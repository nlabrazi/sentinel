class CreateJobExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :job_executions do |t|
      t.references :cron_job, null: false, foreign_key: true
      t.string :status
      t.integer :duration
      t.text :log
      t.datetime :executed_at

      t.timestamps
    end
  end
end
