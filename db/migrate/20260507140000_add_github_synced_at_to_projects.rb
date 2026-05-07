class AddGithubSyncedAtToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :github_synced_at, :datetime
  end
end
