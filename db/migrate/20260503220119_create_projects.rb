class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :slug
      t.string :repo_url
      t.string :branch
      t.string :production_url
      t.string :vps_path
      t.integer :status
      t.string :last_commit_deployed
      t.integer :commits_behind
      t.boolean :maintenance_mode

      t.timestamps
    end
    add_index :projects, :slug, unique: true
  end
end
