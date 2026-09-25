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

  describe '#recent_pull_requests' do
    it 'returns normalized recent pull requests for the repository' do
      allow(client).to receive(:pull_requests)
        .with('nlabrazi/argandici', state: 'all', sort: 'updated', direction: 'desc', per_page: 20)
        .and_return([
          {
            number: 12,
            title: 'Add Pull Request visibility',
            state: 'closed',
            draft: false,
            html_url: 'https://github.com/nlabrazi/argandici/pull/12',
            created_at: Time.zone.parse('2026-05-06T08:00:00Z'),
            closed_at: Time.zone.parse('2026-05-07T08:00:00Z'),
            merged_at: Time.zone.parse('2026-05-07T08:00:00Z'),
            updated_at: Time.zone.parse('2026-05-07T08:01:00Z'),
            user: { login: 'nlabrazi' },
            head: { ref: 'feature/pr-visibility' },
            base: { ref: 'main' }
          }
        ])

      expect(service.recent_pull_requests).to eq([
        {
          number: 12,
          title: 'Add Pull Request visibility',
          state: 'merged',
          draft: false,
          author_login: 'nlabrazi',
          head_ref: 'feature/pr-visibility',
          base_ref: 'main',
          opened_at: Time.zone.parse('2026-05-06T08:00:00Z'),
          closed_at: Time.zone.parse('2026-05-07T08:00:00Z'),
          merged_at: Time.zone.parse('2026-05-07T08:00:00Z'),
          github_updated_at: Time.zone.parse('2026-05-07T08:01:00Z'),
          html_url: 'https://github.com/nlabrazi/argandici/pull/12'
        }
      ])
    end

    it 'returns an empty list and logs when GitHub pull request lookup fails' do
      allow(client).to receive(:pull_requests).and_raise(Octokit::TooManyRequests)

      expect(service.recent_pull_requests).to eq([])
      expect(Rails.logger).to have_received(:warn).with(/GitHub recent pull requests lookup failed/)
    end
  end

  describe '#compare_branches' do
    let(:comparison_payload) do
      {
        ahead_by: 2,
        behind_by: 1,
        status: 'diverged',
        total_commits: 3,
        html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
        permalink_url: 'https://github.com/nlabrazi/argandici/compare/nlabrazi:abc...nlabrazi:def',
        commits: [
          {
            sha: 'commit123',
            html_url: 'https://github.com/nlabrazi/argandici/commit/commit123',
            author: { login: 'nlabrazi' },
            commit: {
              message: "Feature in staging\n\nExtended notes",
              author: { name: 'Nicolas Labrazi', date: Time.zone.parse('2026-05-07T09:00:00Z') },
              committer: { date: Time.zone.parse('2026-05-07T09:01:00Z') }
            }
          }
        ]
      }
    end

    it 'compares explicit base and head branches' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'feature/test')
        .and_return(comparison_payload)

      result = service.compare_branches('main', 'feature/test')

      expect(result).to eq({
        base_branch: 'main',
        head_branch: 'feature/test',
        ahead_by: 2,
        behind_by: 1,
        status: 'diverged',
        total_commits: 3,
        html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
        permalink_url: 'https://github.com/nlabrazi/argandici/compare/nlabrazi:abc...nlabrazi:def',
        commits: [
          {
            sha: 'commit123',
            message: 'Feature in staging',
            author_name: 'Nicolas Labrazi',
            author_login: 'nlabrazi',
            authored_at: Time.zone.parse('2026-05-07T09:00:00Z'),
            committed_at: Time.zone.parse('2026-05-07T09:01:00Z'),
            html_url: 'https://github.com/nlabrazi/argandici/commit/commit123'
          }
        ]
      })
    end

    it 'defaults to effective_production_branch and staging_branch' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return(comparison_payload)

      result = service.compare_branches

      expect(result[:base_branch]).to eq('main')
      expect(result[:head_branch]).to eq('staging')
      expect(result[:ahead_by]).to eq(2)
      expect(result[:behind_by]).to eq(1)
    end

    it 'returns nil when staging branch is blank and no head branch is given' do
      project.staging_branch = nil

      expect(service.compare_branches).to be_nil
    end

    it 'returns nil when project has no repository URL' do
      project.repo_url = nil

      expect(service.compare_branches).to be_nil
    end

    it 'returns nil and logs when GitHub comparison fails' do
      allow(client).to receive(:compare).and_raise(Octokit::NotFound)

      expect(service.compare_branches('main', 'staging')).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/GitHub branch comparison \(main\.\.\.staging\) failed/)
    end

    it 'treats staging as synced when base HEAD merged staging (merge_base in base_commit parents)' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return({
          ahead_by: 0,
          behind_by: 30,
          status: 'behind',
          total_commits: 0,
          html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          permalink_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          merge_base_commit: { sha: 'staging123' },
          base_commit: {
            sha: 'merge123',
            parents: [ { sha: 'prevmaster' }, { sha: 'staging123' } ]
          },
          commits: []
        })

      result = service.compare_branches('main', 'staging')

      expect(result[:ahead_by]).to eq(0)
      expect(result[:behind_by]).to eq(0)
      expect(result[:status]).to eq('identical')
    end

    it 'treats staging as ahead when staging has unmerged commits and base HEAD is the previous merge' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return({
          ahead_by: 2,
          behind_by: 30,
          status: 'diverged',
          total_commits: 2,
          html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          permalink_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          merge_base_commit: { sha: 'staging_prev' },
          base_commit: {
            sha: 'merge123',
            parents: [ { sha: 'prevmaster' }, { sha: 'staging_prev' } ]
          },
          commits: []
        })

      result = service.compare_branches('main', 'staging')

      expect(result[:ahead_by]).to eq(2)
      expect(result[:behind_by]).to eq(0)
      expect(result[:status]).to eq('ahead')
    end

    it 'treats staging as synced when git trees are identical and ahead_by is zero' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return({
          ahead_by: 0,
          behind_by: 15,
          status: 'behind',
          total_commits: 0,
          html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          permalink_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          merge_base_commit: {
            sha: 'mb123',
            commit: { tree: { sha: 'identical_tree_sha' } }
          },
          base_commit: {
            sha: 'squash123',
            commit: { tree: { sha: 'identical_tree_sha' } },
            parents: [ { sha: 'prevmaster' } ]
          },
          commits: []
        })

      result = service.compare_branches('main', 'staging')

      expect(result[:ahead_by]).to eq(0)
      expect(result[:behind_by]).to eq(0)
      expect(result[:status]).to eq('identical')
    end

    it 'counts only new commits added to base branch after the merge of staging' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return({
          ahead_by: 0,
          behind_by: 32,
          status: 'behind',
          total_commits: 0,
          html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          permalink_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          merge_base_commit: { sha: 'staging123' },
          base_commit: {
            sha: 'hotfix2',
            parents: [ { sha: 'hotfix1' } ]
          },
          commits: []
        })

      allow(client).to receive(:commits)
        .with('nlabrazi/argandici', sha: 'main', per_page: 30)
        .and_return([
          { sha: 'hotfix2', parents: [ { sha: 'hotfix1' } ] },
          { sha: 'hotfix1', parents: [ { sha: 'merge123' } ] },
          { sha: 'merge123', parents: [ { sha: 'prevmaster' }, { sha: 'staging123' } ] }
        ])

      result = service.compare_branches('main', 'staging')

      expect(result[:ahead_by]).to eq(0)
      expect(result[:behind_by]).to eq(2)
      expect(result[:status]).to eq('behind')
    end

    it 'falls back to raw behind_by when commit history traversal fails' do
      allow(client).to receive(:compare)
        .with('nlabrazi/argandici', 'main', 'staging')
        .and_return({
          ahead_by: 0,
          behind_by: 7,
          status: 'behind',
          total_commits: 0,
          html_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          permalink_url: 'https://github.com/nlabrazi/argandici/compare/main...staging',
          merge_base_commit: { sha: 'staging123' },
          base_commit: {
            sha: 'hotfix1',
            parents: [ { sha: 'other' } ]
          },
          commits: []
        })

      allow(client).to receive(:commits)
        .with('nlabrazi/argandici', sha: 'main', per_page: 30)
        .and_raise(Octokit::Error)

      result = service.compare_branches('main', 'staging')

      expect(result[:behind_by]).to eq(7)
    end
  end
end
