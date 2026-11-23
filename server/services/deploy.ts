import { EventEmitter } from 'node:events'
import { and, eq, sql } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { type DeploymentRow, deployments, type ProjectRow, projects } from '#server/db/schema'
import { fetchLatestBranchCommit } from '#server/services/github'
import { captureProjectScreenshot } from '#server/services/screenshot'
import {
  defaultSshExecutor,
  type SshExecutor,
  shellEscape,
  wrapBashCommand,
} from '#server/services/ssh'
import { discoverVpsProjects } from '#server/services/vps-discovery'
import { getEnv, type SentinelEnv } from '#server/utils/env'
import { extractGithubRepo, isSafeVpsPath } from '#shared/schemas/project'
import type { DeploymentStatus } from '#shared/types/sentinel'

export const MAX_DEPLOY_LOG_BYTES = 64 * 1024
const TRUNCATED_NOTICE = '\n\n[Log truncated]\n'
export const SELF_DEPLOY_EXIT_MARKER = '__SENTINEL_SELF_DEPLOY_EXIT__='
export const SELF_DEPLOY_MISSING_MARKER = '__SENTINEL_SELF_DEPLOY_MISSING__'

export class DeploymentAlreadyRunningError extends Error {
  constructor(slug: string) {
    super(`Un déploiement est déjà en cours pour ${slug}.`)
    this.name = 'DeploymentAlreadyRunningError'
  }
}

export interface DeployStreamEvent {
  type: 'chunk' | 'done'
  data?: string
  status?: DeploymentStatus
  durationSeconds?: number
}

export class DeployLogBus {
  private readonly emitter = new EventEmitter()
  private readonly activeBuffers = new Map<number, string>()

  constructor() {
    this.emitter.setMaxListeners(100)
  }

  start(deploymentId: number): void {
    this.activeBuffers.set(deploymentId, '')
  }

  append(deploymentId: number, chunk: string): void {
    const current = this.activeBuffers.get(deploymentId) ?? ''
    this.activeBuffers.set(deploymentId, truncateLog(current + chunk, MAX_DEPLOY_LOG_BYTES))
    this.emitter.emit(this.channel(deploymentId), {
      type: 'chunk',
      data: chunk,
    } satisfies DeployStreamEvent)
  }

  finish(deploymentId: number, status: DeploymentStatus, durationSeconds: number): void {
    this.emitter.emit(this.channel(deploymentId), {
      type: 'done',
      status,
      durationSeconds,
    } satisfies DeployStreamEvent)
    this.activeBuffers.delete(deploymentId)
  }

  getActiveBuffer(deploymentId: number): string | undefined {
    return this.activeBuffers.get(deploymentId)
  }

  isActive(deploymentId: number): boolean {
    return this.activeBuffers.has(deploymentId)
  }

  subscribe(deploymentId: number, listener: (event: DeployStreamEvent) => void): () => void {
    const ch = this.channel(deploymentId)
    this.emitter.on(ch, listener)
    return () => {
      this.emitter.off(ch, listener)
    }
  }

  private channel(deploymentId: number): string {
    return `deploy:${deploymentId}`
  }
}

export const deployLogBus = new DeployLogBus()

export function truncateLog(log: string, maxBytes = MAX_DEPLOY_LOG_BYTES): string {
  const buf = Buffer.from(log, 'utf8')
  if (buf.byteLength <= maxBytes) {
    return log
  }
  const noticeBytes = Buffer.byteLength(TRUNCATED_NOTICE, 'utf8')
  const sliceLen = Math.max(0, maxBytes - noticeBytes)
  return `${buf.subarray(0, sliceLen).toString('utf8')}${TRUNCATED_NOTICE}`
}

const SAFE_UNIX_USER_PATTERN = /^[a-z_][a-z0-9_-]*$/

export function isSelfDeployProject(project: Pick<ProjectRow, 'slug'>): boolean {
  return project.slug.trim().toLowerCase() === 'sentinel'
}

export function selfDeployLogPath(deploymentId: number): string {
  if (!Number.isInteger(deploymentId) || deploymentId <= 0) {
    throw new Error(`Invalid deployment id: ${deploymentId}`)
  }
  return `/tmp/sentinel-self-deploy-${deploymentId}.log`
}

export function parseSelfDeployLog(raw: string): { log: string; exitCode: number | null } {
  let exitCode: number | null = null
  const keptLines: string[] = []

  for (const line of raw.split(/\r?\n/)) {
    if (line.startsWith(SELF_DEPLOY_EXIT_MARKER)) {
      const parsed = Number.parseInt(line.slice(SELF_DEPLOY_EXIT_MARKER.length).trim(), 10)
      if (Number.isInteger(parsed)) {
        exitCode = parsed
      }
      continue
    }
    keptLines.push(line)
  }

  return {
    log: keptLines.join('\n').trimEnd(),
    exitCode,
  }
}

