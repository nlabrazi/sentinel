require 'rails_helper'

RSpec.describe GithubPullRequest, type: :model do
  subject(:github_pull_request) { build(:github_pull_request) }

  it { is_expected.to belong_to(:project) }
  it { is_expected.to validate_presence_of(:number) }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:state) }
  it { is_expected.to validate_uniqueness_of(:number).scoped_to(:project_id) }
  it { is_expected.to validate_inclusion_of(:state).in_array(%w[open closed merged]) }

  it 'allows HTTPS GitHub pull request URLs' do
    pull_request = build(:github_pull_request, html_url: 'https://github.com/user/project/pull/12')

    expect(pull_request).to be_valid
  end

  it 'rejects non-GitHub URLs' do
    pull_request = build(:github_pull_request, html_url: 'https://example.com/phishing')

    expect(pull_request).not_to be_valid
    expect(pull_request.errors[:html_url]).to include('must be a HTTPS GitHub URL')
  end
end
