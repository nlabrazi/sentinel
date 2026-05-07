class CreateGithubPullRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :github_pull_requests do |t|
      t.references :project, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :title, null: false
      t.string :state, null: false
      t.boolean :draft, null: false, default: false
      t.string :author_login
      t.string :head_ref
      t.string :base_ref
      t.datetime :opened_at
      t.datetime :closed_at
      t.datetime :merged_at
      t.datetime :github_updated_at
      t.string :html_url

      t.timestamps
    end

    add_index :github_pull_requests, [ :project_id, :number ], unique: true
    add_index :github_pull_requests, [ :project_id, :state ]
    add_index :github_pull_requests, [ :project_id, :github_updated_at ]
  end
end
