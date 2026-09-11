class SyncProjectGithubService
  DEFAULT_LIMIT = 20

  attr_reader :project, :synced_commits_count, :synced_pull_requests_count

  def initialize(
    project,
    github_service: nil,
    commits_sync_service: nil,
    pull_requests_sync_service: nil,
    commits_limit: DEFAULT_LIMIT,
    pull_requests_limit: DEFAULT_LIMIT
  )
    @project = project
    @github_service = github_service
    @commits_sync_service = commits_sync_service
    @pull_requests_sync_service = pull_requests_sync_service
    @commits_limit = commits_limit
    @pull_requests_limit = pull_requests_limit
    @synced_commits_count = 0
    @synced_pull_requests_count = 0
  end

  def call
    return false unless github_configured?

    sync_commits_and_pull_requests
    sync_drift_and_metadata

    true
  rescue StandardError => e
    Rails.logger.error "GitHub sync failed for #{@project.slug}: #{e.class}: #{e.message}"
    false
  end

  private

  def github_configured?
    @project.repo_url.present? && @project.github_repo != "No GitHub repository"
  end

  def sync_commits_and_pull_requests
    @synced_commits_count = commits_sync.call.to_i
    @synced_pull_requests_count = pull_requests_sync.call.to_i
  end

  def sync_drift_and_metadata
    updates = {
      github_synced_at: Time.current
    }

    latest_commit = github.latest_commit_on_branch
    latest_sha = extract_sha(latest_commit)
    updates[:latest_commit_available] = latest_sha if latest_sha.present?

    updates[:commits_behind] = if @project.last_commit_deployed.present?
                                 github.commits_behind(@project.last_commit_deployed).to_i
    else
                                 0
    end

    if @project.staging_branch.present?
      comparison = github.compare_branches(@project.effective_production_branch, @project.staging_branch)
      if comparison.present?
        updates[:staging_commits_ahead] = comparison[:ahead_by].to_i
        updates[:staging_commits_behind] = comparison[:behind_by].to_i
      end
    else
      updates[:staging_commits_ahead] = 0
      updates[:staging_commits_behind] = 0
    end

    @project.update!(updates)
  end

  def extract_sha(commit)
    return commit[:sha] if commit.is_a?(Hash) && commit.key?(:sha)
    return commit["sha"] if commit.is_a?(Hash) && commit.key?("sha")
    return commit.sha if commit.respond_to?(:sha)
    return commit[:sha] if commit.respond_to?(:[]) && commit[:sha].present?

    nil
  end

  def github
    @github_service || GithubService.new(@project)
  end

  def commits_sync
    @commits_sync_service || GithubCommitsSyncService.new(@project, limit: @commits_limit)
  end

  def pull_requests_sync
    @pull_requests_sync_service || GithubPullRequestsSyncService.new(@project, limit: @pull_requests_limit)
  end
end
