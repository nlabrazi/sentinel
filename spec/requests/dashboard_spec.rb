require 'rails_helper'

RSpec.describe "Dashboards", type: :request do
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

    it "renders the latest deployment timestamp for each project" do
      sign_in create(:user)
      project = create(:project, name: "Deployable", last_commit_deployed: "abcdef123")
      create(:deployment, project: project, created_at: 2.days.ago)
      create(:deployment, project: project, created_at: 5.minutes.ago)

      get root_path

      expect(response.body).to include("Deployable")
      expect(response.body).to include("5 minutes")
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
end
