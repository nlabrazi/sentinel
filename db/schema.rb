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

ActiveRecord::Schema[8.1].define(version: 2026_05_04_000056) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["project_id"], name: "index_deployments_on_project_id"
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
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "projects", force: :cascade do |t|
    t.string "branch"
    t.integer "commits_behind"
    t.datetime "created_at", null: false
    t.string "last_commit_deployed"
    t.boolean "maintenance_mode"
    t.string "name"
    t.string "production_url"
    t.string "repo_url"
    t.string "screenshot_url"
    t.string "slug"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.string "vps_path"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  add_foreign_key "cron_jobs", "projects"
  add_foreign_key "deployments", "projects"
  add_foreign_key "job_executions", "cron_jobs"
end
