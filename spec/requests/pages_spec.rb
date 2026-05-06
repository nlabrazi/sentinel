require 'rails_helper'

RSpec.describe 'Pages', type: :request do
  describe 'GET /settings' do
    it 'renders settings for authenticated users' do
      sign_in create(:user)

      get settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Settings for Sentinel')
      expect(response.body).to include('General app settings')
      expect(response.body).to include('Application details')
      expect(response.body).to include('Application information')
      expect(response.body).to include('Access policy')
      expect(response.body).to include('Environment variables')
      expect(response.body).to include('Access & security')
      expect(response.body).not_to include('Configuration de l’application (placeholder).')
      expect(response.body).not_to include('Team details')
      expect(response.body).not_to include('Team information')
      expect(response.body).not_to include('team member(s)')
      expect(response.body).not_to include('Notifications')
      expect(response.body).not_to include('Danger zone')
      expect(response.body).not_to include('Manage through code')
      expect(response.body).not_to include('Read-only settings')
    end

    it 'does not render secret values' do
      sign_in create(:user)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('super-secret-token')

      get settings_path

      expect(response.body).to include('GitHub token')
      expect(response.body).to include('Configured')
      expect(response.body).not_to include('super-secret-token')
    end
  end

  describe 'GET /deploys' do
    it 'renders the latest deployments newest first' do
      sign_in create(:user)
      project = create(:project, name: 'Deployable')
      create(:deployment, project: project, commit_sha: 'oldcommit', created_at: 2.days.ago)
      create(:deployment, project: project, commit_sha: 'newcommit', created_at: 5.minutes.ago)

      get deploys_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Deployable')
      expect(response.body.index('newcomm')).to be < response.body.index('oldcomm')
    end
  end

  describe 'GET /documentation' do
    it 'renders product documentation for authenticated users' do
      sign_in create(:user)

      get documentation_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Sentinel product overview')
      expect(response.body).to include('Une console simple pour suivre')
      expect(response.body).to include('Questions fréquentes')
      expect(response.body).to include('Est-ce que Sentinel remplace une CI/CD complète ?')
      expect(response.body).to include('docker compose exec sentinel-api bundle exec rspec')
      expect(response.body.scan('<details').size).to eq(4)
    end
  end
end
