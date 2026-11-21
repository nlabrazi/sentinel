import { z } from 'zod'
import { getDb } from '#server/db'
import { toggleProjectMaintenance } from '#server/services/maintenance'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

const maintenanceBodySchema = z.object({
  enabled: z.boolean().optional(),
})

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const rawBody = await readBody(event).catch(() => ({}))
  const parsed = maintenanceBodySchema.safeParse(rawBody ?? {})
  if (!parsed.success) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid maintenance payload' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  const targetMode = parsed.data.enabled ?? !project.maintenanceMode

  try {
    return await toggleProjectMaintenance(db, project, targetMode)
  } catch (error) {
    throw createError({
      statusCode: 502,
      statusMessage: 'SSH Maintenance Error',
      message: error instanceof Error ? error.message : 'Unable to toggle maintenance flag',
    })
  }
})
