class SyncGithubCommitsJob < ApplicationJob
  queue_as :default

  def perform(project_id = nil)
    projects = project_id ? Project.where(id: project_id) : Project.all

    projects.find_each do |project|
      GithubCommitsSyncService.new(project).call
    rescue StandardError => e
      Rails.logger.error "SyncGithubCommitsJob failed for #{project.slug}: #{e.message}"
    end
  end
end