function buildInnerDeployInvocation(
  vpsPath: string,
  appsRoot = getEnv().vps.appsRoot,
  deployAsUser = getEnv().vps.deployAsUser,
): string {
  if (!isSafeVpsPath(vpsPath, appsRoot)) {
    throw new Error(`Unsafe VPS path rejected: ${vpsPath}`)
  }

  const targetUser = (deployAsUser ?? '').trim()
  if (targetUser) {
    if (!SAFE_UNIX_USER_PATTERN.test(targetUser)) {
      throw new Error(`Invalid SSH_DEPLOY_AS_USER value: ${targetUser}`)
    }
    const scriptPath = `${vpsPath}/deploy.sh`
    return `sudo -n -H -u ${shellEscape(targetUser)} ${shellEscape(scriptPath)}`
  }

  return `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' ./deploy.sh`
}

export function buildDeployCommand(
  vpsPath: string,
  appsRoot = getEnv().vps.appsRoot,
  deployAsUser = getEnv().vps.deployAsUser,
): string {
  const invocation = buildInnerDeployInvocation(vpsPath, appsRoot, deployAsUser)
  return wrapBashCommand(`cd ${shellEscape(vpsPath)} && ${invocation}`)
}

export function buildSelfDeployCommand(
  vpsPath: string,
  deploymentId: number,
  appsRoot = getEnv().vps.appsRoot,
  deployAsUser = getEnv().vps.deployAsUser,
): string {
  const invocation = buildInnerDeployInvocation(vpsPath, appsRoot, deployAsUser)
  const logFile = selfDeployLogPath(deploymentId)
  const runnerBody = `${invocation} >"$1" 2>&1; printf '\\n${SELF_DEPLOY_EXIT_MARKER}%s\\n' "$?" >>"$1"`
  const script = [
    'set -e',
    `cd ${shellEscape(vpsPath)}`,
    `LOG_FILE=${shellEscape(logFile)}`,
    'rm -f "$LOG_FILE"',
    'install -m 600 /dev/null "$LOG_FILE"',
    `setsid bash -c ${shellEscape(runnerBody)} _ "$LOG_FILE" </dev/null >/dev/null 2>&1 &`,
    'BG_PID=$!',
    'tail -n +1 -f --pid="$BG_PID" "$LOG_FILE" || true',
    `RC=$(sed -n 's/^${SELF_DEPLOY_EXIT_MARKER}//p' "$LOG_FILE" | tail -n1)`,
    'rm -f "$LOG_FILE"',
    'if [ -n "$RC" ]; then exit "$RC"; else exit 1; fi',
  ].join('\n')
  return wrapBashCommand(script)
}

export async function acquireDeploymentLock(
  db: SentinelDb,
  project: ProjectRow,
  commitSha: string | null,
  triggeredBy: string,
): Promise<DeploymentRow> {
  return await db.transaction(async (tx) => {
    await tx.execute(sql`SELECT id FROM projects WHERE id = ${project.id} FOR UPDATE`)

    const running = await tx
      .select({ id: deployments.id })
      .from(deployments)
      .where(and(eq(deployments.projectId, project.id), eq(deployments.status, 'running')))
      .limit(1)

    if (running.length > 0) {
      throw new DeploymentAlreadyRunningError(project.slug)
    }

    const [created] = await tx
      .insert(deployments)
      .values({
        projectId: project.id,
        commitSha,
        status: 'running',
        triggeredBy,
        log: '',
      })
      .returning()

    if (!created) {
      throw new Error('Failed to create deployment record')
    }
    return created
  })
}

