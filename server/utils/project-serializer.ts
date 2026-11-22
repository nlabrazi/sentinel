import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import {
  type CronJobRow,
  type DeploymentRow,
  type GithubPullRequestRow,
  type JobExecutionRow,
  type ProjectRow,
  projects,
} from '#server/db/schema'
import {
  buildGithubCompareDeployUrl,
  buildGithubCompareStagingUrl,
  computeStagingSyncStatus,
  extractGithubRepo,
} from '#shared/schemas/project'
import type {
  CronJobDto,
  DeploymentDto,
  JobExecutionDto,
  ProjectSummaryDto,
  PullRequestDto,
} from '#shared/types/api'

export async function findProjectBySlugOrThrow(db: SentinelDb, slug: string): Promise<ProjectRow> {
  const rows = await db.select().from(projects).where(eq(projects.slug, slug)).limit(1)
  const project = rows[0]
  if (!project) {
    throw createError({
      statusCode: 404,
      statusMessage: 'Not Found',
      message: `Project '${slug}' not found`,
    })
  }
  return project
}

export function serializeDeployment(
  row: DeploymentRow,
  projectMeta?: { slug: string; name: string },
): DeploymentDto {
  return {
    id: row.id,
    projectId: row.projectId,
    projectSlug: projectMeta?.slug,
    projectName: projectMeta?.name,
    commitSha: row.commitSha,
    status: row.status,
    triggeredBy: row.triggeredBy,
    durationSeconds: row.durationSeconds,
    log: row.log,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  }
}

export function serializePullRequest(
  row: GithubPullRequestRow,
  projectMeta?: { slug: string; name: string },
): PullRequestDto {
  return {
    id: row.id,
    projectId: row.projectId,
    projectSlug: projectMeta?.slug,
    projectName: projectMeta?.name,
    number: row.number,
    title: row.title,
    state: row.state,
    isRenovate: row.isRenovate,
    draft: row.draft,
    authorLogin: row.authorLogin,
    headRef: row.headRef,
    baseRef: row.baseRef,
    htmlUrl: row.htmlUrl,
    openedAt: row.openedAt?.toISOString() ?? null,
    mergedAt: row.mergedAt?.toISOString() ?? null,
    githubUpdatedAt: row.githubUpdatedAt?.toISOString() ?? null,
  }
}

export function serializeJobExecution(row: JobExecutionRow): JobExecutionDto {
  return {
    id: row.id,
    cronJobId: row.cronJobId,
    status: row.status,
    duration: row.duration,
    log: row.log,
    executedAt: row.executedAt.toISOString(),
  }
}

export function serializeCronJob(
  row: CronJobRow,
  executions: JobExecutionRow[],
  displayStatus: CronJobDto['displayStatus'] = row.lastStatus === 'success'
    ? 'ok'
    : row.lastStatus === 'failed'
      ? 'failed'
      : row.lastExecutionAt
        ? 'unknown'
        : 'never_run',
): CronJobDto {
  return {
    id: row.id,
    projectId: row.projectId,
    name: row.name,
    command: row.command,
    schedule: row.schedule,
    lastStatus: row.lastStatus,
    displayStatus,
    lastDuration: row.lastDuration,
    lastExecutionAt: row.lastExecutionAt?.toISOString() ?? null,
    executions: executions.map(serializeJobExecution),
  }
}

export function serializeProjectSummary(
  row: ProjectRow,
  extras: {
    openPrsCount?: number
    openRenovatePrsCount?: number
    hasRunningDeployment?: boolean
    cronSummaryStatus?: ProjectSummaryDto['cronSummaryStatus']
  } = {},
): ProjectSummaryDto {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    kind: row.kind,
    vpsPath: row.vpsPath,
    repoUrl: row.repoUrl,
    githubRepo: extractGithubRepo(row.repoUrl),
    productionBranch: row.productionBranch,
    stagingBranch: row.stagingBranch,
    productionUrl: row.productionUrl,
    grafanaAppValue: row.grafanaAppValue,
    umamiWebsiteId: row.umamiWebsiteId,
    hasDeployScript: row.hasDeployScript,
    hasStatusScript: row.hasStatusScript,
    cronMonitoringEnabled: row.cronMonitoringEnabled,
    maintenanceMode: row.maintenanceMode,
    lastCommitDeployed: row.lastCommitDeployed,
    latestCommitAvailable: row.latestCommitAvailable,
    commitsBehind: row.commitsBehind,
    stagingCommitsAhead: row.stagingCommitsAhead,
    stagingCommitsBehind: row.stagingCommitsBehind,
    stagingSyncStatus: computeStagingSyncStatus(
      row.stagingBranch,
      row.stagingCommitsAhead,
      row.stagingCommitsBehind,
    ),
    githubCompareStagingUrl: buildGithubCompareStagingUrl(
      row.repoUrl,
      row.productionBranch,
      row.stagingBranch,
    ),
    githubCompareDeployUrl: buildGithubCompareDeployUrl(
      row.repoUrl,
      row.lastCommitDeployed,
      row.productionBranch,
    ),
    umamiVisitors24h: row.umamiVisitors24h,
    umamiPageviews24h: row.umamiPageviews24h,
    umamiBounceRate: row.umamiBounceRate,
    umamiSyncError: row.umamiSyncError,
    umamiSyncedAt: row.umamiSyncedAt?.toISOString() ?? null,
    screenshotUrl: row.screenshotUpdatedAt
      ? `/api/projects/${encodeURIComponent(row.slug)}/screenshot?v=${Math.floor(row.screenshotUpdatedAt.getTime() / 1000)}`
      : null,
    screenshotUpdatedAt: row.screenshotUpdatedAt?.toISOString() ?? null,
    vpsSyncedAt: row.vpsSyncedAt?.toISOString() ?? null,
    githubSyncedAt: row.githubSyncedAt?.toISOString() ?? null,
    cronSyncedAt: row.cronSyncedAt?.toISOString() ?? null,
    openPrsCount: extras.openPrsCount ?? 0,
    openRenovatePrsCount: extras.openRenovatePrsCount ?? 0,
    hasRunningDeployment: extras.hasRunningDeployment ?? false,
    cronSummaryStatus:
      extras.cronSummaryStatus ?? (row.cronMonitoringEnabled ? 'not_reported' : 'disabled'),
  }
}
