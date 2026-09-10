require 'rails_helper'

RSpec.describe SyncProjectGithubService, type: :service do
  let(:project) do
    create(
      :project,
      repo_url: 'https://github.com/nlabrazi/argandici.git',
      production_branch: 'master',
      staging_branch: 'staging',
      last_commit_deployed: 'deployed123'
    )
  end

  let(:github) { instance_double(GithubService) }
  let(:commits_sync) { instance_double(GithubCommitsSyncService, call: 5) }
  let(:pull_requests_sync) { instance_double(GithubPullRequestsSyncService, call: 3) }

  before do
    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(GithubCommitsSyncService).to receive(:new).with(project, limit: 20).and_return(commits_sync)
    allow(GithubPullRequestsSyncService).to receive(:new).with(project, limit: 20).and_return(pull_requests_sync)

    allow(github).to receive(:latest_commit_on_branch).and_return({ sha: 'headsha999' })
    allow(github).to receive(:commits_behind).with('deployed123').and_return(2)
    allow(github).to receive(:compare_branches).with('master', 'staging').and_return({ ahead_by: 4, behind_by: 1 })
  end

  describe '#call' do
    it 'synchronizes commits, pull requests, and drift metrics' do
      service = described_class.new(project)

      expect(service.call).to be true
      expect(service.synced_commits_count).to eq(5)
      expect(service.synced_pull_requests_count).to eq(3)

      project.reload
      expect(project.latest_commit_available).to eq('headsha999')
      expect(project.commits_behind).to eq(2)
      expect(project.staging_commits_ahead).to eq(4)
      expect(project.staging_commits_behind).to eq(1)
      expect(project.github_synced_at).to be_present
    end

    it 'sets commits_behind to 0 when no commit has been deployed' do
      project.update!(last_commit_deployed: nil)

      service = described_class.new(project)

      expect(service.call).to be true
      expect(github).not_to have_received(:commits_behind)
      expect(project.reload.commits_behind).to eq(0)
    end

    it 'resets staging drift to 0 when project has no staging branch' do
      project.update!(staging_branch: nil)

      service = described_class.new(project)

      expect(service.call).to be true
      expect(github).not_to have_received(:compare_branches)
      expect(project.reload.staging_commits_ahead).to eq(0)
      expect(project.reload.staging_commits_behind).to eq(0)
    end

    it 'returns false and skips synchronization when repository is not configured' do
      unconfigured_project = build(:project, repo_url: nil)

      service = described_class.new(unconfigured_project)

      expect(service.call).to be false
      expect(GithubService).not_to have_received(:new)
    end

    it 'rescues errors, logs warning, and returns false when GitHub API raises' do
      allow(github).to receive(:latest_commit_on_branch).and_raise(StandardError, 'GitHub timeout')
      allow(Rails.logger).to receive(:error)

      service = described_class.new(project)

      expect(service.call).to be false
      expect(Rails.logger).to have_received(:error).with(/GitHub sync failed for #{project.slug}: StandardError: GitHub timeout/)
    end

    it 'allows injecting custom services and custom limits' do
      custom_github = instance_double(GithubService)
      custom_commits = instance_double(GithubCommitsSyncService, call: 1)
      custom_prs = instance_double(GithubPullRequestsSyncService, call: 1)

      allow(custom_github).to receive(:latest_commit_on_branch).and_return({ sha: 'customsha' })
      allow(custom_github).to receive(:commits_behind).with('deployed123').and_return(0)
      allow(custom_github).to receive(:compare_branches).with('master', 'staging').and_return({ ahead_by: 0, behind_by: 0 })

      service = described_class.new(
        project,
        github_service: custom_github,
        commits_sync_service: custom_commits,
        pull_requests_sync_service: custom_prs,
        commits_limit: 10,
        pull_requests_limit: 10
      )

      expect(service.call).to be true
      expect(service.synced_commits_count).to eq(1)
      expect(service.synced_pull_requests_count).to eq(1)
      expect(project.reload.latest_commit_available).to eq('customsha')
    end
  end
end
