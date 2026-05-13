require 'rails_helper'

RSpec.describe 'Projects', type: :request do
  describe 'GET /projects/:id' do
    it 'renders the project deployment history newest first' do
      sign_in create(:user)
      project = create(:project)
      other_project = create(:project)
      old_deployment = create(:deployment, project: project, commit_sha: 'oldcommit', created_at: 2.days.ago)
      new_deployment = create(:deployment, project: project, commit_sha: 'newcommit', created_at: 5.minutes.ago)
      other_deployment = create(:deployment, project: other_project, commit_sha: 'othercommit', created_at: 1.minute.ago)

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body.index('newcomm')).to be < response.body.index('oldcomm')
      expect(response.body).to include(deployment_path(new_deployment))
      expect(response.body).to include(deployment_path(old_deployment))
      expect(response.body).not_to include(other_deployment.commit_sha.first(7))
      expect(response.body).not_to include(deployment_path(other_deployment))
    end

    it 'limits the project deployment history to the 20 newest records' do
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

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('newestc')
      expect(response.body).to include(deployment_path(newest_deployment))
      expect(response.body).not_to include('oldest')
      expect(response.body).not_to include(deployment_path(oldest_deployment))
    end

    it 'renders the project overview layout with compact sidebar' do
      sign_in create(:user)
      project = create(
        :project,
        name: 'Project Overview',
        slug: 'project-overview',
        production_url: 'https://project-overview.example.com',
        last_commit_deployed: 'abcdef123',
        github_synced_at: 6.minutes.ago,
        cron_synced_at: 8.minutes.ago
      )
      create(:deployment, project: project, commit_sha: 'abcdef123', status: :success, created_at: 5.minutes.ago)

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-sidebar-collapsed-value="true"')
      expect(response.body).to include('href="/favicon.ico"')
      expect(response.body).to include('src="/favicon.ico"')
      expect(response.body).to include('Project overview')
      expect(response.body).to include('Release status')
      expect(response.body).to include('Recent commits')
      expect(response.body).to include('Pull requests')
      expect(response.body).to include('GitHub synced')
      expect(response.body).to include('Sync GitHub')
      expect(response.body).to include('Sync jobs')
      expect(response.body).to include('Deployment command')
      expect(response.body).to include('Cron jobs')
      expect(response.body).to include('Cron synced')
      expect(response.body).to include('Production deploys')
      expect(response.body).to include('Healthcheck')
      expect(response.body).to include('Current status')
      expect(response.body).to include('Production URL')
      expect(response.body).to include('Last check')
      expect(response.body).to include('Last result')
      expect(response.body).to include('HTTP code')
      expect(response.body).to include('Response time')
      expect(response.body).to include('Last error')
      expect(response.body).to include('Check status')
      expect(response.body).to include('Latest deployment')
      expect(response.body).to include('Deploy state')
      expect(response.body).to include('Idle')
      expect(response.body).to include('xl:grid-cols')
      expect(response.body).not_to include('Build with an AI agent')
      expect(response.body).not_to include('Protect and secure access to your project')
      expect(response.body).not_to include('Synthetic activity placeholder')
      expect(response.body).not_to include('Preview Servers')
      expect(response.body).not_to include('Web security')
      expect(response.body).not_to include('Domain management')
    end

    it 'renders recent GitHub pull requests newest first' do
      sign_in create(:user)
      project = create(:project)
      old_pull_request = create(
        :github_pull_request,
        project: project,
        number: 12,
        title: 'Old pull request',
        state: 'closed',
        author_login: 'old-author',
        head_ref: 'old-branch',
        base_ref: 'main',
        github_updated_at: 2.days.ago
      )
      new_pull_request = create(
        :github_pull_request,
        project: project,
        number: 13,
        title: 'New pull request',
        state: 'merged',
        author_login: 'new-author',
        head_ref: 'new-branch',
        base_ref: 'main',
        github_updated_at: 5.minutes.ago
      )
      other_pull_request = create(:github_pull_request, title: 'Other project pull request')

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body.index('New pull request')).to be < response.body.index('Old pull request')
      expect(response.body).to include("##{new_pull_request.number}")
      expect(response.body).to include("##{old_pull_request.number}")
      expect(response.body).to include('new-author')
      expect(response.body).to include('new-branch')
      expect(response.body).to include('merged')
      expect(response.body).not_to include(other_pull_request.title)
    end

    it 'renders recent GitHub commits newest first' do
      sign_in create(:user)
      project = create(:project)
      old_commit = create(
        :github_commit,
        project: project,
        sha: 'oldcommit123',
        message: 'Old commit',
        author_login: 'old-author',
        committed_at: 2.days.ago
      )
      new_commit = create(
        :github_commit,
        project: project,
        sha: 'newcommit123',
        message: 'New commit',
        author_login: 'new-author',
        committed_at: 5.minutes.ago,
        html_url: 'https://github.com/user/project/commit/newcommit123'
      )
      other_commit = create(:github_commit, message: 'Other project commit')

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body.index('New commit')).to be < response.body.index('Old commit')
      expect(response.body).to include(new_commit.sha.first(7))
      expect(response.body).to include(old_commit.sha.first(7))
      expect(response.body).to include('new-author')
      expect(response.body).not_to include(other_commit.message)
    end

    it 'renders detailed cron job status' do
      sign_in create(:user)
      project = create(:project)
      cron_job = create(
        :cron_job,
        project: project,
        name: 'daily-import',
        command: './bin/daily-import',
        schedule: '0 2 * * *',
        last_execution_at: Time.zone.parse('2026-05-06T02:00:12Z'),
        last_status: 'failed',
        last_duration: 42
      )
      create(:job_execution, cron_job: cron_job, executed_at: cron_job.last_execution_at, log: 'Import failed on row 12')

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('daily-import')
      expect(response.body).to include('./bin/daily-import')
      expect(response.body).to include('0 2 * * *')
      expect(response.body).to include('failed')
      expect(response.body).to include('42s')
      expect(response.body).to include('Import failed on row 12')
    end

    it 'renders the latest healthcheck details' do
      sign_in create(:user)
      project = create(:project, status: :offline)
      create(
        :ping,
        project: project,
        status: 'offline',
        http_status: 503,
        response_time_ms: 456,
        error: 'Net::ReadTimeout: execution expired',
        checked_at: Time.zone.parse('2026-05-06T10:15:00Z')
      )

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('offline')
      expect(response.body).to include('503')
      expect(response.body).to include('456 ms')
      expect(response.body).to include('Net::ReadTimeout: execution expired')
    end

    it 'renders a running deployment state instead of the deploy action' do
      sign_in create(:user)
      project = create(:project)
      create(:deployment, project: project, status: :running, commit_sha: 'runningcommit')

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Deploy running')
      expect(response.body).to include('Running')
      expect(response.body).not_to include('Deploy latest')
    end
  end

  describe 'POST /projects/:id/deploy' do
    let(:user) { create(:user) }
    let(:project) { create(:project) }

    before do
      sign_in user
    end

    it 'enqueues a deploy job when no deployment is running' do
      allow(DeployProjectJob).to receive(:perform_later)

      post deploy_project_path(project)

      expect(DeployProjectJob).to have_received(:perform_later).with(project.id)
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq('Déploiement lancé en arrière-plan.')
    end

    it 'does not enqueue another deploy job when one is already running' do
      create(:deployment, project: project, status: :running)
      allow(DeployProjectJob).to receive(:perform_later)

      post deploy_project_path(project)

      expect(DeployProjectJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq('Un déploiement est déjà en cours pour ce projet.')
    end
  end

  describe 'POST /projects/:id/refresh_github_commits' do
    let(:user) { create(:user) }
    let(:project) { create(:project) }

    before do
      sign_in user
    end

    it 'synchronizes GitHub commits for the project' do
      commits_service = instance_double(GithubCommitsSyncService, call: 3)
      pull_requests_service = instance_double(GithubPullRequestsSyncService, call: 2)
      allow(GithubCommitsSyncService).to receive(:new).with(project).and_return(commits_service)
      allow(GithubPullRequestsSyncService).to receive(:new).with(project).and_return(pull_requests_service)

      post refresh_github_commits_project_path(project)

      expect(commits_service).to have_received(:call)
      expect(pull_requests_service).to have_received(:call)
      expect(project.reload.github_synced_at).to be_present
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq('3 commit(s) et 2 pull request(s) synchronisé(s) depuis GitHub.')
    end

    it 'redirects back after GitHub synchronization when a previous page is available' do
      commits_service = instance_double(GithubCommitsSyncService, call: 1)
      pull_requests_service = instance_double(GithubPullRequestsSyncService, call: 0)
      allow(GithubCommitsSyncService).to receive(:new).with(project).and_return(commits_service)
      allow(GithubPullRequestsSyncService).to receive(:new).with(project).and_return(pull_requests_service)

      post refresh_github_commits_project_path(project), headers: { 'HTTP_REFERER' => root_url }

      expect(response).to redirect_to(root_url)
    end

    it 'shows an alert when GitHub synchronization fails' do
      commits_service = instance_double(GithubCommitsSyncService)
      allow(GithubCommitsSyncService).to receive(:new).with(project).and_return(commits_service)
      allow(commits_service).to receive(:call).and_raise(StandardError, 'GitHub is unavailable')

      post refresh_github_commits_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq('Synchronisation GitHub impossible pour le moment.')
    end
  end

  describe 'POST /projects/:id/refresh_runtime' do
    let(:user) { create(:user) }
    let(:project) { create(:project) }

    before do
      sign_in user
    end

    it 'runs an immediate healthcheck for the project' do
      service = instance_double(HealthcheckService, call: :online)
      allow(HealthcheckService).to receive(:new).with(project).and_return(service)

      post refresh_runtime_project_path(project)

      expect(service).to have_received(:call)
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq('Healthcheck terminé : online.')
    end

    it 'redirects back after runtime refresh when a previous page is available' do
      service = instance_double(HealthcheckService, call: :offline)
      allow(HealthcheckService).to receive(:new).with(project).and_return(service)

      post refresh_runtime_project_path(project), headers: { 'HTTP_REFERER' => root_url }

      expect(response).to redirect_to(root_url)
    end

    it 'shows an alert when runtime refresh fails' do
      service = instance_double(HealthcheckService)
      allow(HealthcheckService).to receive(:new).with(project).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError, 'HTTP unavailable')

      post refresh_runtime_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq('Healthcheck impossible pour le moment.')
    end
  end

  describe 'POST /projects/:id/refresh_cron_status' do
    let(:user) { create(:user) }
    let(:project) { create(:project) }

    before do
      sign_in user
    end

    it 'runs an immediate cron status sync for the project' do
      service = instance_double(CronStatusSyncService, call: true)
      allow(CronStatusSyncService).to receive(:new).with(project).and_return(service)

      post refresh_cron_status_project_path(project)

      expect(service).to have_received(:call)
      expect(project.reload.cron_synced_at).to be_present
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq('Statuts cron synchronisés.')
    end

    it 'redirects back after cron status sync when a previous page is available' do
      service = instance_double(CronStatusSyncService, call: true)
      allow(CronStatusSyncService).to receive(:new).with(project).and_return(service)

      post refresh_cron_status_project_path(project), headers: { 'HTTP_REFERER' => root_url }

      expect(response).to redirect_to(root_url)
    end

    it 'shows an alert when the cron status script cannot be synchronized' do
      service = instance_double(CronStatusSyncService, call: false)
      allow(CronStatusSyncService).to receive(:new).with(project).and_return(service)

      post refresh_cron_status_project_path(project)

      expect(project.reload.cron_synced_at).to be_nil
      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq('Synchronisation cron impossible pour le moment.')
    end

    it 'shows an alert when cron status synchronization raises an error' do
      service = instance_double(CronStatusSyncService)
      allow(CronStatusSyncService).to receive(:new).with(project).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError, 'SSH unavailable')

      post refresh_cron_status_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq('Synchronisation cron impossible pour le moment.')
    end
  end

  describe 'PATCH /projects/:id/toggle_maintenance' do
    let(:user) { create(:user) }
    let(:project) { create(:project, maintenance_mode: false) }

    before do
      sign_in user
    end

    it 'updates maintenance_mode only after the SSH command succeeds' do
      ssh = instance_double(SshExecutionService)
      allow(SshExecutionService).to receive(:new).and_return(ssh)
      allow(ssh).to receive(:execute)
        .with(project.maintenance_command(true))
        .and_return({ exit_code: 0, stdout: '', stderr: '' })

      patch toggle_maintenance_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(project.reload.maintenance_mode).to eq(true)
    end

    it 'keeps the previous maintenance_mode when the SSH command fails' do
      ssh = instance_double(SshExecutionService)
      allow(SshExecutionService).to receive(:new).and_return(ssh)
      allow(ssh).to receive(:execute)
        .with(project.maintenance_command(true))
        .and_return({ exit_code: 1, stdout: '', stderr: 'permission denied' })

      patch toggle_maintenance_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(project.reload.maintenance_mode).to eq(false)
      expect(flash[:alert]).to include('permission denied')
    end
  end
end
