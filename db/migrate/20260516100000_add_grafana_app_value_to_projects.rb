class AddGrafanaAppValueToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :grafana_app_value, :string
  end
end
