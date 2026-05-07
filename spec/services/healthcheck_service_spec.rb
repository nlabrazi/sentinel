require 'rails_helper'

RSpec.describe HealthcheckService, type: :service do
  let(:project) { create(:project, production_url: 'https://www.example.com') }
  let(:service) { described_class.new(project) }

  it 'updates status to online if request succeeds' do
    stub_request(:get, project.production_url).to_return(status: 200)

    expect(service.call).to eq(:online)

    project.reload
    expect(project.status).to eq('online')
    expect(project.pings.last).to have_attributes(
      status: 'online',
      http_status: 200,
      error: nil
    )
    expect(project.pings.last.response_time_ms).to be >= 0
  end

  it 'updates status to offline if request fails' do
    stub_request(:get, project.production_url).to_return(status: 500)

    service.call

    project.reload
    expect(project.status).to eq('offline')
    expect(project.pings.last).to have_attributes(
      status: 'offline',
      http_status: 500,
      error: nil
    )
  end

  it 'uses bounded HTTP options' do
    response = instance_double(HTTParty::Response, success?: true, code: 200)
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
    expect(project.pings.last.status).to eq('offline')
    expect(project.pings.last.http_status).to be_nil
    expect(project.pings.last.error).to include('HTTParty::Error')
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
