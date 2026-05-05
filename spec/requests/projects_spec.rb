require 'rails_helper'

RSpec.describe 'Projects', type: :request do
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
