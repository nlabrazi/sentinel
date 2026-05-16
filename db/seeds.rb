projects = [
  { name: "Argan d'ici",        slug: "argandici",          grafana_app_value: "argandici",          kind: "app",      repo_url: "https://github.com/nlabrazi/argandici.git",          branch: "master", production_url: "https://argandici.com",                 vps_path: "/srv/apps/argandici" },
  { name: "Games Lab",          slug: "games-lab",          grafana_app_value: "games-lab",          kind: "app",      repo_url: "https://github.com/nlabrazi/games-lab.git",          branch: "master", production_url: "https://games-lab.nabster.dev",         vps_path: "/srv/apps/games-lab" },
  { name: "Lazarus Exchange",   slug: "lazarus-exchange",   grafana_app_value: "lazarus-exchange",   kind: "app",      repo_url: "https://github.com/nlabrazi/lazarus-exchange.git",   branch: "master", production_url: "https://lazarus-exchange.nabster.dev",  vps_path: "/srv/apps/lazarus-exchange" },
  { name: "L’escale Gourmande", slug: "lescale-gourmande",  grafana_app_value: "lescale-gourmande",  kind: "app",      repo_url: "https://github.com/nlabrazi/lescale-gourmande.git",  branch: "master", production_url: "https://lescale-gourmande.nabster.dev", vps_path: "/srv/apps/lescale-gourmande" },
  { name: "Media Tools",        slug: "media-tools",        grafana_app_value: "media-tools",        kind: "app",      repo_url: "https://github.com/nlabrazi/media-tools.git",        branch: "master", production_url: "https://media-tools.nabster.dev",       vps_path: "/srv/apps/media-tools" },
  { name: "Portfolio",          slug: "portfolio",          grafana_app_value: "portfolio",          kind: "app",      repo_url: "https://github.com/nlabrazi/portfolio-3d.git",       branch: "master", production_url: "https://nabster.dev",                   vps_path: "/srv/apps/portfolio" },
  { name: "Sawt AI",            slug: "sawt-ai",            grafana_app_value: "sawt-ai",            kind: "app",      repo_url: "https://github.com/nlabrazi/sawt-ai.git",            branch: "master", production_url: "https://sawt-ai.nabster.dev",           vps_path: "/srv/apps/sawt-ai" },
  { name: "SJVTDM",             slug: "sjvtdm",             grafana_app_value: "sjvtdm",             kind: "service",  repo_url: "https://github.com/nlabrazi/sjvtdm.git",             branch: "master", production_url: "https://sjvtdm.nabster.dev",            vps_path: "/srv/apps/sjvtdm" },
  { name: "Umami",              slug: "umami",              grafana_app_value: "umami",              kind: "service",  repo_url: nil,                                                  branch: nil,      production_url: "https://umami.nabster.dev",             vps_path: "/srv/apps/umami" }
]

projects.each do |attrs|
  project = Project.find_or_initialize_by(slug: attrs[:slug])
  was_new = project.new_record?
  project.update!(attrs)
  puts was_new ? "✅ Créé : #{project.name} (#{project.slug})" : "🔄 Mis à jour : #{project.name} (#{project.slug})"
end

puts "\n🌱 Seed terminée : #{Project.count} projet(s) en base."

admin_username = ENV.fetch("ADMIN_USERNAME", "admin")
admin_email = ENV["ADMIN_EMAIL"].presence || "#{admin_username}@sentinel.local"
admin_password = ENV["ADMIN_PASSWORD"].presence

if admin_password.present?
  admin = User.find_by(username: admin_username) || User.find_or_initialize_by(email: admin_email)
  admin.username = admin_username
  admin.email = admin_email
  admin.password = admin_password
  admin.password_confirmation = admin_password
  admin.save!

  puts "👤 Admin prêt : #{admin.username}"
else
  puts "ℹ️  Admin non créé. Définissez ADMIN_PASSWORD dans .env puis relancez bin/rails db:seed"
end
