class AddV2BranchAndStatusFieldsToProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :production_branch, :string, default: "master", null: false
    add_column :projects, :staging_branch, :string, default: "staging"
    add_column :projects, :staging_commits_ahead, :integer, default: 0, null: false
    add_column :projects, :staging_commits_behind, :integer, default: 0, null: false
    add_column :projects, :status_changed_at, :datetime

    execute <<~SQL.squish
      UPDATE projects
      SET production_branch = COALESCE(NULLIF(branch, ''), 'master')
    SQL
  end

  def down
    remove_column :projects, :production_branch
    remove_column :projects, :staging_branch
    remove_column :projects, :staging_commits_ahead
    remove_column :projects, :staging_commits_behind
    remove_column :projects, :status_changed_at
  end
end