export async function executeDeploymentRun(params: {
  db: SentinelDb
  project: ProjectRow
  deployment: DeploymentRow
  ssh?: SshExecutor
  bus?: DeployLogBus
  appsRoot?: string
  deployAsUser?: string
}): Promise<{ status: DeploymentStatus; durationSeconds: number; log: string }> {
  const ssh = params.ssh ?? defaultSshExecutor
  const bus = params.bus ?? deployLogBus
  const startedAt = Date.now()
  let combinedLog = ''

  bus.start(params.deployment.id)

  const selfDeploy = isSelfDeployProject(params.project)
  const appendChunk = (chunk: string) => {
    combinedLog += chunk
    const visibleChunk = selfDeploy ? parseSelfDeployLog(chunk).log : chunk
    if (visibleChunk) {
      bus.append(
        params.deployment.id,
        selfDeploy && chunk.endsWith('\n') ? `${visibleChunk}\n` : visibleChunk,
      )
    }
  }

  try {
    const command = selfDeploy
      ? buildSelfDeployCommand(
          params.project.vpsPath,
          params.deployment.id,
          params.appsRoot,
          params.deployAsUser,
        )
      : buildDeployCommand(params.project.vpsPath, params.appsRoot, params.deployAsUser)
    const result = await ssh.execute(command, {
      onStdout: appendChunk,
      onStderr: appendChunk,
    })

    if (!combinedLog && (result.stdout || result.stderr)) {
      combinedLog = [result.stdout, result.stderr].filter(Boolean).join('\n')
    }

    const cleanedLog = selfDeploy ? parseSelfDeployLog(combinedLog).log : combinedLog
    const durationSeconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000))
    const status: DeploymentStatus = result.exitCode === 0 ? 'success' : 'failed'
    const finalLog = truncateLog(
      cleanedLog || (status === 'failed' ? `Exit code ${result.exitCode}` : ''),
    )
    const now = new Date()

    await params.db
      .update(deployments)
      .set({
        status,
        durationSeconds,
        log: finalLog,
        updatedAt: now,
      })
      .where(eq(deployments.id, params.deployment.id))

    if (status === 'success' && params.deployment.commitSha) {
      await params.db
        .update(projects)
        .set({
          lastCommitDeployed: params.deployment.commitSha,
          latestCommitAvailable: params.deployment.commitSha,
          commitsBehind: 0,
          updatedAt: now,
        })
        .where(eq(projects.id, params.project.id))
    }

    if (status === 'success' && params.project.productionUrl && getEnv().apiflashAccessKey) {
      void captureProjectScreenshot(params.db, params.project).catch((err) => {
        console.warn(
          `[sentinel:screenshot] Post-deploy capture failed for ${params.project.slug}:`,
          err,
        )
      })
    }

    bus.finish(params.deployment.id, status, durationSeconds)
    return { status, durationSeconds, log: finalLog }
  } catch (error) {
    const durationSeconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000))
    const message = error instanceof Error ? error.message : String(error)
    const finalLog = truncateLog(combinedLog ? `${combinedLog}\n${message}` : message)

    await params.db
      .update(deployments)
      .set({
        status: 'failed',
        durationSeconds,
        log: finalLog,
        updatedAt: new Date(),
      })
      .where(eq(deployments.id, params.deployment.id))

    bus.finish(params.deployment.id, 'failed', durationSeconds)
    return { status: 'failed', durationSeconds, log: finalLog }
  }
}

export async function startProjectDeployment(
  db: SentinelDb,
  project: ProjectRow,
  triggeredBy: string,
): Promise<DeploymentRow> {
  let commitSha = project.latestCommitAvailable ?? project.lastCommitDeployed
  const repo = extractGithubRepo(project.repoUrl)
  if (repo) {
    const latest = await fetchLatestBranchCommit(repo, project.productionBranch)
    if (latest?.sha) {
      commitSha = latest.sha
    }
  }

  const deployment = await acquireDeploymentLock(db, project, commitSha, triggeredBy)

  void executeDeploymentRun({ db, project, deployment })

  return deployment
}

export interface ReconcileDeploymentsOptions {
  ssh?: SshExecutor
  bus?: DeployLogBus
  env?: SentinelEnv
  maxPollAttempts?: number
  pollIntervalMs?: number
  syncVpsOnSuccess?: boolean
}

function sleepMs(ms: number): Promise<void> {
  if (ms <= 0) {
    return Promise.resolve()
  }
  return new Promise((resolve) => {
    setTimeout(resolve, ms)
  })
}

async function finalizeReconciledDeployment(params: {
  db: SentinelDb
  deployment: DeploymentRow
  project: ProjectRow
  status: DeploymentStatus
  log: string
  bus: DeployLogBus
}): Promise<void> {
  const now = new Date()
  const durationSeconds = Math.max(
    0,
    Math.round((now.getTime() - params.deployment.createdAt.getTime()) / 1000),
  )
  const finalLog = truncateLog(params.log)

  await params.db
    .update(deployments)
    .set({
      status: params.status,
      durationSeconds,
      log: finalLog,
      updatedAt: now,
    })
    .where(eq(deployments.id, params.deployment.id))

  if (params.status === 'success' && params.deployment.commitSha) {
    await params.db
      .update(projects)
      .set({
        lastCommitDeployed: params.deployment.commitSha,
        latestCommitAvailable: params.deployment.commitSha,
        commitsBehind: 0,
        updatedAt: now,
      })
      .where(eq(projects.id, params.project.id))
  }

  if (finalLog) {
    params.bus.append(params.deployment.id, finalLog)
  }
  params.bus.finish(params.deployment.id, params.status, durationSeconds)
}

