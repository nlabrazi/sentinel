class HealthcheckAllJob < ApplicationJob
  queue_as :default

  def perform
    Project.where(runtime_monitoring_enabled: true).find_each do |project|
      begin
        HealthcheckService.new(project).call
      rescue StandardError => e
        Rails.logger.error "HealthcheckAllJob failed for #{project.slug}: #{e.message}"
      end
    end
  end
end
