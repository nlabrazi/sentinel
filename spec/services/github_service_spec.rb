require 'rails_helper'

RSpec.describe GithubService, type: :service do
  let(:project) { build(:project, repo_url: 'https://github.com/nlabrazi/argandici.git', branch: 'main') }
  let(:client) { instance_double(Octokit::Client) }
  let(:service) { described_class.new(project) }

  before do
    allow(Octokit::Client).to receive(:new).and_return(client)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#latest_commit_on_branch' do
    it 'returns the latest commit on the project branch' do
      allow(client).to receive(:ref)
        .with('nlabrazi/argandici', 'heads/main')
        .and_return({ object: { sha: 'abc123' } })
      allow(client).to receive(:commit)
        .with('nlabrazi/argandici', 'abc123')
        .and_return({ sha: 'abc123' })

      expect(service.latest_commit_on_branch).to eq({ sha: 'abc123' })
    end

    it 'returns nil and logs when GitHub lookup fails' do
      allow(client).to receive(:ref).and_raise(Octokit::TooManyRequests)

      expect(service.latest_commit_on_branch).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/GitHub latest commit lookup failed/)
    end
  end

  describe '#commits_behind' do
    it 'returns zero when no base SHA is available' do
      allow(client).to receive(:compare)

      expect(service.commits_behind(nil)).to eq(0)
      expect(client).not_to have_received(:compare)
    end

    it 'returns the number of commits behind the remote branch' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'abc123', 'heads/main')
        .and_return({ ahead_by: 3 })

      expect(service.commits_behind('abc123')).to eq(3)
    end

    it 'returns zero and logs when GitHub comparison fails' do
      allow(client).to receive(:compare).and_raise(Faraday::TimeoutError)

      expect(service.commits_behind('abc123')).to eq(0)
      expect(Rails.logger).to have_received(:warn).with(/GitHub commit comparison failed/)
    end
  end

  describe '#recent_commits' do
    it 'returns normalized recent commits for the project branch' do
      allow(client).to receive(:commits)
        .with('nlabrazi/argandici', sha: 'main', per_page: 20)
        .and_return([
          {
            sha: 'abc123',
            html_url: 'https://github.com/nlabrazi/argandici/commit/abc123',
            author: { login: 'nlabrazi' },
            commit: {
              message: "Add Sentinel commit visibility\n\nLonger body",
              author: { name: 'Nicolas Labrazi', date: Time.zone.parse('2026-05-07T08:00:00Z') },
              committer: { date: Time.zone.parse('2026-05-07T08:01:00Z') }
            }
          }
        ])

      expect(service.recent_commits).to eq([
        {
          sha: 'abc123',
          message: 'Add Sentinel commit visibility',
          author_name: 'Nicolas Labrazi',
          author_login: 'nlabrazi',
          authored_at: Time.zone.parse('2026-05-07T08:00:00Z'),
          committed_at: Time.zone.parse('2026-05-07T08:01:00Z'),
          html_url: 'https://github.com/nlabrazi/argandici/commit/abc123'
        }
      ])
    end

    it 'returns an empty list and logs when GitHub commit history lookup fails' do
      allow(client).to receive(:commits).and_raise(Octokit::TooManyRequests)

      expect(service.recent_commits).to eq([])
      expect(Rails.logger).to have_received(:warn).with(/GitHub recent commits lookup failed/)
    end
  end
end
