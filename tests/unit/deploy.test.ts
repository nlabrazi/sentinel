import { describe, expect, it, vi } from 'vitest'
import type { SentinelDb } from '#server/db'
import type { DeploymentRow, ProjectRow } from '#server/db/schema'
import {
  buildDeployCommand,
  buildSelfDeployCommand,
  DeployLogBus,
  type DeployStreamEvent,
  executeDeploymentRun,
  isSelfDeployProject,
  parseSelfDeployLog,
  reconcileInterruptedDeployments,
  SELF_DEPLOY_EXIT_MARKER,
  SELF_DEPLOY_MISSING_MARKER,
  selfDeployLogPath,
  truncateLog,
} from '#server/services/deploy'
import type { SshExecutor } from '#server/services/ssh'
import { getEnv } from '#server/utils/env'

function makeFakeProject(overrides: Partial<ProjectRow> = {}): ProjectRow {
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
    screenshotUpdatedAt: null,
    vpsSyncedAt: now,
    githubSyncedAt: now,
    cronSyncedAt: null,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  }
}

function makeFakeDeployment(overrides: Partial<DeploymentRow> = {}): DeploymentRow {
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
    ...overrides,
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

  it('builds safe deploy.sh command, supports SSH_DEPLOY_AS_USER and rejects unsafe inputs', () => {
    const direct = buildDeployCommand('/srv/apps/sentinel', '/srv/apps', '')
    expect(direct).toContain('./deploy.sh')
    expect(direct).toContain('GIT_CONFIG_COUNT=1')

    const delegated = buildDeployCommand('/srv/apps/sentinel', '/srv/apps', 'zref')
    expect(delegated).toContain('sudo -n -H -u')
    expect(delegated).toContain('zref')
    expect(delegated).toContain('/srv/apps/sentinel/deploy.sh')

    expect(() => buildDeployCommand('/etc/passwd', '/srv/apps', '')).toThrow(/Unsafe VPS path/)
    expect(() => buildDeployCommand('/srv/apps/sentinel', '/srv/apps', 'zref; id')).toThrow(
      /Invalid SSH_DEPLOY_AS_USER/,
    )
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
      project: makeFakeProject({ slug: 'games-lab', vpsPath: '/srv/apps/games-lab' }),
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

  it('detects self-deploy project, builds detached setsid command, and parses self-deploy markers', () => {
    expect(isSelfDeployProject({ slug: 'sentinel' })).toBe(true)
    expect(isSelfDeployProject({ slug: 'Sentinel' })).toBe(true)
    expect(isSelfDeployProject({ slug: 'games-lab' })).toBe(false)

    expect(selfDeployLogPath(42)).toBe('/tmp/sentinel-self-deploy-42.log')
    expect(() => selfDeployLogPath(0)).toThrow(/Invalid deployment id/)
    expect(() => selfDeployLogPath(-5)).toThrow(/Invalid deployment id/)

    const cmd = buildSelfDeployCommand('/srv/apps/sentinel', 42, '/srv/apps', 'zref')
    expect(cmd).toContain('setsid')
    expect(cmd).toContain('/tmp/sentinel-self-deploy-42.log')
    expect(cmd).toContain('sudo -n -H -u')
    expect(cmd).toContain('/srv/apps/sentinel/deploy.sh')
    expect(cmd).toContain(SELF_DEPLOY_EXIT_MARKER)

    const parsedOk = parseSelfDeployLog(
      `🚀 Starting Sentinel deploy...\n✅ Sentinel deploy done!\n${SELF_DEPLOY_EXIT_MARKER}0\n`,
    )
    expect(parsedOk.exitCode).toBe(0)
    expect(parsedOk.log).toBe('🚀 Starting Sentinel deploy...\n✅ Sentinel deploy done!')

    const parsedRunning = parseSelfDeployLog('🚀 Starting Sentinel deploy...\n📦 Pulling...\n')
    expect(parsedRunning.exitCode).toBeNull()
    expect(parsedRunning.log).toContain('Pulling...')
  })

  it('reconciles orphaned deploys on startup: fails other projects and recovers detached sentinel self-deploy', async () => {
    const updates: Array<Record<string, unknown>> = []
    const runningRows = [
      {
        deployment: makeFakeDeployment({ id: 10, projectId: 2, commitSha: 'aaaaaaa' }),
        project: makeFakeProject({
          id: 2,
          slug: 'games-lab',
          name: 'Games-Lab',
          vpsPath: '/srv/apps/games-lab',
        }),
      },
      {
        deployment: makeFakeDeployment({ id: 11, projectId: 1, commitSha: 'bbbbbbb' }),
        project: makeFakeProject({ id: 1, slug: 'sentinel', name: 'Sentinel' }),
      },
    ]

    const fakeDb = {
      select: vi.fn(() => ({
        from: vi.fn(() => ({
          innerJoin: vi.fn(() => ({
            where: vi.fn(async () => runningRows),
          })),
        })),
      })),
      update: vi.fn(() => ({
        set: vi.fn((values: Record<string, unknown>) => {
          updates.push(values)
          return {
            where: vi.fn(async () => []),
          }
        }),
      })),
    } as unknown as SentinelDb

    const sshCalls: string[] = []
    const fakeSsh: SshExecutor = {
      execute: vi.fn(async (cmd) => {
        sshCalls.push(cmd)
        if (sshCalls.length === 1) {
          return { exitCode: 0, stdout: '🚀 Pulling...\n', stderr: '' }
        }
        if (sshCalls.length === 2) {
          return {
            exitCode: 0,
            stdout: `🚀 Pulling...\n✅ Sentinel deploy done!\n${SELF_DEPLOY_EXIT_MARKER}0\n`,
            stderr: '',
          }
        }
        return { exitCode: 0, stdout: '', stderr: '' }
      }),
    }

    const bus = new DeployLogBus()
    const env = getEnv({ VPS_HOST: 'vps.example.com' })
    const summary = await reconcileInterruptedDeployments(fakeDb, {
      ssh: fakeSsh,
      bus,
      env,
      maxPollAttempts: 3,
      pollIntervalMs: 0,
      syncVpsOnSuccess: false,
    })

    expect(summary).toEqual({ reconciled: 2, selfSucceeded: 1, failed: 1 })
    // First update: games-lab marked failed
    expect(updates[0]).toMatchObject({ status: 'failed' })
    expect(String(updates[0]?.log)).toContain('interrompu par un redémarrage')
    // Second & third updates: sentinel marked success with full log + project commit updated
    expect(updates[1]).toMatchObject({
      status: 'success',
      log: '🚀 Pulling...\n✅ Sentinel deploy done!',
    })
    expect(updates[2]).toMatchObject({
      lastCommitDeployed: 'bbbbbbb',
      latestCommitAvailable: 'bbbbbbb',
      commitsBehind: 0,
    })
    // Third SSH call cleaned up the temp log file
    expect(sshCalls[2]).toContain('rm -f')
    expect(sshCalls[2]).toContain('/tmp/sentinel-self-deploy-11.log')
  })

  it('reconciles legacy sentinel self-deploy immediately when no detached log file exists', async () => {
    const updates: Array<Record<string, unknown>> = []
    const runningRows = [
      {
        deployment: makeFakeDeployment({ id: 99, projectId: 1, commitSha: 'ccccccc' }),
        project: makeFakeProject({ id: 1, slug: 'sentinel', name: 'Sentinel' }),
      },
    ]

    const fakeDb = {
      select: vi.fn(() => ({
        from: vi.fn(() => ({
          innerJoin: vi.fn(() => ({
            where: vi.fn(async () => runningRows),
          })),
        })),
      })),
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
      execute: vi.fn(async () => ({
        exitCode: 0,
        stdout: `${SELF_DEPLOY_MISSING_MARKER}\n`,
        stderr: '',
      })),
    }

    const summary = await reconcileInterruptedDeployments(fakeDb, {
      ssh: fakeSsh,
      env: getEnv({ VPS_HOST: 'vps.example.com' }),
      maxPollAttempts: 3,
      pollIntervalMs: 0,
      syncVpsOnSuccess: false,
    })

    expect(summary).toEqual({ reconciled: 1, selfSucceeded: 1, failed: 0 })
    expect(fakeSsh.execute).toHaveBeenCalledTimes(1)
    expect(updates[0]).toMatchObject({ status: 'success' })
    expect(String(updates[0]?.log)).toContain('auto-déploiement')
  })
})
