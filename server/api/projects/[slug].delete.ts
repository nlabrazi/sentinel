import { eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { projects } from '#server/db/schema'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const existing = await findProjectBySlugOrThrow(db, slug)
  await db.delete(projects).where(eq(projects.id, existing.id))

  return { deleted: true, slug: existing.slug }
})
