require 'rails_helper'

RSpec.describe SyncCommitStatusJob, type: :job do
  it 'stores the latest remote commit and behind count for deployed projects' do
    project = create(:project, last_commit_deployed: 'prod123')
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:latest_commit_on_branch).and_return({ sha: 'head456' })
    allow(github).to receive(:commits_behind).with('prod123').and_return(4)

    described_class.perform_now

    expect(project.reload.latest_commit_available).to eq('head456')
    expect(project.commits_behind).to eq(4)
  end

  it 'stores the latest remote commit for projects without a deployed commit' do
    project = create(:project, last_commit_deployed: nil, commits_behind: 2)
    github = instance_double(GithubService)

    allow(GithubService).to receive(:new).with(project).and_return(github)
    allow(github).to receive(:latest_commit_on_branch).and_return({ sha: 'head456' })
    expect(github).not_to receive(:commits_behind)

    described_class.perform_now

    expect(project.reload.latest_commit_available).to eq('head456')
    expect(project.commits_behind).to eq(0)
  end
end
