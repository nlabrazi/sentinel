class CreateGithubCommits < ActiveRecord::Migration[8.1]
  def change
    create_table :github_commits do |t|
      t.references :project, null: false, foreign_key: true
      t.string :sha, null: false
      t.string :message, null: false
      t.string :author_name
      t.string :author_login
      t.datetime :authored_at
      t.datetime :committed_at
      t.string :html_url

      t.timestamps
    end

    add_index :github_commits, [ :project_id, :sha ], unique: true
    add_index :github_commits, [ :project_id, :committed_at ]
  end
end
