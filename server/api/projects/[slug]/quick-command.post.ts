import { z } from 'zod'
import { getDb } from '#server/db'
import { executeQuickCommand } from '#server/services/quick-command'
import { findProjectBySlugOrThrow } from '#server/utils/project-serializer'

const quickCommandSchema = z.object({
  command: z.string().min(1).max(500),
})

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const body = await readBody(event)
  const parsed = quickCommandSchema.safeParse(body)
  if (!parsed.success) {
    throw createError({ statusCode: 400, statusMessage: 'Command is required' })
  }

  const db = getDb()
  const project = await findProjectBySlugOrThrow(db, slug)
  return await executeQuickCommand(project, parsed.data.command)
})
