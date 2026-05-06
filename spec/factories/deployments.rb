FactoryBot.define do
  factory :deployment do
    project
    commit_sha { "abcdef1234567890" }
    status { :success }
    duration { 12 }
    log { "Deploy OK" }
    triggered_by { "web" }
  end
end
