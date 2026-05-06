require 'rails_helper'

RSpec.describe DeployProjectService, type: :service do
  let(:project) { create(:project) }
  let(:service) { described_class.new(project) }

  before do
    # Stub GithubService pour éviter tout appel réseau
    allow_any_instance_of(GithubService).to receive(:latest_commit_on_branch)
      .and_return({ sha: 'abc123' })
    # Stub SshExecutionService pour simuler une exécution réussie
    allow_any_instance_of(SshExecutionService).to receive(:execute)
      .and_return({ exit_code: 0, stdout: 'Deploy OK', stderr: '' })
    allow(project).to receive(:regenerate_screenshot!)
  end

  it 'creates a deployment with success status' do
    expect { service.call }.to change(Deployment, :count).by(1)
    deployment = Deployment.last
    expect(deployment.status).to eq('success')
    expect(deployment.commit_sha).to eq('abc123')
  end

  it 'updates project after successful deploy' do
    service.call
    project.reload
    expect(project.last_commit_deployed).to eq('abc123')
    expect(project.commits_behind).to eq(0)
  end

  it 'handles SSH failure gracefully' do
    allow_any_instance_of(SshExecutionService).to receive(:execute)
      .and_return({ exit_code: 1, stdout: '', stderr: 'Command not found' })
    service.call
    deployment = Deployment.last
    expect(deployment.status).to eq('failed')
    # Le projet n'est pas mis à jour en cas d'échec
    project.reload
    expect(project.last_commit_deployed).to be_nil
  end

  it 'truncates oversized deployment logs before storing them' do
    allow_any_instance_of(SshExecutionService).to receive(:execute)
      .and_return({
        exit_code: 1,
        stdout: 'o' * (DeployProjectService::MAX_LOG_BYTES + 1_000),
        stderr: 'Command failed'
      })

    service.call

    deployment = Deployment.last
    expect(deployment.log.bytesize).to eq(DeployProjectService::MAX_LOG_BYTES)
    expect(deployment.log).to end_with(DeployProjectService::TRUNCATED_LOG_NOTICE)
  end

  it 'handles an exception from GithubService' do
    allow_any_instance_of(GithubService).to receive(:latest_commit_on_branch)
      .and_raise(Octokit::NotFound)
    result = service.call
    expect(result).to eq(false)
    expect(Deployment.count).to eq(0)
  end

  it 'does not start a second deployment while one is already running' do
    create(:deployment, project: project, status: :running)

    expect(GithubService).not_to receive(:new)

    result = service.call

    expect(result).to eq(false)
    expect(project.deployments.count).to eq(1)
  end

  it 'does not execute SSH when another deployment starts after the GitHub lookup' do
    allow_any_instance_of(GithubService).to receive(:latest_commit_on_branch) do
      create(:deployment, project: project, status: :running)
      { sha: 'abc123' }
    end
    expect(SshExecutionService).not_to receive(:new)

    result = service.call

    expect(result).to eq(false)
    expect(project.deployments.running.count).to eq(1)
  end
end
