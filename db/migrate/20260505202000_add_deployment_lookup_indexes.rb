class AddDeploymentLookupIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :deployments, :created_at
    add_index :deployments, [ :project_id, :created_at ]
  end
end
