import { timingSafeEqual } from 'node:crypto'
import { CronExpressionParser } from 'cron-parser'
import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { type CronJobRow, cronJobs, type ProjectRow, projects } from '#server/db/schema'
import { getEnv } from '#server/utils/env'
import type { CronJobDto, ProjectSummaryDto } from '#shared/types/api'

const METRICS_HELP = {
  job_healthy: 'Whether the cron job needs no attention (1 healthy, 0 unhealthy).',
  job_failed: 'Whether the last execution failed.',
  job_overdue: 'Whether an expected cron occurrence was missed beyond the grace period.',
  job_last_execution_timestamp_seconds:
    'Unix timestamp of the last cron execution; omitted if never run.',
  job_last_duration_seconds: 'Duration of the last cron execution; omitted if unknown.',
  project_last_sync_timestamp_seconds:
    'Unix timestamp of the last successful cron sync; omitted if never synced.',
  project_sync_stale: 'Whether the project cron sync is stale or missing.',
  project_healthy: 'Whether the project has healthy cron jobs and a recent sync.',
} as const

type MetricKey = keyof typeof METRICS_HELP

export interface CronEvalOptions {
  at?: Date
  overdueGraceMinutes?: number
  syncStaleAfterMinutes?: number
}

export function isValidCronSchedule(schedule: string | null | undefined): boolean {
  if (!schedule || schedule === 'unknown') {
    return false
  }
  try {
    CronExpressionParser.parse(schedule.trim(), { tz: 'UTC' })
    return true
  } catch {
    return false
  }
}

export function isCronJobOverdue(
  job: Pick<CronJobRow, 'schedule' | 'lastExecutionAt'>,
  options: CronEvalOptions = {},
): boolean {
  if (!job.lastExecutionAt) {
    return false
  }
  const at = options.at ?? new Date()
  const graceMinutes = options.overdueGraceMinutes ?? getEnv().cron.overdueGraceMinutes

  try {
    const cutoffMs = at.getTime() - graceMinutes * 60 * 1000
    // Floor to second and add 1 second so exact cutoff second is included as previous occurrence
    const cutoffInclusive = new Date(Math.floor(cutoffMs / 1000) * 1000 + 1000)
    const expr = CronExpressionParser.parse(job.schedule.trim(), {
      currentDate: cutoffInclusive,
      tz: 'UTC',
    })
    const expectedAt = expr.prev().toDate()
    return job.lastExecutionAt.getTime() < expectedAt.getTime()
  } catch {
    return false
  }
}

export function evaluateCronJobStatus(
  job: Pick<CronJobRow, 'schedule' | 'lastStatus' | 'lastExecutionAt'>,
  options: CronEvalOptions = {},
): CronJobDto['displayStatus'] {
  if (job.lastStatus === 'failed') {
    return 'failed'
  }
  if (isCronJobOverdue(job, options)) {
    return 'overdue'
  }
  if (!job.lastExecutionAt) {
    return 'never_run'
  }
  if (job.lastStatus !== 'success' || !isValidCronSchedule(job.schedule)) {
    return 'unknown'
  }
  return 'ok'
}

export function cronJobNeedsAttention(
  job: Pick<CronJobRow, 'schedule' | 'lastStatus' | 'lastExecutionAt'>,
  options: CronEvalOptions = {},
): boolean {
  return evaluateCronJobStatus(job, options) !== 'ok'
}

export function isProjectCronSyncStale(
  project: Pick<ProjectRow, 'cronMonitoringEnabled' | 'cronSyncedAt'>,
  options: CronEvalOptions = {},
): boolean {
  if (!project.cronMonitoringEnabled) {
    return false
  }
  if (!project.cronSyncedAt) {
    return true
  }
  const at = options.at ?? new Date()
  const staleAfterMinutes = options.syncStaleAfterMinutes ?? getEnv().cron.syncStaleAfterMinutes
  return project.cronSyncedAt.getTime() <= at.getTime() - staleAfterMinutes * 60 * 1000
}

export function evaluateProjectCronSummary(
  project: Pick<ProjectRow, 'cronMonitoringEnabled' | 'cronSyncedAt'>,
  jobs: Array<Pick<CronJobRow, 'schedule' | 'lastStatus' | 'lastExecutionAt'>>,
  options: CronEvalOptions = {},
): ProjectSummaryDto['cronSummaryStatus'] {
  if (!project.cronMonitoringEnabled) {
    return 'disabled'
  }
  if (jobs.length === 0) {
    return 'not_reported'
  }

  const statuses = jobs.map((job) => evaluateCronJobStatus(job, options))
  if (statuses.includes('failed')) {
    return 'failed'
  }
  if (statuses.includes('overdue')) {
    return 'overdue'
  }
  if (statuses.includes('never_run')) {
    return 'never_run'
  }
  if (statuses.includes('unknown')) {
    return 'unknown'
  }
  return 'ok'
}

