class SyncCommitStatusJob < ApplicationJob
  queue_as :default

  def perform
    Project.find_each do |project|
      next if project.last_commit_deployed.blank?

      begin
        github = GithubService.new(project)
        behind = github.commits_behind(project.last_commit_deployed)
        project.update!(commits_behind: behind)
      rescue StandardError => e
        Rails.logger.error "SyncCommitStatusJob failed for #{project.slug}: #{e.message}"
      end
    end
  end
end
