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
