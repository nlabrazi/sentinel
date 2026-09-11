# frozen_string_literal: true

class SyncUmamiJob < ApplicationJob
  queue_as :default

  def perform(project_id = nil)
    projects = if project_id
                 Project.where(id: project_id)
    else
                 Project.where.not(production_url: [ nil, "" ])
                        .or(Project.where.not(umami_website_id: [ nil, "" ]))
    end

    projects.find_each do |project|
      ProjectUmamiSyncService.call(project)
    rescue StandardError => e
      Rails.logger.error("SyncUmamiJob failed for #{project.slug}: #{e.message}")
    end
  end
end
