require 'rails_helper'

RSpec.describe GithubCommit, type: :model do
  subject(:github_commit) { build(:github_commit) }

  it { is_expected.to belong_to(:project) }
  it { is_expected.to validate_presence_of(:sha) }
  it { is_expected.to validate_presence_of(:message) }
  it { is_expected.to validate_uniqueness_of(:sha).scoped_to(:project_id) }

  it 'allows HTTPS GitHub commit URLs' do
    commit = build(:github_commit, html_url: 'https://github.com/user/project/commit/abc123')

    expect(commit).to be_valid
  end

  it 'rejects non-GitHub URLs' do
    commit = build(:github_commit, html_url: 'https://example.com/phishing')

    expect(commit).not_to be_valid
    expect(commit.errors[:html_url]).to include('must be a HTTPS GitHub URL')
  end

  it 'rejects JavaScript URLs' do
    commit = build(:github_commit, html_url: 'javascript:alert(1)')

    expect(commit).not_to be_valid
    expect(commit.errors[:html_url]).to include('must be a HTTPS GitHub URL')
  end
end
