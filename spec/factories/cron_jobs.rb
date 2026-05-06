FactoryBot.define do
  factory :cron_job do
    project
    sequence(:name) { |n| "job-#{n}" }
    command { "./bin/run-job" }
    schedule { "0 2 * * *" }
    last_execution_at { Time.zone.parse("2026-05-04 00:01:49") }
    last_status { "success" }
    last_duration { 1 }
  end
end
