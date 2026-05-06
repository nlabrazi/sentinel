FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "Project #{n}" }
    slug { name.parameterize }
    repo_url { "https://github.com/user/#{slug}.git" }
    branch { "master" }
    production_url { "https://#{slug}.example.com" }
    vps_path { "/srv/apps/#{slug}" }
    status { :unknown }
    maintenance_mode { false }
    last_commit_deployed { nil }
    commits_behind { 0 }
  end
end
