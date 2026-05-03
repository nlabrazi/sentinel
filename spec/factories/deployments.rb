FactoryBot.define do
  factory :deployment do
    project { nil }
    commit_sha { "MyString" }
    status { 1 }
    duration { 1 }
    log { "MyText" }
    triggered_by { "MyString" }
  end
end
