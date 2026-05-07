FactoryBot.define do
  factory :github_pull_request do
    project
    sequence(:number)
    title { "Add release visibility" }
    state { "open" }
    draft { false }
    author_login { "nlabrazi" }
    head_ref { "feature/release-visibility" }
    base_ref { "main" }
    opened_at { 2.days.ago }
    github_updated_at { 1.hour.ago }
    html_url { "https://github.com/user/project/pull/#{number}" }
  end
end
