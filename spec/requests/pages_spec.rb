require 'rails_helper'

RSpec.describe 'Pages', type: :request do
  describe 'GET /settings' do
    it 'renders settings for authenticated users' do
      sign_in create(:user)

      get settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Settings for')
      expect(response.body).to include('Sentinel')
      expect(response.body).to include('General app settings')
      expect(response.body).to include('Application details')
      expect(response.body).to include('Application information')
      expect(response.body).to include('Access policy')
      expect(response.body).to include('Environment variables')
      expect(response.body).to include('Access &amp; security')
      expect(CGI.unescapeHTML(response.body)).to include('Access & security')
      expect(response.body).not_to include('Configuration de l’application (placeholder).')
      expect(response.body).not_to include('Team details')
      expect(response.body).not_to include('Team information')
      expect(response.body).not_to include('team member(s)')
      expect(response.body).not_to include('Notifications')
      expect(response.body).not_to include('Danger zone')
      expect(response.body).not_to include('Manage through code')
      expect(response.body).not_to include('Read-only settings')
    end

    it 'renders operational triggers and background worker observability' do
      sign_in create(:user)

      get settings_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Actions d'exploitation globales")
      expect(response.body).to include('Healthcheck global')
      expect(response.body).to include('Sync GitHub global')
      expect(response.body).to include('Sync Crons VPS')
      expect(response.body).to include("Workers &amp; Tâches d'arrière-plan")
      expect(response.body).to include('Solid Queue actif')
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

  describe 'POST /settings/trigger_healthcheck' do
    it 'enqueues a HealthcheckAllJob and redirects with notice' do
      sign_in create(:user)
      expect {
        post trigger_healthcheck_settings_path
      }.to have_enqueued_job(HealthcheckAllJob)

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include('Healthcheck global déclenché')
    end
  end

  describe 'POST /settings/trigger_sync_github' do
    it 'enqueues a SyncGithubJob and redirects with notice' do
      sign_in create(:user)
      expect {
        post trigger_sync_github_settings_path
      }.to have_enqueued_job(SyncGithubJob)

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include('Synchronisation GitHub déclenchée')
    end
  end

  describe 'POST /settings/trigger_sync_cron' do
    it 'enqueues a CronStatusJob and redirects with notice' do
      sign_in create(:user)
      expect {
        post trigger_sync_cron_settings_path
      }.to have_enqueued_job(CronStatusJob)

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include('Synchronisation des statuts cron déclenchée')
    end
  end

  describe 'GET /deploys' do
    it 'renders the latest deployments newest first' do
      sign_in create(:user)
      project = create(:project, name: 'Deployable')
      old_deployment = create(:deployment, project: project, commit_sha: 'oldcommit', created_at: 2.days.ago)
      new_deployment = create(:deployment, project: project, commit_sha: 'newcommit', created_at: 5.minutes.ago)

      get deploys_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Deployments')
      expect(response.body).to include('Latest deployment activity across managed projects.')
      expect(response.body).to include('Total')
      expect(response.body).to include('Success')
      expect(response.body).to include('Failed')
      expect(response.body).to include('Deployable')
      expect(response.body.index('newcomm')).to be < response.body.index('oldcomm')
      expect(response.body).to include(deployment_path(new_deployment))
      expect(response.body).to include(deployment_path(old_deployment))
      expect(response.body).not_to include('Derniers déploiements')
    end

    it 'limits the global deployment history to the 20 newest records' do
      sign_in create(:user)
      project = create(:project)
      oldest_deployment = create(
        :deployment,
        project: project,
        commit_sha: 'oldestcommit',
        created_at: 30.days.ago
      )
      newest_deployment = create(
        :deployment,
        project: project,
        commit_sha: 'newestcommit',
        created_at: 1.minute.ago
      )

      19.times do |index|
        create(
          :deployment,
          project: project,
          commit_sha: "middlecommit#{index}",
          created_at: (index + 2).minutes.ago
        )
      end

      get deploys_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('newestc')
      expect(response.body).to include(deployment_path(newest_deployment))
      expect(response.body).not_to include('oldest')
      expect(response.body).not_to include(deployment_path(oldest_deployment))
    end

    it 'filters deployments by project' do
      sign_in create(:user)
      project_a = create(:project, name: 'Alpha Project')
      project_b = create(:project, name: 'Beta Project')
      deploy_a = create(:deployment, project: project_a, commit_sha: 'alphacommit')
      deploy_b = create(:deployment, project: project_b, commit_sha: 'betacommit')

      get deploys_path, params: { project_id: project_a.id }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(deployment_path(deploy_a))
      expect(response.body).not_to include(deployment_path(deploy_b))
    end

    it 'filters deployments by status' do
      sign_in create(:user)
      project = create(:project)
      deploy_success = create(:deployment, project: project, status: :success, commit_sha: 'succ123')
      deploy_failed = create(:deployment, project: project, status: :failed, commit_sha: 'fail123')

      get deploys_path, params: { status: 'failed' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(deployment_path(deploy_failed))
      expect(response.body).not_to include(deployment_path(deploy_success))
    end

    it 'searches deployments by commit SHA or project name' do
      sign_in create(:user)
      project_search = create(:project, name: 'Target App')
      project_other = create(:project, name: 'Other App')
      deploy_match = create(:deployment, project: project_search, commit_sha: 'findme123')
      deploy_other = create(:deployment, project: project_other, commit_sha: 'hidden456')

      get deploys_path, params: { q: 'Target' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(deployment_path(deploy_match))
      expect(response.body).not_to include(deployment_path(deploy_other))
    end

    it 'displays an active alert banner when a deployment is running' do
      sign_in create(:user)
      project = create(:project, name: 'Live Deploy Project')
      running_deploy = create(:deployment, project: project, status: :running, commit_sha: 'runcommit1')

      get deploys_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('déploiement en cours')
      expect(response.body).to include('Live Deploy Project')
      expect(response.body).to include(deployment_path(running_deploy))
    end
  end

  describe 'GET /documentation' do
    it 'renders product documentation for authenticated users' do
      sign_in create(:user)

      get documentation_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Sentinel product overview')
      expect(response.body).to include('Une console simple pour suivre')
      expect(response.body).to include('Cron visibility')
      expect(response.body).to include('/srv/apps/&lt;project&gt;/sentinel/cron-status.json')
      expect(response.body).to include('Sync cron')
      expect(response.body).to include('status.sh')
      expect(response.body).to include('Aucun sudo')
      expect(response.body).to include('Questions fréquentes')
      expect(response.body).to include('Est-ce que Sentinel remplace une CI/CD complète ?')
      expect(response.body).to include('docker compose exec sentinel-api bundle exec rspec')
      expect(response.body.scan('<details').size).to eq(4)
    end
  end
end
