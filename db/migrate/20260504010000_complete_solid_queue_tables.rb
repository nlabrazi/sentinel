class CompleteSolidQueueTables < ActiveRecord::Migration[8.1]
  def up
    create_solid_queue_blocked_executions
    create_solid_queue_claimed_executions
    create_solid_queue_failed_executions
    create_solid_queue_ready_executions
    create_solid_queue_recurring_executions
    create_solid_queue_recurring_tasks
    create_solid_queue_semaphores
    complete_solid_queue_jobs_indexes
    complete_solid_queue_scheduled_executions_indexes
    complete_solid_queue_processes_columns
  end

  def down
    drop_table :solid_queue_semaphores, if_exists: true
    drop_table :solid_queue_recurring_tasks, if_exists: true
    drop_table :solid_queue_recurring_executions, if_exists: true
    drop_table :solid_queue_ready_executions, if_exists: true
    drop_table :solid_queue_failed_executions, if_exists: true
    drop_table :solid_queue_claimed_executions, if_exists: true
    drop_table :solid_queue_blocked_executions, if_exists: true
  end

  private

  def create_solid_queue_blocked_executions
    return if table_exists?(:solid_queue_blocked_executions)

    create_table :solid_queue_blocked_executions do |t|
      t.references :job, null: false, index: false, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.string :concurrency_key, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
      t.index [ :concurrency_key, :priority, :job_id ], name: "index_solid_queue_blocked_executions_for_release"
      t.index [ :expires_at, :concurrency_key ], name: "index_solid_queue_blocked_executions_for_maintenance"
    end
  end

  def create_solid_queue_claimed_executions
    return if table_exists?(:solid_queue_claimed_executions)

    create_table :solid_queue_claimed_executions do |t|
      t.references :job, null: false, index: false, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.bigint :process_id
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
      t.index [ :process_id, :job_id ], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
    end
  end

  def create_solid_queue_failed_executions
    return if table_exists?(:solid_queue_failed_executions)

    create_table :solid_queue_failed_executions do |t|
      t.references :job, null: false, index: false, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.text :error
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_failed_executions_on_job_id", unique: true
    end
  end

  def create_solid_queue_ready_executions
    return if table_exists?(:solid_queue_ready_executions)

    create_table :solid_queue_ready_executions do |t|
      t.references :job, null: false, index: false, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_ready_executions_on_job_id", unique: true
      t.index [ :priority, :job_id ], name: "index_solid_queue_poll_all"
      t.index [ :queue_name, :priority, :job_id ], name: "index_solid_queue_poll_by_queue"
    end
  end

  def create_solid_queue_recurring_executions
    return if table_exists?(:solid_queue_recurring_executions)

    create_table :solid_queue_recurring_executions do |t|
      t.references :job, null: false, index: false, foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.string :task_key, null: false
      t.datetime :run_at, null: false
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
      t.index [ :task_key, :run_at ], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
    end
  end

  def create_solid_queue_recurring_tasks
    return if table_exists?(:solid_queue_recurring_tasks)

    create_table :solid_queue_recurring_tasks do |t|
      t.string :key, null: false
      t.string :schedule, null: false
      t.string :command, limit: 2048
      t.string :class_name
      t.text :arguments
      t.string :queue_name
      t.integer :priority, default: 0
      t.boolean :static, default: true, null: false
      t.text :description
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index [ :key ], name: "index_solid_queue_recurring_tasks_on_key", unique: true
      t.index [ :static ], name: "index_solid_queue_recurring_tasks_on_static"
    end
  end

  def create_solid_queue_semaphores
    return if table_exists?(:solid_queue_semaphores)

    create_table :solid_queue_semaphores do |t|
      t.string :key, null: false
      t.integer :value, default: 1, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index [ :expires_at ], name: "index_solid_queue_semaphores_on_expires_at"
      t.index [ :key, :value ], name: "index_solid_queue_semaphores_on_key_and_value"
      t.index [ :key ], name: "index_solid_queue_semaphores_on_key", unique: true
    end
  end

  def complete_solid_queue_jobs_indexes
    add_index :solid_queue_jobs, [ :class_name ], name: "index_solid_queue_jobs_on_class_name" unless index_exists?(:solid_queue_jobs, [ :class_name ], name: "index_solid_queue_jobs_on_class_name")
    add_index :solid_queue_jobs, [ :finished_at ], name: "index_solid_queue_jobs_on_finished_at" unless index_exists?(:solid_queue_jobs, [ :finished_at ], name: "index_solid_queue_jobs_on_finished_at")
  end

  def complete_solid_queue_scheduled_executions_indexes
    unless index_exists?(:solid_queue_scheduled_executions, [ :job_id ], name: "index_solid_queue_scheduled_executions_on_job_id")
      add_index :solid_queue_scheduled_executions, [ :job_id ], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    end

    unless index_exists?(:solid_queue_scheduled_executions, [ :scheduled_at, :priority, :job_id ], name: "index_solid_queue_dispatch_all")
      add_index :solid_queue_scheduled_executions, [ :scheduled_at, :priority, :job_id ], name: "index_solid_queue_dispatch_all"
    end
  end

  def complete_solid_queue_processes_columns
    add_column :solid_queue_processes, :supervisor_id, :bigint unless column_exists?(:solid_queue_processes, :supervisor_id)
    add_column :solid_queue_processes, :metadata, :text unless column_exists?(:solid_queue_processes, :metadata)

    unless index_exists?(:solid_queue_processes, [ :name, :supervisor_id ], name: "index_solid_queue_processes_on_name_and_supervisor_id")
      add_index :solid_queue_processes, [ :name, :supervisor_id ], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    end

    unless index_exists?(:solid_queue_processes, [ :supervisor_id ], name: "index_solid_queue_processes_on_supervisor_id")
      add_index :solid_queue_processes, [ :supervisor_id ], name: "index_solid_queue_processes_on_supervisor_id"
    end
  end
end
