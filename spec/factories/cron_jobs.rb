FactoryBot.define do
  factory :cron_job do
    project
    sequence(:name) { |n| "job-#{n}" }
    command { "./bin/run-job" }
    schedule { "0 2 * * *" }
    last_execution_at { Time.current }
    last_status { "success" }
    last_duration { 1 }
  end
end
