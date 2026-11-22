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
import { getEnv } from '#server/utils/env'
import { extractGithubRepo, isSafeVpsPath } from '#shared/schemas/project'
import type { DeploymentStatus } from '#shared/types/sentinel'

export const MAX_DEPLOY_LOG_BYTES = 64 * 1024
const TRUNCATED_NOTICE = '\n\n[Log truncated]\n'

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

export function buildDeployCommand(vpsPath: string, appsRoot = getEnv().vps.appsRoot): string {
  if (!isSafeVpsPath(vpsPath, appsRoot)) {
    throw new Error(`Unsafe VPS path rejected: ${vpsPath}`)
  }
  return wrapBashCommand(`cd ${shellEscape(vpsPath)} && ./deploy.sh`)
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
}): Promise<{ status: DeploymentStatus; durationSeconds: number; log: string }> {
  const ssh = params.ssh ?? defaultSshExecutor
  const bus = params.bus ?? deployLogBus
  const startedAt = Date.now()
  let combinedLog = ''

  bus.start(params.deployment.id)

  const appendChunk = (chunk: string) => {
    combinedLog += chunk
    bus.append(params.deployment.id, chunk)
  }

  try {
    const command = buildDeployCommand(params.project.vpsPath, params.appsRoot)
    const result = await ssh.execute(command, {
      onStdout: appendChunk,
      onStderr: appendChunk,
    })

    if (!combinedLog && (result.stdout || result.stderr)) {
      combinedLog = [result.stdout, result.stderr].filter(Boolean).join('\n')
    }

    const durationSeconds = Math.max(0, Math.round((Date.now() - startedAt) / 1000))
    const status: DeploymentStatus = result.exitCode === 0 ? 'success' : 'failed'
    const finalLog = truncateLog(
      combinedLog || (status === 'failed' ? `Exit code ${result.exitCode}` : ''),
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
