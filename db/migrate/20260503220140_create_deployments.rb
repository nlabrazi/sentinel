class CreateDeployments < ActiveRecord::Migration[8.1]
  def change
    create_table :deployments do |t|
      t.references :project, null: false, foreign_key: true
      t.string :commit_sha
      t.integer :status
      t.integer :duration
      t.text :log
      t.string :triggered_by

      t.timestamps
    end
  end
end
