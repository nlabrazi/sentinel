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

  it 'handles an exception from GithubService' do
    allow_any_instance_of(GithubService).to receive(:latest_commit_on_branch)
      .and_raise(Octokit::NotFound)
    result = service.call
    expect(result).to eq(false)
    expect(Deployment.count).to eq(0)
  end
end
