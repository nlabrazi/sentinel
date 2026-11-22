import { eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { projectScreenshots } from '#server/db/schema'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  const [row] = await db
    .select()
    .from(projectScreenshots)
    .where(eq(projectScreenshots.projectId, project.id))
    .limit(1)

  if (!row) {
    throw createError({ statusCode: 404, statusMessage: 'Screenshot not found' })
  }

  setHeader(event, 'Content-Type', row.contentType)
  setHeader(event, 'Cache-Control', 'private, max-age=3600')
  return Buffer.from(row.dataBase64, 'base64')
})
