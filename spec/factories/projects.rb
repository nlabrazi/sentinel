FactoryBot.define do
  factory :project do
    name { Faker::App.name } # Nous ajouterons la gem faker plus tard, sinon utiliser une chaîne fixe
    slug { name.parameterize }
    repo_url { "https://github.com/user/#{slug}.git" }
    branch { "master" }
    production_url { "https://#{slug}.example.com" }
    vps_path { "/srv/projects/#{slug}" }
    status { :unknown }
    maintenance_mode { false }
    last_commit_deployed { nil }
    commits_behind { 0 }
  end
end
