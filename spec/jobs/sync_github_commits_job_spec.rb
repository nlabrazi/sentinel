require 'rails_helper'

RSpec.describe SyncGithubCommitsJob, type: :job do
  it 'syncs commits for every project via GithubCommitsSyncService' do
    first_project = create(:project)
    second_project = create(:project)
    first_service = instance_double(GithubCommitsSyncService, call: 5)
    second_service = instance_double(GithubCommitsSyncService, call: 3)

    allow(GithubCommitsSyncService).to receive(:new).with(first_project).and_return(first_service)
    allow(GithubCommitsSyncService).to receive(:new).with(second_project).and_return(second_service)

    described_class.perform_now

    expect(first_service).to have_received(:call)
    expect(second_service).to have_received(:call)
  end

  it 'syncs commits for a single project when project_id is provided' do
    target_project = create(:project)
    other_project = create(:project)
    service = instance_double(GithubCommitsSyncService, call: 2)

    allow(GithubCommitsSyncService).to receive(:new).with(target_project).and_return(service)

    described_class.perform_now(target_project.id)

    expect(service).to have_received(:call)
    expect(GithubCommitsSyncService).not_to have_received(:new).with(other_project)
  end

  it 'isolates errors per project and continues processing' do
    failing_project = create(:project, slug: 'failing')
    healthy_project = create(:project, slug: 'healthy')
    failing_service = instance_double(GithubCommitsSyncService)
    healthy_service = instance_double(GithubCommitsSyncService, call: 1)

    allow(Rails.logger).to receive(:error)
    allow(GithubCommitsSyncService).to receive(:new).with(failing_project).and_return(failing_service)
    allow(GithubCommitsSyncService).to receive(:new).with(healthy_project).and_return(healthy_service)
    allow(failing_service).to receive(:call).and_raise(StandardError, 'API rate limited')

    described_class.perform_now

    expect(healthy_service).to have_received(:call)
    expect(Rails.logger).to have_received(:error).with(/SyncGithubCommitsJob failed for failing: API rate limited/)
  end
end
