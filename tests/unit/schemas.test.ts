import { describe, expect, it } from 'vitest'
import {
  buildGithubCompareDeployUrl,
  buildGithubCompareStagingUrl,
  computeStagingSyncStatus,
  extractGithubRepo,
  isSafeVpsPath,
  isValidHttpUrl,
  normalizeGithubRepoUrl,
  projectUpdateSchema,
  sentinelManifestSchema,
} from '#shared/schemas/project'

describe('project validation schemas & helpers', () => {
  it('enforces strict vps_path containment under /srv/apps', () => {
    expect(isSafeVpsPath('/srv/apps/sentinel')).toBe(true)
    expect(isSafeVpsPath('/srv/apps/my-app_v2.1')).toBe(true)
    expect(isSafeVpsPath('/srv/apps/group/app')).toBe(true)

    expect(isSafeVpsPath('/srv/apps')).toBe(false)
    expect(isSafeVpsPath('/srv/apps/')).toBe(false)
    expect(isSafeVpsPath('/srv/apps/../etc/passwd')).toBe(false)
    expect(isSafeVpsPath('/etc/passwd')).toBe(false)
    expect(isSafeVpsPath('/srv/apps/foo;rm -rf /')).toBe(false)
    expect(isSafeVpsPath('/srv/apps/foo bar')).toBe(false)
  })

  it('normalizes GitHub HTTPS and SSH remote URLs and extracts owner/repo', () => {
    expect(normalizeGithubRepoUrl('git@github.com:nlabrazi/sentinel.git')).toBe(
      'https://github.com/nlabrazi/sentinel.git',
    )
    expect(normalizeGithubRepoUrl('https://github.com/nlabrazi/sentinel')).toBe(
      'https://github.com/nlabrazi/sentinel',
    )
    expect(normalizeGithubRepoUrl('https://gitlab.com/nlabrazi/sentinel.git')).toBeNull()
    expect(normalizeGithubRepoUrl('https://user:pass@github.com/nlabrazi/sentinel.git')).toBeNull()

    expect(extractGithubRepo('git@github.com:nlabrazi/sentinel.git')).toBe('nlabrazi/sentinel')
    expect(extractGithubRepo('https://github.com/nlabrazi/dev-platform.git')).toBe(
      'nlabrazi/dev-platform',
    )
  })

  it('validates HTTP/HTTPS URLs without embedded credentials', () => {
    expect(isValidHttpUrl('https://sentinel.nabster.dev')).toBe(true)
    expect(isValidHttpUrl('http://localhost:3000')).toBe(true)
    expect(isValidHttpUrl('ftp://sentinel.nabster.dev')).toBe(false)
    expect(isValidHttpUrl('https://user:pass@sentinel.nabster.dev')).toBe(false)
    expect(isValidHttpUrl('javascript:alert(1)')).toBe(false)
  })

  it('computes staging sync status and GitHub compare URLs', () => {
    expect(computeStagingSyncStatus(null, 0, 0)).toBe('not_configured')
    expect(computeStagingSyncStatus('staging', 0, 0)).toBe('synced')
    expect(computeStagingSyncStatus('staging', 3, 0)).toBe('ahead')
    expect(computeStagingSyncStatus('staging', 0, 2)).toBe('behind')
    expect(computeStagingSyncStatus('staging', 2, 1)).toBe('diverged')

    expect(
      buildGithubCompareStagingUrl('https://github.com/nlabrazi/sentinel.git', 'master', 'staging'),
    ).toBe('https://github.com/nlabrazi/sentinel/compare/master...staging')

    expect(
      buildGithubCompareDeployUrl('https://github.com/nlabrazi/sentinel.git', 'abc1234', 'master'),
    ).toBe('https://github.com/nlabrazi/sentinel/compare/abc1234...master')
  })

  it('validates optional sentinel.json manifest and project update payloads', () => {
    const manifest = sentinelManifestSchema.parse({
      name: 'Sentinel',
      kind: 'app',
      production_url: 'https://sentinel.nabster.dev',
      cron_monitoring: true,
    })
    expect(manifest.kind).toBe('app')

    const update = projectUpdateSchema.parse({
      name: 'My App',
      productionUrl: '',
      repoUrl: 'https://github.com/nlabrazi/sentinel.git',
      cronMonitoringEnabled: true,
    })
    expect(update.productionUrl).toBeNull()
    expect(update.cronMonitoringEnabled).toBe(true)

    expect(() =>
      projectUpdateSchema.parse({
        productionUrl: 'ftp://invalid.example.com',
      }),
    ).toThrow()
  })
})
