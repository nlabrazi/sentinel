require 'rails_helper'

RSpec.describe CronStatusJob, type: :job do
  it 'syncs every project and isolates project-level failures' do
    first_project = create(:project, cron_monitoring_enabled: true)
    second_project = create(:project, cron_monitoring_enabled: true)
    first_service = instance_double(CronStatusSyncService)
    second_service = instance_double(CronStatusSyncService)

    allow(CronStatusSyncService).to receive(:new).with(first_project).and_return(first_service)
    allow(CronStatusSyncService).to receive(:new).with(second_project).and_return(second_service)
    allow(first_service).to receive(:call).and_raise(StandardError, 'boom')
    allow(second_service).to receive(:call).and_return(true)
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(second_service).to have_received(:call)
    expect(Rails.logger).to have_received(:error).with(/CronStatusJob failed/)
  end

  it 'skips projects with cron monitoring disabled' do
    monitored_project = create(:project, cron_monitoring_enabled: true)
    disabled_project = create(:project, cron_monitoring_enabled: false)
    monitored_service = instance_double(CronStatusSyncService, call: true)

    allow(CronStatusSyncService).to receive(:new).with(monitored_project).and_return(monitored_service)

    described_class.perform_now

    expect(monitored_service).to have_received(:call)
    expect(CronStatusSyncService).not_to have_received(:new).with(disabled_project)
  end
end
