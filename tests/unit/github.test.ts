import { describe, expect, it, vi } from 'vitest'
import {
  compareGithubRefs,
  computeEffectiveBehindBy,
  fetchLatestBranchCommit,
  fetchRecentPullRequests,
  fetchRepoMetadata,
  isRenovatePullRequest,
  normalizeHomepageUrl,
} from '#server/services/github'

describe('github service', () => {
  it('accurately detects Renovate PRs by bot author or branch prefix', () => {
    expect(isRenovatePullRequest('renovate[bot]', 'renovate/all-minor-patch')).toBe(true)
    expect(isRenovatePullRequest('nlabrazi', 'renovate/dev-platform')).toBe(true)
    expect(isRenovatePullRequest('nlabrazi', 'feat/add-dashboard')).toBe(false)
    expect(isRenovatePullRequest(null, null)).toBe(false)
  })

  it('ignores spurious behind_by count when trees match or base parent is merge_base', () => {
    expect(
      computeEffectiveBehindBy({
        ahead_by: 0,
        behind_by: 2,
        base_commit: { sha: 'aaa', commit: { tree: { sha: 'tree-1' } } },
        merge_base_commit: { sha: 'bbb', commit: { tree: { sha: 'tree-1' } } },
      }),
    ).toBe(0)

    expect(
      computeEffectiveBehindBy({
        ahead_by: 1,
        behind_by: 1,
        base_commit: { sha: 'aaa', parents: [{ sha: 'bbb' }] },
        merge_base_commit: { sha: 'bbb' },
      }),
    ).toBe(0)

    expect(
      computeEffectiveBehindBy({
        ahead_by: 3,
        behind_by: 2,
        base_commit: { sha: 'aaa', parents: [{ sha: 'ccc' }] },
        merge_base_commit: { sha: 'bbb' },
      }),
    ).toBe(2)
  })

  it('fetches latest branch commit, compares branches, and normalizes PRs', async () => {
    const mockFetch = vi.fn<typeof fetch>()
    mockFetch
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            sha: 'deadbeef1234',
            html_url: 'https://github.com/nlabrazi/sentinel/commit/deadbeef1234',
            commit: {
              message: 'feat: add cockpit\n\nLonger body',
              committer: { date: '2026-11-21T10:00:00Z' },
            },
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            ahead_by: 4,
            behind_by: 0,
            html_url: 'https://github.com/nlabrazi/sentinel/compare/master...staging',
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify([
            {
              number: 12,
              title: 'chore(deps): update dev-platform packages',
              state: 'open',
              draft: false,
              user: { login: 'renovate[bot]' },
              head: { ref: 'renovate/dev-platform' },
              base: { ref: 'staging' },
              html_url: 'https://github.com/nlabrazi/sentinel/pull/12',
              created_at: '2026-11-21T08:00:00Z',
              updated_at: '2026-11-21T09:00:00Z',
            },
            {
              number: 11,
              title: 'feat: initial cockpit',
              state: 'closed',
              draft: false,
              user: { login: 'nlabrazi' },
              head: { ref: 'feat/cockpit' },
              base: { ref: 'staging' },
              merged_at: '2026-11-20T18:00:00Z',
              updated_at: '2026-11-20T18:00:00Z',
            },
          ]),
          { status: 200 },
        ),
      )

    const commit = await fetchLatestBranchCommit('nlabrazi/sentinel', 'master', {
      token: 'ghp_test',
      fetchImpl: mockFetch,
    })
    expect(commit?.sha).toBe('deadbeef1234')
    expect(commit?.message).toBe('feat: add cockpit')

    const comparison = await compareGithubRefs('nlabrazi/sentinel', 'master', 'staging', {
      token: 'ghp_test',
      fetchImpl: mockFetch,
    })
    expect(comparison).toMatchObject({ aheadBy: 4, behindBy: 0, status: 'ahead' })

    const prs = await fetchRecentPullRequests('nlabrazi/sentinel', 10, {
      token: 'ghp_test',
      fetchImpl: mockFetch,
    })
    expect(prs).toHaveLength(2)
    expect(prs[0]).toMatchObject({ number: 12, state: 'open', isRenovate: true })
    expect(prs[1]).toMatchObject({ number: 11, state: 'merged', isRenovate: false })
  })

  it('normalizes GitHub homepage URLs and fetches repo metadata', async () => {
    expect(normalizeHomepageUrl('https://nabster.dev/')).toBe('https://nabster.dev')
    expect(normalizeHomepageUrl('argandici.com')).toBe('https://argandici.com')
    expect(normalizeHomepageUrl('')).toBeNull()
    expect(normalizeHomepageUrl('ftp://invalid.example')).toBeNull()

    const mockFetch = vi.fn<typeof fetch>().mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          homepage: 'https://riftvision.nabster.dev/',
          default_branch: 'master',
        }),
        { status: 200 },
      ),
    )

    const meta = await fetchRepoMetadata('nlabrazi/riftvision', {
      token: 'ghp_test',
      fetchImpl: mockFetch,
    })
    expect(meta).toEqual({
      homepage: 'https://riftvision.nabster.dev',
      defaultBranch: 'master',
    })
  })
})
