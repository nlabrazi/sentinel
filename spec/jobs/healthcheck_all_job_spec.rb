require 'rails_helper'

RSpec.describe HealthcheckAllJob, type: :job do
  it 'checks every project' do
    projects = create_list(:project, 2)
    default_service = instance_double(HealthcheckService, call: :online)

    allow(HealthcheckService).to receive(:new).and_return(default_service)
    projects.each do |project|
      service = instance_double(HealthcheckService, call: :online)
      allow(HealthcheckService).to receive(:new).with(project).and_return(service)
    end

    described_class.perform_now

    projects.each do |project|
      expect(HealthcheckService).to have_received(:new).with(project)
    end
  end

  it 'continues when one project healthcheck fails' do
    failed_project = create(:project, slug: 'broken')
    healthy_project = create(:project, slug: 'healthy')
    default_service = instance_double(HealthcheckService, call: :online)
    failed_service = instance_double(HealthcheckService)
    healthy_service = instance_double(HealthcheckService, call: :online)

    allow(Rails.logger).to receive(:error)
    allow(HealthcheckService).to receive(:new).and_return(default_service)
    allow(HealthcheckService).to receive(:new).with(failed_project).and_return(failed_service)
    allow(HealthcheckService).to receive(:new).with(healthy_project).and_return(healthy_service)
    allow(failed_service).to receive(:call).and_raise(StandardError, 'boom')

    described_class.perform_now

    expect(healthy_service).to have_received(:call)
    expect(Rails.logger).to have_received(:error).with(/HealthcheckAllJob failed for broken: boom/)
  end
end
