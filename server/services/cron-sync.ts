import { and, eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { cronJobs, jobExecutions, type ProjectRow, projects } from '#server/db/schema'
import { truncateLog } from '#server/services/deploy'
import {
  defaultSshExecutor,
  type SshExecutor,
  shellEscape,
  wrapBashCommand,
} from '#server/services/ssh'
import { getEnv } from '#server/utils/env'
import { isSafeVpsPath } from '#shared/schemas/project'
import type { CronStatus } from '#shared/types/sentinel'

export const MAX_CRON_LOG_BYTES = 16 * 1024

const SUCCESS_STATUSES = new Set(['success', 'ok', 'passed'])
const FAILED_STATUSES = new Set(['failed', 'fail', 'failure', 'error'])
const IGNORED_LEGACY_KEYS = new Set(['version', 'generated_at', 'jobs', 'cron_jobs'])

export interface NormalizedCronJobInput {
  name: string
  command: string | null
  schedule: string | null
  lastExecutionAt: Date | null
  lastStatus: CronStatus
  lastDuration: number | null
  lastLog: string
}

export function normalizeCronStatus(value: unknown): CronStatus {
  const normalized = String(value ?? '')
    .trim()
    .toLowerCase()
  if (SUCCESS_STATUSES.has(normalized)) {
    return 'success'
  }
  if (FAILED_STATUSES.has(normalized)) {
    return 'failed'
  }
  return 'unknown'
}

function parseOptionalInt(value: unknown): number | null {
  if (value === null || value === undefined || value === '') {
    return null
  }
  const num = Number(value)
  return Number.isInteger(num) && num >= 0 ? num : null
}

function parseOptionalDate(value: unknown): Date | null {
  if (!value) {
    return null
  }
  const date = new Date(String(value))
  return Number.isNaN(date.getTime()) ? null : date
}

export function parseCronStatusPayload(payload: unknown): NormalizedCronJobInput[] {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return []
  }

  const record = payload as Record<string, unknown>
  let rawJobs: Array<Record<string, unknown>> = []

  if (Array.isArray(record.jobs)) {
    rawJobs = record.jobs.filter(
      (item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object',
    )
  } else if (Array.isArray(record.cron_jobs)) {
    rawJobs = record.cron_jobs.filter(
      (item): item is Record<string, unknown> => Boolean(item) && typeof item === 'object',
    )
  } else {
    for (const [key, value] of Object.entries(record)) {
      if (IGNORED_LEGACY_KEYS.has(key)) {
        continue
      }
      if (value && typeof value === 'object' && !Array.isArray(value)) {
        rawJobs.push({ ...(value as Record<string, unknown>), name: key })
      }
    }
  }

  const normalized: NormalizedCronJobInput[] = []
  for (const item of rawJobs) {
    const name = String(item.name ?? '').trim()
    if (!name) {
      continue
    }

    const command =
      typeof item.command === 'string' && item.command.trim() ? item.command.trim() : null
    const schedule =
      typeof item.schedule === 'string' && item.schedule.trim() ? item.schedule.trim() : null

    normalized.push({
      name,
      command,
      schedule,
      lastExecutionAt: parseOptionalDate(item.last_execution_at ?? item.last_run),
      lastStatus: normalizeCronStatus(item.last_status ?? item.status),
      lastDuration: parseOptionalInt(item.last_duration ?? item.duration),
      lastLog: truncateLog(String(item.last_log ?? item.log ?? ''), MAX_CRON_LOG_BYTES),
    })
  }

  return normalized
}

export function buildCronStatusCommand(vpsPath: string, appsRoot = getEnv().vps.appsRoot): string {
  if (!isSafeVpsPath(vpsPath, appsRoot)) {
    throw new Error(`Unsafe VPS path rejected: ${vpsPath}`)
  }
  return wrapBashCommand(
    `cd ${shellEscape(vpsPath)} && (if [ -x ./status.sh ]; then ./status.sh; elif [ -f sentinel/cron-status.json ]; then cat sentinel/cron-status.json; else exit 1; fi)`,
  )
}

export async function syncProjectCronStatus(
  db: SentinelDb,
  project: ProjectRow,
  ssh: SshExecutor = defaultSshExecutor,
): Promise<{ synced: boolean; jobsCount: number; error?: string }> {
  const command = buildCronStatusCommand(project.vpsPath)
  const result = await ssh.execute(command, { timeoutSeconds: 20 })

  if (result.exitCode !== 0) {
    return {
      synced: false,
      jobsCount: 0,
      error: result.stderr.trim() || `status.sh exited with code ${result.exitCode}`,
    }
  }

  let parsedPayload: unknown
  try {
    parsedPayload = JSON.parse(result.stdout)
  } catch (error) {
    return {
      synced: false,
      jobsCount: 0,
      error: `Invalid cron status JSON: ${error instanceof Error ? error.message : String(error)}`,
    }
  }

  const jobs = parseCronStatusPayload(parsedPayload)
  const now = new Date()

  for (const item of jobs) {
    const existingRows = await db
      .select()
      .from(cronJobs)
      .where(and(eq(cronJobs.projectId, project.id), eq(cronJobs.name, item.name)))
      .limit(1)

    const existing = existingRows[0]
    let cronJobId: number

    if (!existing) {
      const [inserted] = await db
        .insert(cronJobs)
        .values({
          projectId: project.id,
          name: item.name,
          command: item.command ?? 'unknown',
          schedule: item.schedule ?? 'unknown',
          lastStatus: item.lastStatus,
          lastDuration: item.lastDuration,
          lastExecutionAt: item.lastExecutionAt,
          updatedAt: now,
        })
        .returning()
      if (!inserted) {
        continue
      }
      cronJobId = inserted.id
    } else {
      cronJobId = existing.id
      await db
        .update(cronJobs)
        .set({
          command: item.command ?? existing.command ?? 'unknown',
          schedule: item.schedule ?? existing.schedule ?? 'unknown',
          lastStatus: item.lastStatus,
          lastDuration: item.lastDuration,
          lastExecutionAt: item.lastExecutionAt,
          updatedAt: now,
        })
        .where(eq(cronJobs.id, existing.id))
    }

    if (item.lastExecutionAt) {
      const duplicate = await db
        .select({ id: jobExecutions.id })
        .from(jobExecutions)
        .where(
          and(
            eq(jobExecutions.cronJobId, cronJobId),
            eq(jobExecutions.executedAt, item.lastExecutionAt),
          ),
        )
        .limit(1)

      if (duplicate.length === 0) {
        await db.insert(jobExecutions).values({
          cronJobId,
          status: item.lastStatus,
          duration: item.lastDuration,
          log: item.lastLog,
          executedAt: item.lastExecutionAt,
        })
      }
    }
  }

  await db
    .update(projects)
    .set({
      cronSyncedAt: now,
      updatedAt: now,
    })
    .where(eq(projects.id, project.id))

  return { synced: true, jobsCount: jobs.length }
}

export async function syncAllProjectsCronStatus(
  db: SentinelDb,
  ssh: SshExecutor = defaultSshExecutor,
): Promise<{ syncedCount: number; failedSlugs: string[] }> {
  const monitoredProjects = await db
    .select()
    .from(projects)
    .where(eq(projects.cronMonitoringEnabled, true))

  let syncedCount = 0
  const failedSlugs: string[] = []

  for (const project of monitoredProjects) {
    try {
      const result = await syncProjectCronStatus(db, project, ssh)
      if (result.synced) {
        syncedCount += 1
      } else {
        failedSlugs.push(project.slug)
      }
    } catch (error) {
      console.error(`[sentinel:cron] Sync failed for ${project.slug}:`, error)
      failedSlugs.push(project.slug)
    }
  }

  return { syncedCount, failedSlugs }
}
