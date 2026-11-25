import { describe, expect, it } from 'vitest'
import type { ProjectRow } from '#server/db/schema'
import { serializeProjectSummary } from '#server/utils/project-serializer'

function makeProjectRow(overrides: Partial<ProjectRow> = {}): ProjectRow {
  const now = new Date('2026-11-21T12:00:00Z')
  return {
    id: 1,
    slug: 'sentinel',
    name: 'Sentinel',
    kind: 'app',
    vpsPath: '/srv/apps/sentinel',
    repoUrl: 'https://github.com/nlabrazi/sentinel.git',
    productionBranch: 'master',
    stagingBranch: 'staging',
    productionUrl: 'https://sentinel.nabster.dev',
    grafanaAppValue: 'https://sentinel.nabster.dev',
    umamiWebsiteId: null,
    hasDeployScript: true,
    hasStatusScript: true,
    cronMonitoringEnabled: true,
    maintenanceMode: false,
    lastCommitDeployed: 'abc1234',
    latestCommitAvailable: 'def5678',
    commitsBehind: 2,
    productionCiStatus: 'failed',
    productionCiUrl: 'https://jenkins.nabster.dev/job/sentinel/job/master/14/display/redirect',
    stagingCommitsAhead: 3,
    stagingCommitsBehind: 0,
    umamiVisitors24h: 0,
    umamiPageviews24h: 0,
    umamiBounceRate: 0,
    umamiSyncError: null,
    umamiSyncedAt: null,
    screenshotUpdatedAt: now,
    vpsSyncedAt: now,
    githubSyncedAt: now,
    cronSyncedAt: null,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  }
}

describe('project serializer', () => {
  it('computes github links, staging status, and aggregates PR / deploy flags', () => {
    const dto = serializeProjectSummary(makeProjectRow(), {
      openPrsCount: 4,
      openRenovatePrsCount: 2,
      hasRunningDeployment: true,
      cronSummaryStatus: 'ok',
    })

    expect(dto.githubRepo).toBe('nlabrazi/sentinel')
    expect(dto.stagingSyncStatus).toBe('ahead')
    expect(dto.githubCompareStagingUrl).toBe(
      'https://github.com/nlabrazi/sentinel/compare/master...staging',
    )
    expect(dto.githubCompareDeployUrl).toBe(
      'https://github.com/nlabrazi/sentinel/compare/abc1234...master',
    )
    expect(dto.openPrsCount).toBe(4)
    expect(dto.openRenovatePrsCount).toBe(2)
    expect(dto.hasRunningDeployment).toBe(true)
    expect(dto.cronSummaryStatus).toBe('ok')
    expect(dto.productionCiStatus).toBe('failed')
    expect(dto.productionCiUrl).toBe(
      'https://jenkins.nabster.dev/job/sentinel/job/master/14/display/redirect',
    )
    expect(dto.screenshotUrl).toMatch(/^\/api\/projects\/sentinel\/screenshot\?v=\d+$/)
  })

  it('handles projects without repository or staging branch cleanly', () => {
    const dto = serializeProjectSummary(
      makeProjectRow({
        repoUrl: null,
        stagingBranch: null,
        cronMonitoringEnabled: false,
      }),
    )

    expect(dto.githubRepo).toBeNull()
    expect(dto.stagingSyncStatus).toBe('not_configured')
    expect(dto.githubCompareStagingUrl).toBeNull()
    expect(dto.githubCompareDeployUrl).toBeNull()
    expect(dto.cronSummaryStatus).toBe('disabled')
  })
})
