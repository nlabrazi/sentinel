import { asc, desc, eq, inArray } from 'drizzle-orm'
import { getDb } from '#server/db'
import { cronJobs, deployments, githubPullRequests, jobExecutions } from '#server/db/schema'
import {
  findProjectBySlugOrThrow,
  serializeCronJob,
  serializeDeployment,
  serializeProjectSummary,
  serializePullRequest,
} from '#server/utils/project-serializer'
import type { ProjectDetailDto } from '#shared/types/api'

export default defineEventHandler(async (event): Promise<ProjectDetailDto> => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)

  const [deploymentRows, cronJobRows, prRows] = await Promise.all([
    db
      .select()
      .from(deployments)
      .where(eq(deployments.projectId, project.id))
      .orderBy(desc(deployments.createdAt))
      .limit(20),
    db
      .select()
      .from(cronJobs)
      .where(eq(cronJobs.projectId, project.id))
      .orderBy(asc(cronJobs.name)),
    db
      .select()
      .from(githubPullRequests)
      .where(eq(githubPullRequests.projectId, project.id))
      .orderBy(desc(githubPullRequests.githubUpdatedAt))
      .limit(30),
  ])

  const cronJobIds = cronJobRows.map((job) => job.id)
  const executionRows =
    cronJobIds.length > 0
      ? await db
          .select()
          .from(jobExecutions)
          .where(inArray(jobExecutions.cronJobId, cronJobIds))
          .orderBy(desc(jobExecutions.executedAt))
          .limit(100)
      : []

  const executionsByJob = new Map<number, typeof executionRows>()
  for (const execution of executionRows) {
    const list = executionsByJob.get(execution.cronJobId) ?? []
    if (list.length < 15) {
      list.push(execution)
      executionsByJob.set(execution.cronJobId, list)
    }
  }

  const serializedDeployments = deploymentRows.map((row) =>
    serializeDeployment(row, { slug: project.slug, name: project.name }),
  )
  const runningDeployment = serializedDeployments.find((item) => item.status === 'running') ?? null

  const serializedPullRequests = prRows.map((row) =>
    serializePullRequest(row, { slug: project.slug, name: project.name }),
  )

  const serializedCrons = cronJobRows.map((job) =>
    serializeCronJob(job, executionsByJob.get(job.id) ?? []),
  )

  const openPrs = serializedPullRequests.filter((pr) => pr.state === 'open')

  const summary = serializeProjectSummary(project, {
    openPrsCount: openPrs.length,
    openRenovatePrsCount: openPrs.filter((pr) => pr.isRenovate).length,
    hasRunningDeployment: Boolean(runningDeployment),
  })

  return {
    ...summary,
    deployments: serializedDeployments,
    runningDeployment,
    cronJobs: serializedCrons,
    pullRequests: serializedPullRequests,
    grafanaEmbedUrl: null,
    grafanaDirectUrl: null,
  }
})
