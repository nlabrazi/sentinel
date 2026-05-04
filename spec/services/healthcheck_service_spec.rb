require 'rails_helper'

RSpec.describe HealthcheckService, type: :service do
  let(:project) { create(:project, production_url: 'https://www.example.com') }

  it 'updates status to online if request succeeds' do
    stub_request(:get, project.production_url).to_return(status: 200)
    service = described_class.new(project)
    service.call
    project.reload
    expect(project.status).to eq('online')
  end

  it 'updates status to offline if request fails' do
    stub_request(:get, project.production_url).to_return(status: 500)
    service = described_class.new(project)
    service.call
    project.reload
    expect(project.status).to eq('offline')
  end

  it 'updates status to offline on timeout/exception' do
    stub_request(:get, project.production_url).to_raise(HTTParty::Error)
    service = described_class.new(project)
    service.call
    project.reload
    expect(project.status).to eq('offline')
  end
end
