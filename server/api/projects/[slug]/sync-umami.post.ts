import { getDb } from '#server/db'
import { syncProjectUmami } from '#server/services/umami'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  return await syncProjectUmami(db, project)
})
