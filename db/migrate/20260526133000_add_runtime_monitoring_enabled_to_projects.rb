class AddRuntimeMonitoringEnabledToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :runtime_monitoring_enabled, :boolean, default: true, null: false
  end
end
