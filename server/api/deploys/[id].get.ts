import { eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { deployments, projects } from '#server/db/schema'
import { serializeDeployment } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const id = Number.parseInt(getRouterParam(event, 'id') ?? '', 10)
  if (!Number.isFinite(id) || id <= 0) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid deployment id' })
  }

  const db = getDb()
  const [row] = await db.select().from(deployments).where(eq(deployments.id, id)).limit(1)
  if (!row) {
    throw createError({ statusCode: 404, statusMessage: 'Deployment not found' })
  }

  const [project] = await db.select().from(projects).where(eq(projects.id, row.projectId)).limit(1)
  return serializeDeployment(row, project ? { slug: project.slug, name: project.name } : undefined)
})
