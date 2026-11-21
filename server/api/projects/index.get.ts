import { asc, desc, eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { cronJobs, deployments, githubPullRequests, projects } from '#server/db/schema'
import { serializeProjectSummary, serializePullRequest } from '#server/utils/project-serializer'
import type { ProjectSummaryDto, ProjectsDashboardResponse } from '#shared/types/api'

function computeBasicCronSummary(
  enabled: boolean,
  jobs: Array<{ lastStatus: string; lastExecutionAt: Date | null }>,
): ProjectSummaryDto['cronSummaryStatus'] {
  if (!enabled) {
    return 'disabled'
  }
  if (jobs.length === 0) {
    return 'not_reported'
  }
  if (jobs.some((job) => job.lastStatus === 'failed')) {
    return 'failed'
  }
  if (jobs.some((job) => !job.lastExecutionAt)) {
    return 'never_run'
  }
  if (jobs.every((job) => job.lastStatus === 'success')) {
    return 'ok'
  }
  return 'unknown'
}

export default defineEventHandler(async (): Promise<ProjectsDashboardResponse> => {
  const db = getDb()
  const [projectRows, openPrRows, runningDeployRows, cronJobRows] = await Promise.all([
    db.select().from(projects).orderBy(asc(projects.name)),
    db
      .select()
      .from(githubPullRequests)
      .where(eq(githubPullRequests.state, 'open'))
      .orderBy(desc(githubPullRequests.isRenovate), desc(githubPullRequests.githubUpdatedAt)),
    db.select().from(deployments).where(eq(deployments.status, 'running')),
    db.select().from(cronJobs),
  ])

  const projectById = new Map(projectRows.map((row) => [row.id, row]))
  const runningProjectIds = new Set(runningDeployRows.map((row) => row.projectId))

  const openPrCounts = new Map<number, { total: number; renovate: number }>()
  for (const pr of openPrRows) {
    const current = openPrCounts.get(pr.projectId) ?? { total: 0, renovate: 0 }
    current.total += 1
    if (pr.isRenovate) {
      current.renovate += 1
    }
    openPrCounts.set(pr.projectId, current)
  }

  const cronsByProject = new Map<number, typeof cronJobRows>()
  for (const job of cronJobRows) {
    const list = cronsByProject.get(job.projectId) ?? []
    list.push(job)
    cronsByProject.set(job.projectId, list)
  }

  const serializedProjects = projectRows.map((row) => {
    const prCount = openPrCounts.get(row.id) ?? { total: 0, renovate: 0 }
    const projectCrons = cronsByProject.get(row.id) ?? []
    return serializeProjectSummary(row, {
      openPrsCount: prCount.total,
      openRenovatePrsCount: prCount.renovate,
      hasRunningDeployment: runningProjectIds.has(row.id),
      cronSummaryStatus: computeBasicCronSummary(row.cronMonitoringEnabled, projectCrons),
    })
  })

  const openPullRequests = openPrRows.map((pr) => {
    const owner = projectById.get(pr.projectId)
    return serializePullRequest(pr, owner ? { slug: owner.slug, name: owner.name } : undefined)
  })

  return {
    projects: serializedProjects,
    openPullRequests,
    kpis: {
      totalProjects: serializedProjects.length,
      deployPendingCount: serializedProjects.filter((p) => p.commitsBehind > 0).length,
      openRenovatePrsCount: openPullRequests.filter((pr) => pr.isRenovate).length,
      openPrsCount: openPullRequests.length,
      maintenanceCount: serializedProjects.filter((p) => p.maintenanceMode).length,
      cronAlertsCount: serializedProjects.filter((p) =>
        ['failed', 'overdue', 'never_run', 'not_reported', 'unknown'].includes(p.cronSummaryStatus),
      ).length,
    },
  }
})
