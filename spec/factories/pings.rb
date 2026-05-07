FactoryBot.define do
  factory :ping do
    project
    status { "online" }
    http_status { 200 }
    response_time_ms { 120 }
    error { nil }
    checked_at { Time.current }
  end
end
