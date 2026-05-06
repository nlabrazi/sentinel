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
        last_commit_deployed: 'abcdef123'
      )
      create(:deployment, project: project, commit_sha: 'abcdef123', status: :success, created_at: 5.minutes.ago)

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-sidebar-collapsed-value="true"')
      expect(response.body).to include('Project overview')
      expect(response.body).to include('Release readiness')
      expect(response.body).to include('Deployment command')
      expect(response.body).to include('Production deploys')
      expect(response.body).to include('Healthcheck')
      expect(response.body).to include('Current status')
      expect(response.body).to include('Production URL')
      expect(response.body).to include('Latest deployment')
      expect(response.body).to include('Deployment state')
      expect(response.body).to include('Idle')
      expect(response.body).to include('xl:grid-cols')
      expect(response.body).not_to include('Build with an AI agent')
      expect(response.body).not_to include('Protect and secure access to your project')
      expect(response.body).not_to include('Synthetic activity placeholder')
      expect(response.body).not_to include('Preview Servers')
      expect(response.body).not_to include('Web security')
      expect(response.body).not_to include('Domain management')
    end

    it 'renders a running deployment state instead of the deploy action' do
      sign_in create(:user)
      project = create(:project)
      create(:deployment, project: project, status: :running, commit_sha: 'runningcommit')

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Deployment running since')
      expect(response.body).to include('Deploy running')
      expect(response.body).to include('Running')
      expect(response.body).not_to include('Deploy project')
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
