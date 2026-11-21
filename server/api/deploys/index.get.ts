import { desc } from 'drizzle-orm'
import { getDb } from '#server/db'
import { deployments, projects } from '#server/db/schema'
import { serializeDeployment } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const projectFilter = typeof query.project === 'string' ? query.project.trim() : ''
  const statusFilter = typeof query.status === 'string' ? query.status.trim() : ''
  const search = typeof query.q === 'string' ? query.q.trim().toLowerCase() : ''

  const db = getDb()
  const [allDeployments, allProjects] = await Promise.all([
    db.select().from(deployments).orderBy(desc(deployments.createdAt)).limit(200),
    db.select().from(projects),
  ])

  const projectById = new Map(allProjects.map((p) => [p.id, p]))
  const serializedAll = allDeployments.map((row) => {
    const owner = projectById.get(row.projectId)
    return serializeDeployment(row, owner ? { slug: owner.slug, name: owner.name } : undefined)
  })

  const filtered = serializedAll.filter((item) => {
    if (projectFilter && item.projectSlug !== projectFilter) {
      return false
    }
    if (statusFilter && item.status !== statusFilter) {
      return false
    }
    if (search) {
      const hay =
        `${item.projectName ?? ''} ${item.projectSlug ?? ''} ${item.commitSha ?? ''}`.toLowerCase()
      return hay.includes(search)
    }
    return true
  })

  const finished = serializedAll.filter((d) => d.status !== 'running')
  const succeeded = finished.filter((d) => d.status === 'success')
  const failed = finished.filter((d) => d.status === 'failed')
  const durations = finished
    .map((d) => d.durationSeconds)
    .filter((v): v is number => typeof v === 'number')

  return {
    deployments: filtered,
    runningDeployments: serializedAll.filter((d) => d.status === 'running'),
    projects: allProjects.map((p) => ({ slug: p.slug, name: p.name })),
    kpis: {
      total: serializedAll.length,
      successRate: finished.length > 0 ? Math.round((succeeded.length / finished.length) * 100) : 0,
      failed: failed.length,
      avgDurationSeconds:
        durations.length > 0
          ? Math.round(durations.reduce((sum, val) => sum + val, 0) / durations.length)
          : 0,
    },
  }
})
