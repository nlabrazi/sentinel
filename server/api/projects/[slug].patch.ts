import { eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { projects } from '#server/db/schema'
import { findProjectBySlugOrThrow, serializeProjectSummary } from '#server/utils/project-serializer'
import { normalizeGithubRepoUrl, projectUpdateSchema } from '#shared/schemas/project'

export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug')
  if (!slug) {
    throw createError({ statusCode: 400, statusMessage: 'Project slug is required' })
  }

  const body = await readBody(event)
  const parsed = projectUpdateSchema.safeParse(body)
  if (!parsed.success) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Invalid project payload',
      data: parsed.error.flatten(),
    })
  }

  const db = getDb()
  const existing = await findProjectBySlugOrThrow(db, slug)
  const data = parsed.data

  const [updated] = await db
    .update(projects)
    .set({
      ...(data.name !== undefined ? { name: data.name } : {}),
      ...(data.kind !== undefined ? { kind: data.kind } : {}),
      ...(data.repoUrl !== undefined
        ? { repoUrl: data.repoUrl ? normalizeGithubRepoUrl(data.repoUrl) : null }
        : {}),
      ...(data.productionBranch !== undefined ? { productionBranch: data.productionBranch } : {}),
      ...(data.stagingBranch !== undefined ? { stagingBranch: data.stagingBranch } : {}),
      ...(data.productionUrl !== undefined ? { productionUrl: data.productionUrl } : {}),
      ...(data.grafanaAppValue !== undefined ? { grafanaAppValue: data.grafanaAppValue } : {}),
      ...(data.umamiWebsiteId !== undefined ? { umamiWebsiteId: data.umamiWebsiteId } : {}),
      ...(data.cronMonitoringEnabled !== undefined
        ? { cronMonitoringEnabled: data.cronMonitoringEnabled }
        : {}),
      updatedAt: new Date(),
    })
    .where(eq(projects.id, existing.id))
    .returning()

  if (!updated) {
    throw createError({ statusCode: 500, statusMessage: 'Failed to update project' })
  }

  return serializeProjectSummary(updated)
})
