# db/seeds.rb
projects = [
  { name: "Games Lab",          slug: "games-lab",          repo_url: "https://github.com/nlabrazi/games-lab.git",          branch: "master", production_url: "https://games-lab.nabster.dev",     vps_path: "/srv/projects/games-lab" },
  { name: "Lazarus Exchange",   slug: "lazarus-exchange",   repo_url: "https://github.com/nlabrazi/lazarus-exchange.git",   branch: "main",   production_url: "https://lazarus.nabster.dev",        vps_path: "/srv/projects/lazarus-exchange" },
  { name: "L’escale Gourmande", slug: "lescale-gourmande",  repo_url: "https://github.com/nlabrazi/lescale-gourmande.git",  branch: "master", production_url: "https://lescale.nabster.dev",       vps_path: "/srv/projects/lescale-gourmande" },
  { name: "Media Tools",        slug: "media-tools",        repo_url: "https://github.com/nlabrazi/media-tools.git",        branch: "main",   production_url: "https://media-tools.nabster.dev",     vps_path: "/srv/projects/media-tools" },
  { name: "Monitoring",         slug: "monitoring",         repo_url: "https://github.com/nlabrazi/monitoring.git",         branch: "master", production_url: "https://monitoring.nabster.dev",      vps_path: "/srv/projects/monitoring" },
  { name: "Portfolio",          slug: "portfolio",          repo_url: "https://github.com/nlabrazi/portfolio-3d.git",          branch: "master", production_url: "https://nabster.dev",              vps_path: "/srv/projects/portfolio" },
  { name: "Sawt AI",            slug: "sawt-ai",            repo_url: "https://github.com/nlabrazi/sawt-ai.git",            branch: "main",   production_url: "https://sawt-ai.nabster.dev",         vps_path: "/srv/projects/sawt-ai" },
  { name: "SJV TDM",            slug: "sjvtdm",             repo_url: "https://github.com/nlabrazi/sjvtdm.git",             branch: "master", production_url: "https://sjvtdm.nabster.dev",          vps_path: "/srv/projects/sjvtdm" },
]

projects.each do |attrs|
  Project.find_or_create_by!(slug: attrs[:slug]) do |p|
    p.assign_attributes(attrs)
  end
end
