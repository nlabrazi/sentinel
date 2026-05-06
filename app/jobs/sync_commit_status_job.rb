class SyncCommitStatusJob < ApplicationJob
  queue_as :default

  def perform
    Project.find_each do |project|
      begin
        github = GithubService.new(project)
        latest_commit = github.latest_commit_on_branch
        latest_commit_sha = latest_commit&.fetch(:sha, nil)
        behind = project.last_commit_deployed.present? ? github.commits_behind(project.last_commit_deployed) : 0

        project.update!(
          latest_commit_available: latest_commit_sha,
          commits_behind: behind
        )
      rescue StandardError => e
        Rails.logger.error "SyncCommitStatusJob failed for #{project.slug}: #{e.message}"
      end
    end
  end
end
