require 'rails_helper'

RSpec.describe CronStatusJob, type: :job do
  it 'syncs every project and isolates project-level failures' do
    first_project = create(:project)
    second_project = create(:project)
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
end
