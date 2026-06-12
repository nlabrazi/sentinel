class AddCronMonitoringEnabledToProjects < ActiveRecord::Migration[8.1]
  class MigrationProject < ApplicationRecord
    self.table_name = "projects"
  end

  class MigrationCronJob < ApplicationRecord
    self.table_name = "cron_jobs"
  end

  def up
    add_column :projects, :cron_monitoring_enabled, :boolean, default: false, null: false

    monitored_project_ids = MigrationProject
      .where.not(cron_synced_at: nil)
      .or(MigrationProject.where(id: MigrationCronJob.select(:project_id).distinct))
      .distinct
      .pluck(:id)

    MigrationProject.where(id: monitored_project_ids).update_all(cron_monitoring_enabled: true)
  end

  def down
    remove_column :projects, :cron_monitoring_enabled
  end
end
