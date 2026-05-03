FactoryBot.define do
  factory :cron_job do
    project { nil }
    name { "MyString" }
    command { "MyString" }
    schedule { "MyString" }
    last_execution_at { "2026-05-04 00:01:49" }
    last_status { "MyString" }
    last_duration { 1 }
  end
end
