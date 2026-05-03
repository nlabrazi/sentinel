FactoryBot.define do
  factory :job_execution do
    cron_job { nil }
    status { "MyString" }
    duration { 1 }
    log { "MyText" }
    executed_at { "2026-05-04 00:01:55" }
  end
end
