require 'rails_helper'

RSpec.describe SyncGithubJob, type: :job do
  it 'syncs every project via SyncProjectGithubService' do
    first_project = create(:project)
    second_project = create(:project)
    first_service = instance_double(SyncProjectGithubService, call: true)
    second_service = instance_double(SyncProjectGithubService, call: true)

    allow(SyncProjectGithubService).to receive(:new).with(first_project).and_return(first_service)
    allow(SyncProjectGithubService).to receive(:new).with(second_project).and_return(second_service)

    described_class.perform_now

    expect(first_service).to have_received(:call)
    expect(second_service).to have_received(:call)
  end

  it 'syncs only the target project when project_id is provided' do
    target_project = create(:project)
    other_project = create(:project)
    service = instance_double(SyncProjectGithubService, call: true)

    allow(SyncProjectGithubService).to receive(:new).with(target_project).and_return(service)

    described_class.perform_now(target_project.id)

    expect(service).to have_received(:call)
    expect(SyncProjectGithubService).not_to have_received(:new).with(other_project)
  end

  it 'isolates errors per project and continues processing' do
    failing_project = create(:project, slug: 'failing-app')
    healthy_project = create(:project, slug: 'healthy-app')
    failing_service = instance_double(SyncProjectGithubService)
    healthy_service = instance_double(SyncProjectGithubService, call: true)

    allow(Rails.logger).to receive(:error)
    allow(SyncProjectGithubService).to receive(:new).with(failing_project).and_return(failing_service)
    allow(SyncProjectGithubService).to receive(:new).with(healthy_project).and_return(healthy_service)
    allow(failing_service).to receive(:call).and_raise(StandardError, 'Network timeout')

    described_class.perform_now

    expect(healthy_service).to have_received(:call)
    expect(Rails.logger).to have_received(:error).with(/SyncGithubJob failed for failing-app: Network timeout/)
  end
end
