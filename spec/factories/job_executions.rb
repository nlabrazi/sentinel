FactoryBot.define do
  factory :job_execution do
    cron_job
    status { "success" }
    duration { 1 }
    log { "MyText" }
    executed_at { Time.zone.parse("2026-05-04 00:01:55") }
  end
end
