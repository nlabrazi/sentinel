class AddLatestCommitAvailableToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :latest_commit_available, :string
  end
end
