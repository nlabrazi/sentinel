require 'rails_helper'

RSpec.describe 'Deployments', type: :request do
  describe 'GET /deployments/:id' do
    it 'redirects anonymous users to the login page' do
      deployment = create(:deployment)

      get deployment_path(deployment)

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'renders deployment details and logs' do
      sign_in create(:user)
      project = create(
        :project,
        name: 'Sentinel API',
        branch: 'main',
        vps_path: '/srv/apps/sentinel-api'
      )
      deployment = create(
        :deployment,
        project: project,
        commit_sha: 'abc123def456',
        status: :failed,
        duration: 42,
        triggered_by: 'web',
        log: "Pulling image\nCommand failed"
      )

      get deployment_path(deployment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Deployment abc123d')
      expect(response.body).to include('Sentinel API')
      expect(response.body).to include('failed')
      expect(response.body).to include('abc123def456')
      expect(response.body).to include('main')
      expect(response.body).to include('42s')
      expect(response.body).to include('web')
      expect(response.body).to include('/srv/apps/sentinel-api')
      expect(response.body).to include('Pulling image')
      expect(response.body).to include('Command failed')
    end

    it 'renders an empty log state when no log was recorded' do
      sign_in create(:user)
      deployment = create(:deployment, log: nil)

      get deployment_path(deployment)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('No logs recorded for this deployment.')
    end
  end
end
