FactoryBot.define do
  factory :github_commit do
    project
    sequence(:sha) { |n| "abcdef#{n.to_s.rjust(34, '0')}" }
    message { "Improve deployment visibility" }
    author_name { "Nicolas Labrazi" }
    author_login { "nlabrazi" }
    authored_at { 1.hour.ago }
    committed_at { authored_at }
    html_url { "https://github.com/user/project/commit/#{sha}" }
  end
end