async function reconcileSelfDeployment(
  db: SentinelDb,
  deployment: DeploymentRow,
  project: ProjectRow,
  options: ReconcileDeploymentsOptions,
): Promise<DeploymentStatus> {
  const ssh = options.ssh ?? defaultSshExecutor
  const bus = options.bus ?? deployLogBus
  const env = options.env ?? getEnv()
  const maxAttempts = options.maxPollAttempts ?? 8
  const pollIntervalMs = options.pollIntervalMs ?? 2000

  if (!env.vps.host) {
    const fallbackLog =
      deployment.log ||
      '[sentinel] Redémarrage du conteneur Sentinel détecté suite à un auto-déploiement.'
    await finalizeReconciledDeployment({
      db,
      deployment,
      project,
      status: 'success',
      log: fallbackLog,
      bus,
    })
    return 'success'
  }

  const logFile = selfDeployLogPath(deployment.id)
  const readCmd = wrapBashCommand(
    `LOG_FILE=${shellEscape(logFile)}; if [ ! -f "$LOG_FILE" ]; then printf '${SELF_DEPLOY_MISSING_MARKER}\\n'; exit 0; fi; cat "$LOG_FILE"`,
  )

  let lastObservedLog = deployment.log
  let resolvedStatus: DeploymentStatus = 'success'
  let shouldCleanupLog = false

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const res = await ssh.execute(readCmd, { timeoutSeconds: 15, env })
    if (res.exitCode !== 0) {
      lastObservedLog =
        lastObservedLog ||
        '[sentinel] Redémarrage du conteneur Sentinel détecté suite à un auto-déploiement.'
      break
    }

    if (res.stdout.includes(SELF_DEPLOY_MISSING_MARKER)) {
      lastObservedLog =
        lastObservedLog ||
        '[sentinel] Redémarrage du conteneur Sentinel détecté suite à un auto-déploiement.'
      break
    }

    const parsed = parseSelfDeployLog(res.stdout)
    if (parsed.log) {
      lastObservedLog = parsed.log
    }

    if (parsed.exitCode !== null) {
      resolvedStatus = parsed.exitCode === 0 ? 'success' : 'failed'
      shouldCleanupLog = true
      break
    }

    if (attempt + 1 < maxAttempts) {
      await sleepMs(pollIntervalMs)
    } else {
      lastObservedLog = [
        lastObservedLog,
        '[sentinel] Redémarrage de Sentinel confirmé (nettoyage final en cours en arrière-plan).',
      ]
        .filter(Boolean)
        .join('\n')
    }
  }

  if (shouldCleanupLog) {
    await ssh
      .execute(wrapBashCommand(`rm -f ${shellEscape(logFile)}`), { timeoutSeconds: 10, env })
      .catch(() => {})
  }

  await finalizeReconciledDeployment({
    db,
    deployment,
    project,
    status: resolvedStatus,
    log: lastObservedLog,
    bus,
  })

  if (resolvedStatus === 'success' && options.syncVpsOnSuccess !== false) {
    void discoverVpsProjects(db, ssh).catch((error) => {
      console.warn('[sentinel:deploy] Post-self-deploy VPS discovery failed:', error)
    })
  }

  return resolvedStatus
}

export async function reconcileInterruptedDeployments(
  db: SentinelDb,
  options: ReconcileDeploymentsOptions = {},
): Promise<{ reconciled: number; selfSucceeded: number; failed: number }> {
  const bus = options.bus ?? deployLogBus
  const rows = await db
    .select({
      deployment: deployments,
      project: projects,
    })
    .from(deployments)
    .innerJoin(projects, eq(deployments.projectId, projects.id))
    .where(eq(deployments.status, 'running'))

  if (rows.length === 0) {
    return { reconciled: 0, selfSucceeded: 0, failed: 0 }
  }

  let selfSucceeded = 0
  let failed = 0

  for (const { deployment, project } of rows) {
    if (isSelfDeployProject(project)) {
      const status = await reconcileSelfDeployment(db, deployment, project, options)
      if (status === 'success') {
        selfSucceeded++
      } else {
        failed++
      }
      continue
    }

    const notice = '[sentinel] Déploiement interrompu par un redémarrage du serveur Sentinel.'
    const combined = deployment.log ? `${deployment.log}\n${notice}` : notice
    await finalizeReconciledDeployment({
      db,
      deployment,
      project,
      status: 'failed',
      log: combined,
      bus,
    })
    failed++
  }

  console.info(
    `[sentinel:deploy] Reconciled ${rows.length} interrupted deployment(s) (selfSucceeded=${selfSucceeded}, failed=${failed})`,
  )

  return { reconciled: rows.length, selfSucceeded, failed }
}
