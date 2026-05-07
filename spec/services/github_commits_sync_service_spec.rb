require 'rails_helper'

RSpec.describe GithubCommitsSyncService, type: :service do
  it 'stores recent GitHub commits for a project' do
    project = create(:project)
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:recent_commits).with(limit: 20).and_return([
      {
        sha: 'abc123',
        message: 'Add cron visibility',
        author_name: 'Nicolas Labrazi',
        author_login: 'nlabrazi',
        authored_at: Time.zone.parse('2026-05-07T08:00:00Z'),
        committed_at: Time.zone.parse('2026-05-07T08:01:00Z'),
        html_url: 'https://github.com/user/project/commit/abc123'
      }
    ])

    expect(described_class.new(project).call).to eq(1)

    commit = project.github_commits.find_by!(sha: 'abc123')
    expect(commit.message).to eq('Add cron visibility')
    expect(commit.author_login).to eq('nlabrazi')
    expect(commit.committed_at).to eq(Time.zone.parse('2026-05-07T08:01:00Z'))
  end

  it 'updates existing commits instead of duplicating them' do
    project = create(:project)
    create(:github_commit, project: project, sha: 'abc123', message: 'Old message')
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:recent_commits).with(limit: 20).and_return([
      { sha: 'abc123', message: 'New message' }
    ])

    described_class.new(project).call

    expect(project.github_commits.where(sha: 'abc123').count).to eq(1)
    expect(project.github_commits.find_by!(sha: 'abc123').message).to eq('New message')
  end
end
