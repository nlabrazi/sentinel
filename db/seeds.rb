projects = [
  { name: "Games Lab",          slug: "games-lab",          repo_url: "https://github.com/nlabrazi/games-lab.git",          branch: "master", production_url: "https://games-lab.nabster.dev",       vps_path: "/srv/projects/games-lab" },
  { name: "Lazarus Exchange",   slug: "lazarus-exchange",   repo_url: "https://github.com/nlabrazi/lazarus-exchange.git",   branch: "main",   production_url: "https://lazarus-exchange.nabster.dev",  vps_path: "/srv/projects/lazarus-exchange" },
  { name: "L’escale Gourmande", slug: "lescale-gourmande",  repo_url: "https://github.com/nlabrazi/lescale-gourmande.git",  branch: "master", production_url: "https://lescale-gourmande.nabster.dev", vps_path: "/srv/projects/lescale-gourmande" },
  { name: "Media Tools",        slug: "media-tools",        repo_url: "https://github.com/nlabrazi/media-tools.git",        branch: "main",   production_url: "https://media-tools.nabster.dev",       vps_path: "/srv/projects/media-tools" },
  { name: "Portfolio",          slug: "portfolio",          repo_url: "https://github.com/nlabrazi/portfolio-3d.git",      branch: "master", production_url: "https://nabster.dev",                   vps_path: "/srv/projects/portfolio" },
  { name: "Sawt AI",            slug: "sawt-ai",            repo_url: "https://github.com/nlabrazi/sawt-ai.git",            branch: "main",   production_url: "https://sawt-ai.nabster.dev",           vps_path: "/srv/projects/sawt-ai" },
  { name: "SJVTDM",            slug: "sjvtdm",             repo_url: "https://github.com/nlabrazi/sjvtdm.git",             branch: "master", production_url: "https://sjvtdm.nabster.dev",            vps_path: "/srv/projects/sjvtdm" },
]

projects.each do |attrs|
  project = Project.find_or_initialize_by(slug: attrs[:slug])
  was_new = project.new_record?
  project.update!(attrs)
  puts was_new ? "✅ Créé : #{project.name} (#{project.slug})" : "🔄 Mis à jour : #{project.name} (#{project.slug})"
end

puts "\n🌱 Seed terminée : #{Project.count} projet(s) en base."