export function projectCronNeedsAttention(
  project: Pick<ProjectRow, 'cronMonitoringEnabled' | 'cronSyncedAt'>,
  jobs: Array<Pick<CronJobRow, 'schedule' | 'lastStatus' | 'lastExecutionAt'>>,
  options: CronEvalOptions = {},
): boolean {
  if (isProjectCronSyncStale(project, options)) {
    return true
  }
  return evaluateProjectCronSummary(project, jobs, options) !== 'ok'
}

function escapePrometheusLabel(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')
}

function formatSample(metric: MetricKey, labels: Record<string, string>, value: number): string {
  const encoded = Object.entries(labels)
    .map(([key, val]) => `${key}="${escapePrometheusLabel(val)}"`)
    .join(',')
  return `sentinel_cron_${metric}{${encoded}} ${value}`
}

export function renderPrometheusCronMetrics(
  entries: Array<{
    project: Pick<ProjectRow, 'slug' | 'cronMonitoringEnabled' | 'cronSyncedAt'>
    jobs: Array<
      Pick<CronJobRow, 'name' | 'schedule' | 'lastStatus' | 'lastDuration' | 'lastExecutionAt'>
    >
  }>,
  options: CronEvalOptions = {},
): string {
  const samples: Record<MetricKey, string[]> = {
    job_healthy: [],
    job_failed: [],
    job_overdue: [],
    job_last_execution_timestamp_seconds: [],
    job_last_duration_seconds: [],
    project_last_sync_timestamp_seconds: [],
    project_sync_stale: [],
    project_healthy: [],
  }

  for (const { project, jobs } of entries) {
    if (!project.cronMonitoringEnabled) {
      continue
    }

    const projectLabels = { project: project.slug }
    if (project.cronSyncedAt) {
      samples.project_last_sync_timestamp_seconds.push(
        formatSample(
          'project_last_sync_timestamp_seconds',
          projectLabels,
          Math.floor(project.cronSyncedAt.getTime() / 1000),
        ),
      )
    }

    samples.project_sync_stale.push(
      formatSample(
        'project_sync_stale',
        projectLabels,
        isProjectCronSyncStale(project, options) ? 1 : 0,
      ),
    )
    samples.project_healthy.push(
      formatSample(
        'project_healthy',
        projectLabels,
        projectCronNeedsAttention(project, jobs, options) ? 0 : 1,
      ),
    )

    for (const job of jobs) {
      const jobLabels = { project: project.slug, job: job.name }
      samples.job_healthy.push(
        formatSample('job_healthy', jobLabels, cronJobNeedsAttention(job, options) ? 0 : 1),
      )
      samples.job_failed.push(
        formatSample('job_failed', jobLabels, job.lastStatus === 'failed' ? 1 : 0),
      )
      samples.job_overdue.push(
        formatSample('job_overdue', jobLabels, isCronJobOverdue(job, options) ? 1 : 0),
      )

      if (job.lastExecutionAt) {
        samples.job_last_execution_timestamp_seconds.push(
          formatSample(
            'job_last_execution_timestamp_seconds',
            jobLabels,
            Math.floor(job.lastExecutionAt.getTime() / 1000),
          ),
        )
      }
      if (job.lastDuration !== null && job.lastDuration !== undefined) {
        samples.job_last_duration_seconds.push(
          formatSample('job_last_duration_seconds', jobLabels, job.lastDuration),
        )
      }
    }
  }

  const lines: string[] = []
  for (const [key, help] of Object.entries(METRICS_HELP) as Array<[MetricKey, string]>) {
    const metricName = `sentinel_cron_${key}`
    lines.push(`# HELP ${metricName} ${help}`)
    lines.push(`# TYPE ${metricName} gauge`)
    lines.push(...samples[key])
  }

  return `${lines.join('\n')}\n`
}

export function verifyMetricsBearerToken(
  authorizationHeader: string | undefined,
  expectedToken: string,
): boolean {
  if (!expectedToken || !authorizationHeader) {
    return false
  }
  const match = authorizationHeader.match(/^Bearer (\S+)$/)
  const provided = match?.[1]
  if (!provided) {
    return false
  }
  const providedBuf = Buffer.from(provided, 'utf8')
  const expectedBuf = Buffer.from(expectedToken, 'utf8')
  if (providedBuf.length !== expectedBuf.length) {
    return false
  }
  return timingSafeEqual(providedBuf, expectedBuf)
}

export async function generatePrometheusMetricsText(
  db: SentinelDb,
  options: CronEvalOptions = {},
): Promise<string> {
  const [monitoredProjects, allCronJobs] = await Promise.all([
    db.select().from(projects).where(eq(projects.cronMonitoringEnabled, true)),
    db.select().from(cronJobs),
  ])

  const jobsByProject = new Map<number, CronJobRow[]>()
  for (const job of allCronJobs) {
    const list = jobsByProject.get(job.projectId) ?? []
    list.push(job)
    jobsByProject.set(job.projectId, list)
  }

  const entries = monitoredProjects.map((project) => ({
    project,
    jobs: jobsByProject.get(project.id) ?? [],
  }))

  return renderPrometheusCronMetrics(entries, options)
}
