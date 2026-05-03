class CreateCronJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :cron_jobs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name
      t.string :command
      t.string :schedule
      t.datetime :last_execution_at
      t.string :last_status
      t.integer :last_duration

      t.timestamps
    end
  end
end
