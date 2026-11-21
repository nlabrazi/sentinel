import { getDb } from '#server/db'
import { syncProjectCronStatus } from '#server/services/cron-sync'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  const result = await syncProjectCronStatus(db, project)

  if (!result.synced) {
    throw createError({
      statusCode: 502,
      statusMessage: 'Cron Sync Failed',
      message: result.error || 'Unable to fetch cron status via SSH',
    })
  }

  return result
})
