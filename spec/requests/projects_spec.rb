require 'rails_helper'

RSpec.describe 'Projects', type: :request do
  describe 'GET /projects/:id' do
    it 'renders the project deployment history newest first' do
      sign_in create(:user)
      project = create(:project)
      create(:deployment, project: project, commit_sha: 'oldcommit', created_at: 2.days.ago)
      create(:deployment, project: project, commit_sha: 'newcommit', created_at: 5.minutes.ago)

      get project_path(project)

      expect(response).to have_http_status(:success)
      expect(response.body.index('newcomm')).to be < response.body.index('oldcomm')
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
      expect(response.body).to include('xl:grid-cols')
      expect(response.body).not_to include('Build with an AI agent')
      expect(response.body).not_to include('Protect and secure access to your project')
      expect(response.body).not_to include('Synthetic activity placeholder')
      expect(response.body).not_to include('Preview Servers')
      expect(response.body).not_to include('Web security')
      expect(response.body).not_to include('Domain management')
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
