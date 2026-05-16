require 'rails_helper'

RSpec.describe "Dashboards", type: :request do
  DASHBOARD_GRAFANA_ENV_KEYS = %w[
    GRAFANA_BASE_URL
    GRAFANA_DASHBOARD_UID
    GRAFANA_DASHBOARD_SLUG
    GRAFANA_VARIABLE_NAME
    GRAFANA_DEFAULT_THEME
    GRAFANA_ORG_ID
    GRAFANA_DEFAULT_FROM
    GRAFANA_DEFAULT_TO
    GRAFANA_DEFAULT_TIMEZONE
    GRAFANA_REFRESH
    GRAFANA_PANEL_ID
    GRAFANA_GLOBAL_VARIABLE_VALUE
    GRAFANA_EMBED_URL
  ].freeze

  around do |example|
    original_env = DASHBOARD_GRAFANA_ENV_KEYS.to_h { |key| [key, ENV[key]] }

    DASHBOARD_GRAFANA_ENV_KEYS.each { |key| ENV.delete(key) }
    example.run
  ensure
    DASHBOARD_GRAFANA_ENV_KEYS.each do |key|
      if original_env[key].nil?
        ENV.delete(key)
      else
        ENV[key] = original_env[key]
      end
    end
  end

  describe "GET /" do
    it "redirects anonymous users to the login page" do
      get root_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "returns http success for authenticated users" do
      sign_in create(:user)

      get root_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Search projects")
      expect(response.body).to include("Projects")
      expect(response.body).to include("Online")
      expect(response.body).to include("Behind")
      expect(response.body).to include("Jobs issues")
      expect(response.body).to include("Maintenance")
      expect(response.body).not_to include("Add new project")
      expect(response.body).not_to include("Want to deploy a new project?")
      expect(response.body).to include("Deployments")
      expect(response.body).to include("Settings")
      expect(response.body).to include("Documentation")
      expect(response.body).to include("Docs")
      expect(response.body).to include("lg:flex")
      expect(response.body).not_to include("Builds")
      expect(response.body).not_to include("Extensions")
      expect(response.body).not_to include("DNS")
      expect(response.body).not_to include("Members")
      expect(response.body).not_to include("Security Scorecard")
      expect(response.body).not_to include("Usage & billing")
      expect(response.body).not_to include("Visual editor dashboard")
      expect(response.body).not_to include("Upgrade")
      expect(response.body).not_to include("News")
      expect(response.body).not_to include("Support")
      expect(response.body).not_to include("Mis à jour il y a quelques secondes")
    end

    it "renders the global Grafana embed when configured" do
      configure_grafana_env
      sign_in create(:user)

      get root_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Global observability")
      expect(response.body).to include('title="Global Grafana dashboard"')
      expect(response.body).to include(
        'src="https://grafana.example.com/d-solo/apps-overview/applications-overview?orgId=1&amp;from=now-6h&amp;to=now&amp;timezone=browser&amp;refresh=30s&amp;theme=dark&amp;panelId=panel-6&amp;var-app=All"'
      )
      expect(response.body).to include("Ouvrir dans Grafana")
      expect(response.body).to include('sandbox="allow-scripts allow-same-origin allow-forms allow-popups"')
    end

    it "renders the latest deployment timestamp for each project" do
      sign_in create(:user)
      project = create(:project, name: "Deployable", last_commit_deployed: "abcdef123")
      create(:deployment, project: project, created_at: 2.days.ago)
      create(:deployment, project: project, created_at: 5.minutes.ago)

      get root_path

      expect(response.body).to include("Deployable")
      expect(response.body).to include("5 minutes")
    end

    it "renders release, runtime, cron, pull requests and deploy controls for each project" do
      sign_in create(:user)
      project = create(
        :project,
        name: "Sawt AI",
        repo_url: "https://github.com/nlabrazi/sawt-ai.git",
        branch: "main",
        production_url: "https://sawt.example.com",
        status: :online,
        last_commit_deployed: "a82f31c999",
        latest_commit_available: "a91dd20999",
        commits_behind: 3,
        github_synced_at: 4.minutes.ago,
        cron_synced_at: 2.minutes.ago
      )
      create(:cron_job, project: project, last_status: "success")
      create(:ping, project: project, http_status: 200, response_time_ms: 88, checked_at: 3.minutes.ago)
      create(:github_pull_request, project: project, state: "open", title: "Open PR")
      create(:github_pull_request, project: project, state: "merged", title: "Merged PR")

      get root_path

      expect(response.body).to include("Sawt AI")
      expect(response.body).to include("https://sawt.example.com")
      expect(response.body).to include("nlabrazi/sawt-ai")
      expect(response.body).to include("GitHub")
      expect(response.body).to include("a82f31c")
      expect(response.body).to include("3 update(s)")
      expect(response.body).to include("OK")
      expect(response.body).to include("open PR")
      expect(response.body).to include("merged")
      expect(response.body).to include("Sync GitHub")
      expect(response.body).to include("Check health")
      expect(response.body).to include("Sync jobs")
      expect(response.body).to include("Runtime")
      expect(response.body).to include("HTTP")
      expect(response.body).to include("200")
      expect(response.body).to include("Jobs")
      expect(response.body).to include("Deploy")
      expect(response.body).to include("Open project")
      expect(response.body).to include("Open site")
    end

    it "renders a running state instead of the deploy action when a project is deploying" do
      sign_in create(:user)
      project = create(:project, name: "Running Project")
      create(:deployment, project: project, status: :running)

      get root_path

      expect(response.body).to include("Running Project")
      expect(response.body).to include("Running")
      expect(response.body).not_to include("Deploy latest")
    end

    it "filters projects by search query" do
      sign_in create(:user)
      create(:project, name: "Searchable Alpha", slug: "searchable-alpha")
      create(:project, name: "Hidden Beta", slug: "hidden-beta")

      get root_path, params: { q: "alpha" }

      expect(response.body).to include("Searchable Alpha")
      expect(response.body).not_to include("Hidden Beta")
    end
  end

  def configure_grafana_env
    ENV["GRAFANA_BASE_URL"] = "https://grafana.example.com"
    ENV["GRAFANA_DASHBOARD_UID"] = "apps-overview"
    ENV["GRAFANA_DASHBOARD_SLUG"] = "applications-overview"
    ENV["GRAFANA_VARIABLE_NAME"] = "app"
    ENV["GRAFANA_DEFAULT_THEME"] = "dark"
    ENV["GRAFANA_ORG_ID"] = "1"
    ENV["GRAFANA_DEFAULT_FROM"] = "now-6h"
    ENV["GRAFANA_DEFAULT_TO"] = "now"
    ENV["GRAFANA_DEFAULT_TIMEZONE"] = "browser"
    ENV["GRAFANA_REFRESH"] = "30s"
    ENV["GRAFANA_PANEL_ID"] = "panel-6"
    ENV["GRAFANA_GLOBAL_VARIABLE_VALUE"] = "All"
  end
end
