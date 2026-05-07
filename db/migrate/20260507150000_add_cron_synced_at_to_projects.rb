class AddCronSyncedAtToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :cron_synced_at, :datetime
  end
end
