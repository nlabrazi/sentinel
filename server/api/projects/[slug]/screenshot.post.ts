import { getDb } from '#server/db'
import { captureProjectScreenshot } from '#server/services/screenshot'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  const result = await captureProjectScreenshot(db, project)

  if (!result.success) {
    throw createError({
      statusCode: 502,
      statusMessage: 'Screenshot Capture Failed',
      message: result.message,
    })
  }

  return result
})
