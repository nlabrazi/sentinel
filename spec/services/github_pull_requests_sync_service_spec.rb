require 'rails_helper'

RSpec.describe GithubPullRequestsSyncService, type: :service do
  it 'stores recent GitHub pull requests for a project' do
    project = create(:project)
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:recent_pull_requests).with(limit: 20).and_return([
      {
        number: 12,
        title: 'Add release visibility',
        state: 'merged',
        draft: false,
        author_login: 'nlabrazi',
        head_ref: 'feature/release-visibility',
        base_ref: 'main',
        opened_at: Time.zone.parse('2026-05-06T08:00:00Z'),
        closed_at: Time.zone.parse('2026-05-07T08:00:00Z'),
        merged_at: Time.zone.parse('2026-05-07T08:00:00Z'),
        github_updated_at: Time.zone.parse('2026-05-07T08:01:00Z'),
        html_url: 'https://github.com/user/project/pull/12'
      }
    ])

    expect(described_class.new(project).call).to eq(1)

    pull_request = project.github_pull_requests.find_by!(number: 12)
    expect(pull_request.title).to eq('Add release visibility')
    expect(pull_request.state).to eq('merged')
    expect(pull_request.author_login).to eq('nlabrazi')
  end

  it 'updates existing pull requests instead of duplicating them' do
    project = create(:project)
    create(:github_pull_request, project: project, number: 12, title: 'Old title')
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:recent_pull_requests).with(limit: 20).and_return([
      { number: 12, title: 'New title', state: 'open', draft: false }
    ])

    described_class.new(project).call

    expect(project.github_pull_requests.where(number: 12).count).to eq(1)
    expect(project.github_pull_requests.find_by!(number: 12).title).to eq('New title')
  end
end
