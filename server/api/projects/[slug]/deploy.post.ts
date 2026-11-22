import { getDb } from '#server/db'
import { DeploymentAlreadyRunningError, startProjectDeployment } from '#server/services/deploy'
import { findProjectBySlugOrThrow, serializeDeployment } from '#server/utils/project-serializer'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  const triggeredBy = event.context.user?.username || 'web'

  try {
    const deployment = await startProjectDeployment(db, project, triggeredBy)
    setResponseStatus(event, 202)
    return serializeDeployment(deployment, { slug: project.slug, name: project.name })
  } catch (error) {
    if (error instanceof DeploymentAlreadyRunningError) {
      throw createError({
        statusCode: 409,
        statusMessage: 'Conflict',
        message: error.message,
      })
    }
    throw error
  }
})
