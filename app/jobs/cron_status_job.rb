class CronStatusJob < ApplicationJob
  queue_as :default

  def perform
    Project.where(cron_monitoring_enabled: true).find_each do |project|
      begin
        CronStatusSyncService.new(project).call
      rescue StandardError => e
        Rails.logger.error "CronStatusJob failed for #{project.slug}: #{e.message}"
      end
    end
  end
end
