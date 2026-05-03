FactoryBot.define do
  factory :project do
    name { "MyString" }
    slug { "MyString" }
    repo_url { "MyString" }
    branch { "MyString" }
    production_url { "MyString" }
    vps_path { "MyString" }
    status { 1 }
    last_commit_deployed { "MyString" }
    commits_behind { 1 }
    maintenance_mode { false }
  end
end
