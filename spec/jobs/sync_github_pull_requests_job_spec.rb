require 'rails_helper'

RSpec.describe SyncGithubPullRequestsJob, type: :job do
  it 'syncs pull requests for every project via GithubPullRequestsSyncService' do
    first_project = create(:project)
    second_project = create(:project)
    first_service = instance_double(GithubPullRequestsSyncService, call: 4)
    second_service = instance_double(GithubPullRequestsSyncService, call: 2)

    allow(GithubPullRequestsSyncService).to receive(:new).with(first_project).and_return(first_service)
    allow(GithubPullRequestsSyncService).to receive(:new).with(second_project).and_return(second_service)

    described_class.perform_now

    expect(first_service).to have_received(:call)
    expect(second_service).to have_received(:call)
  end

  it 'syncs pull requests for a single project when project_id is provided' do
    target_project = create(:project)
    other_project = create(:project)
    service = instance_double(GithubPullRequestsSyncService, call: 1)

    allow(GithubPullRequestsSyncService).to receive(:new).with(target_project).and_return(service)

    described_class.perform_now(target_project.id)

    expect(service).to have_received(:call)
    expect(GithubPullRequestsSyncService).not_to have_received(:new).with(other_project)
  end

  it 'isolates errors per project and continues processing' do
    failing_project = create(:project, slug: 'failing')
    healthy_project = create(:project, slug: 'healthy')
    failing_service = instance_double(GithubPullRequestsSyncService)
    healthy_service = instance_double(GithubPullRequestsSyncService, call: 1)

    allow(Rails.logger).to receive(:error)
    allow(GithubPullRequestsSyncService).to receive(:new).with(failing_project).and_return(failing_service)
    allow(GithubPullRequestsSyncService).to receive(:new).with(healthy_project).and_return(healthy_service)
    allow(failing_service).to receive(:call).and_raise(StandardError, 'API rate limited')

    described_class.perform_now

    expect(healthy_service).to have_received(:call)
    expect(Rails.logger).to have_received(:error).with(/SyncGithubPullRequestsJob failed for failing: API rate limited/)
  end
end
