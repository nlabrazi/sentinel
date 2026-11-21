import { describe, expect, it, vi } from 'vitest'
import type { SentinelDb } from '#server/db'
import type { DeploymentRow, ProjectRow } from '#server/db/schema'
import {
  buildDeployCommand,
  DeployLogBus,
  type DeployStreamEvent,
  executeDeploymentRun,
  truncateLog,
} from '#server/services/deploy'
import type { SshExecutor } from '#server/services/ssh'

function makeFakeProject(): ProjectRow {
  const now = new Date()
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
    grafanaAppValue: null,
    umamiWebsiteId: null,
    hasDeployScript: true,
    hasStatusScript: false,
    cronMonitoringEnabled: false,
    maintenanceMode: false,
    lastCommitDeployed: '1111111',
    latestCommitAvailable: '2222222',
    commitsBehind: 1,
    stagingCommitsAhead: 0,
    stagingCommitsBehind: 0,
    umamiVisitors24h: 0,
    umamiPageviews24h: 0,
    umamiBounceRate: 0,
    umamiSyncError: null,
    umamiSyncedAt: null,
    vpsSyncedAt: now,
    githubSyncedAt: now,
    cronSyncedAt: null,
    createdAt: now,
    updatedAt: now,
  }
}

function makeFakeDeployment(): DeploymentRow {
  const now = new Date()
  return {
    id: 42,
    projectId: 1,
    commitSha: '2222222',
    status: 'running',
    triggeredBy: 'admin',
    durationSeconds: null,
    log: '',
    createdAt: now,
    updatedAt: now,
  }
}

describe('deploy service', () => {
  it('truncates logs exceeding byte limits and appends truncation notice', () => {
    const short = 'hello world'
    expect(truncateLog(short, 100)).toBe(short)

    const long = 'a'.repeat(500)
    const truncated = truncateLog(long, 128)
    expect(Buffer.byteLength(truncated, 'utf8')).toBeLessThanOrEqual(128)
    expect(truncated).toContain('[Log truncated]')
  })

  it('builds safe deploy.sh command and rejects unsafe paths', () => {
    expect(buildDeployCommand('/srv/apps/sentinel', '/srv/apps')).toContain('./deploy.sh')
    expect(() => buildDeployCommand('/etc/passwd', '/srv/apps')).toThrow(/Unsafe VPS path/)
  })

  it('streams chunks live through DeployLogBus and clears active buffer on finish', () => {
    const bus = new DeployLogBus()
    const received: DeployStreamEvent[] = []
    bus.start(7)
    const unsub = bus.subscribe(7, (ev) => received.push(ev))

    bus.append(7, 'step 1\n')
    bus.append(7, 'step 2\n')
    expect(bus.getActiveBuffer(7)).toBe('step 1\nstep 2\n')
    expect(bus.isActive(7)).toBe(true)

    bus.finish(7, 'success', 12)
    unsub()

    expect(bus.isActive(7)).toBe(false)
    expect(received).toEqual([
      { type: 'chunk', data: 'step 1\n' },
      { type: 'chunk', data: 'step 2\n' },
      { type: 'done', status: 'success', durationSeconds: 12 },
    ])
  })

  it('executes deployment via SSH, streams logs and updates project on success', async () => {
    const updates: Array<Record<string, unknown>> = []
    const fakeDb = {
      update: vi.fn(() => ({
        set: vi.fn((values: Record<string, unknown>) => {
          updates.push(values)
          return {
            where: vi.fn(async () => []),
          }
        }),
      })),
    } as unknown as SentinelDb

    const fakeSsh: SshExecutor = {
      execute: vi.fn(async (_cmd, opts) => {
        opts?.onStdout?.('==> pulling\n')
        opts?.onStdout?.('==> deployed\n')
        return { exitCode: 0, stdout: '==> pulling\n==> deployed\n', stderr: '' }
      }),
    }

    const bus = new DeployLogBus()
    const result = await executeDeploymentRun({
      db: fakeDb,
      project: makeFakeProject(),
      deployment: makeFakeDeployment(),
      ssh: fakeSsh,
      bus,
      appsRoot: '/srv/apps',
    })

    expect(result.status).toBe('success')
    expect(result.log).toContain('==> deployed')
    expect(updates).toHaveLength(2)
    expect(updates[0]).toMatchObject({ status: 'success' })
    expect(updates[1]).toMatchObject({ lastCommitDeployed: '2222222', commitsBehind: 0 })
  })
})
