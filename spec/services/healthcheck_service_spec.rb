require 'rails_helper'

RSpec.describe HealthcheckService, type: :service do
  let(:project) { create(:project, production_url: 'https://www.example.com') }
  let(:service) { described_class.new(project) }

  it 'updates status to online if request succeeds' do
    stub_request(:get, project.production_url).to_return(status: 200)

    service.call

    project.reload
    expect(project.status).to eq('online')
  end

  it 'updates status to offline if request fails' do
    stub_request(:get, project.production_url).to_return(status: 500)

    service.call

    project.reload
    expect(project.status).to eq('offline')
  end

  it 'uses bounded HTTP options' do
    response = instance_double(HTTParty::Response, success?: true)
    allow(HTTParty).to receive(:get).and_return(response)

    service.call

    expect(HTTParty).to have_received(:get).with(
      project.production_url,
      headers: { "User-Agent" => HealthcheckService::USER_AGENT },
      limit: HealthcheckService::REDIRECT_LIMIT,
      timeout: HealthcheckService::REQUEST_TIMEOUT_SECONDS
    )
  end

  it 'updates status to offline on timeout/exception' do
    allow(Rails.logger).to receive(:warn)
    stub_request(:get, project.production_url).to_raise(HTTParty::Error)

    service.call

    project.reload
    expect(project.status).to eq('offline')
    expect(Rails.logger).to have_received(:warn).with(/Healthcheck failed/)
  end

  it 'updates status to offline when redirects exceed the configured limit' do
    allow(Rails.logger).to receive(:warn)
    response = Net::HTTPFound.new('1.1', '302', 'Found')
    allow(HTTParty).to receive(:get).and_raise(HTTParty::RedirectionTooDeep.new(response))

    expect(service.call).to eq(:offline)

    expect(project.reload.status).to eq('offline')
    expect(Rails.logger).to have_received(:warn).with(/Healthcheck failed/)
  end
end
