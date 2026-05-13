# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_13_214110) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "cron_jobs", force: :cascade do |t|
    t.string "command"
    t.datetime "created_at", null: false
    t.integer "last_duration"
    t.datetime "last_execution_at"
    t.string "last_status"
    t.string "name"
    t.bigint "project_id", null: false
    t.string "schedule"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_cron_jobs_on_project_id"
  end

  create_table "deployments", force: :cascade do |t|
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.integer "duration"
    t.text "log"
    t.bigint "project_id", null: false
    t.integer "status"
    t.string "triggered_by"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_deployments_on_created_at"
    t.index ["project_id", "created_at"], name: "index_deployments_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_deployments_on_project_id"
  end

  create_table "github_commits", force: :cascade do |t|
    t.string "author_login"
    t.string "author_name"
    t.datetime "authored_at"
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.string "html_url"
    t.string "message", null: false
    t.bigint "project_id", null: false
    t.string "sha", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "committed_at"], name: "index_github_commits_on_project_id_and_committed_at"
    t.index ["project_id", "sha"], name: "index_github_commits_on_project_id_and_sha", unique: true
    t.index ["project_id"], name: "index_github_commits_on_project_id"
  end

  create_table "github_pull_requests", force: :cascade do |t|
    t.string "author_login"
    t.string "base_ref"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.boolean "draft", default: false, null: false
    t.datetime "github_updated_at"
    t.string "head_ref"
    t.string "html_url"
    t.datetime "merged_at"
    t.integer "number", null: false
    t.datetime "opened_at"
    t.bigint "project_id", null: false
    t.string "state", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "github_updated_at"], name: "index_github_pull_requests_on_project_id_and_github_updated_at"
    t.index ["project_id", "number"], name: "index_github_pull_requests_on_project_id_and_number", unique: true
    t.index ["project_id", "state"], name: "index_github_pull_requests_on_project_id_and_state"
    t.index ["project_id"], name: "index_github_pull_requests_on_project_id"
  end

  create_table "job_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "cron_job_id", null: false
    t.integer "duration"
    t.datetime "executed_at"
    t.text "log"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["cron_job_id"], name: "index_job_executions_on_cron_job_id"
  end

  create_table "pings", force: :cascade do |t|
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.string "error"
    t.integer "http_status"
    t.string "name"
    t.bigint "project_id"
    t.integer "response_time_ms"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["project_id", "checked_at"], name: "index_pings_on_project_id_and_checked_at"
    t.index ["project_id"], name: "index_pings_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "branch"
    t.integer "commits_behind"
    t.datetime "created_at", null: false
    t.datetime "cron_synced_at"
    t.datetime "github_synced_at"
    t.string "kind", default: "app", null: false
    t.string "last_commit_deployed"
    t.string "latest_commit_available"
    t.boolean "maintenance_mode"
    t.string "name"
    t.string "production_url"
    t.string "repo_url"
    t.string "slug"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "vps_path"
    t.index ["kind"], name: "index_projects_on_kind"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["concurrency_key"], name: "index_solid_queue_jobs_on_concurrency_key"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "cron_jobs", "projects"
  add_foreign_key "deployments", "projects"
  add_foreign_key "github_commits", "projects"
  add_foreign_key "github_pull_requests", "projects"
  add_foreign_key "job_executions", "cron_jobs"
  add_foreign_key "pings", "projects"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
