require 'rails_helper'

RSpec.describe 'Pages', type: :request do
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
end
