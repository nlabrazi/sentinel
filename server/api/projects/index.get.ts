import { asc, desc, eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { cronJobs, deployments, githubPullRequests, projects } from '#server/db/schema'
import { evaluateProjectCronSummary } from '#server/services/cron-metrics'
import { serializeProjectSummary, serializePullRequest } from '#server/utils/project-serializer'
import { isProjectDeployReady } from '#shared/schemas/project'
import type { ProjectsDashboardResponse } from '#shared/types/api'

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
      cronSummaryStatus: evaluateProjectCronSummary(row, projectCrons),
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
      deployPendingCount: serializedProjects.filter((p) =>
        isProjectDeployReady(p.commitsBehind, p.productionCiStatus),
      ).length,
      openRenovatePrsCount: openPullRequests.filter((pr) => pr.isRenovate).length,
      openPrsCount: openPullRequests.length,
      maintenanceCount: serializedProjects.filter((p) => p.maintenanceMode).length,
      cronAlertsCount: serializedProjects.filter((p) =>
        ['failed', 'overdue', 'never_run', 'not_reported', 'unknown'].includes(p.cronSummaryStatus),
      ).length,
    },
  }
})
