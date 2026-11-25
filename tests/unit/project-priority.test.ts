import { describe, expect, it } from 'vitest'
import {
  getProjectAttentionState,
  hasCronAlert,
  isDeployReady,
  sortProjectsByPriority,
} from '../../app/utils/project-priority'
import type { ProjectSummaryDto } from '../../shared/types/api'

function makeSummary(overrides: Partial<ProjectSummaryDto> = {}): ProjectSummaryDto {
  return {
    id: 1,
    slug: 'demo',
    name: 'Demo',
    kind: 'app',
    vpsPath: '/srv/apps/demo',
    repoUrl: 'https://github.com/nlabrazi/demo',
    githubRepo: 'nlabrazi/demo',
    productionBranch: 'master',
    stagingBranch: 'staging',
    productionUrl: 'https://demo.nabster.dev',
    grafanaAppValue: 'demo',
    umamiWebsiteId: null,
    hasDeployScript: true,
    hasStatusScript: false,
    cronMonitoringEnabled: false,
    maintenanceMode: false,
    lastCommitDeployed: '1111111',
    latestCommitAvailable: '1111111',
    commitsBehind: 0,
    productionCiStatus: 'unknown',
    productionCiUrl: null,
    stagingCommitsAhead: 0,
    stagingCommitsBehind: 0,
    stagingSyncStatus: 'synced',
    githubCompareStagingUrl: null,
    githubCompareDeployUrl: null,
    umamiVisitors24h: 0,
    umamiPageviews24h: 0,
    umamiBounceRate: 0,
    umamiSyncError: null,
    umamiSyncedAt: null,
    screenshotUrl: null,
    screenshotUpdatedAt: null,
    vpsSyncedAt: null,
    githubSyncedAt: null,
    cronSyncedAt: null,
    cronSummaryStatus: 'disabled',
    openPrsCount: 0,
    openRenovatePrsCount: 0,
    hasRunningDeployment: false,
    ...overrides,
  }
}

describe('project priority & attention helpers', () => {
  it('classifies cron failures, running deploys, pending commits, maintenance and healthy projects', () => {
    expect(
      getProjectAttentionState(
        makeSummary({ cronMonitoringEnabled: true, cronSummaryStatus: 'failed' }),
      ),
    ).toMatchObject({ severity: 'critical', needsAttention: true })

    expect(getProjectAttentionState(makeSummary({ hasRunningDeployment: true }))).toMatchObject({
      severity: 'running',
      needsAttention: true,
    })

    expect(getProjectAttentionState(makeSummary({ commitsBehind: 2 }))).toMatchObject({
      severity: 'warning',
      needsAttention: true,
      label: '2 commit(s) à déployer',
    })
    expect(isDeployReady(makeSummary({ commitsBehind: 2, productionCiStatus: 'success' }))).toBe(
      true,
    )
    expect(isDeployReady(makeSummary({ commitsBehind: 2, productionCiStatus: 'unknown' }))).toBe(
      true,
    )

    expect(
      getProjectAttentionState(makeSummary({ commitsBehind: 4, productionCiStatus: 'failed' })),
    ).toMatchObject({
      severity: 'critical',
      needsAttention: true,
      color: 'error',
      label: 'CI en échec (4 commit(s))',
    })
    expect(isDeployReady(makeSummary({ commitsBehind: 4, productionCiStatus: 'failed' }))).toBe(
      false,
    )

    expect(
      getProjectAttentionState(makeSummary({ commitsBehind: 1, productionCiStatus: 'pending' })),
    ).toMatchObject({
      severity: 'running',
      needsAttention: false,
      color: 'info',
      label: 'CI en cours (1 commit(s))',
    })
    expect(isDeployReady(makeSummary({ commitsBehind: 1, productionCiStatus: 'pending' }))).toBe(
      false,
    )

    expect(getProjectAttentionState(makeSummary({ maintenanceMode: true }))).toMatchObject({
      severity: 'warning',
      needsAttention: true,
      label: 'Maintenance',
    })

    expect(
      getProjectAttentionState(makeSummary({ stagingSyncStatus: 'ahead', stagingCommitsAhead: 3 })),
    ).toMatchObject({ severity: 'info', needsAttention: false, label: 'Staging +3' })

    expect(getProjectAttentionState(makeSummary())).toMatchObject({
      severity: 'ok',
      needsAttention: false,
      label: 'À jour',
    })

    expect(
      hasCronAlert(makeSummary({ cronMonitoringEnabled: false, cronSummaryStatus: 'failed' })),
    ).toBe(false)
    expect(
      hasCronAlert(makeSummary({ cronMonitoringEnabled: true, cronSummaryStatus: 'overdue' })),
    ).toBe(true)
  })

  it('sorts projects with alerts and pending deployments above healthy ones', () => {
    const healthyA = makeSummary({ slug: 'alpha', name: 'Alpha' })
    const behind = makeSummary({ slug: 'zeta', name: 'Zeta', commitsBehind: 1 })
    const cronFailed = makeSummary({
      slug: 'rift',
      name: 'Rift',
      cronMonitoringEnabled: true,
      cronSummaryStatus: 'failed',
    })
    const running = makeSummary({ slug: 'beta', name: 'Beta', hasRunningDeployment: true })
    const healthyB = makeSummary({ slug: 'gamma', name: 'Gamma' })

    const sorted = sortProjectsByPriority([healthyB, behind, healthyA, cronFailed, running])
    expect(sorted.map((p) => p.slug)).toEqual(['rift', 'beta', 'zeta', 'alpha', 'gamma'])
  })
})
