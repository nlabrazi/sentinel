import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { type ProjectRow, projectScreenshots, projects } from '#server/db/schema'
import { getEnv } from '#server/utils/env'
import { isValidHttpUrl } from '#shared/schemas/project'

export const MAX_SCREENSHOT_BYTES = 5 * 1024 * 1024

export interface ScreenshotCaptureOptions {
  accessKey?: string
  fetchImpl?: typeof fetch
  width?: number
  height?: number
}

export function buildApiFlashUrl(
  productionUrl: string,
  accessKey: string,
  options: { width?: number; height?: number } = {},
): string | null {
  if (!accessKey.trim() || !isValidHttpUrl(productionUrl)) {
    return null
  }
  const url = new URL('https://api.apiflash.com/v1/urltoimage')
  url.searchParams.set('access_key', accessKey.trim())
  url.searchParams.set('url', productionUrl)
  url.searchParams.set('width', String(options.width ?? 1280))
  url.searchParams.set('height', String(options.height ?? 720))
  url.searchParams.set('format', 'jpeg')
  url.searchParams.set('quality', '80')
  url.searchParams.set('fresh', 'true')
  url.searchParams.set('wait_until', 'page_loaded')
  url.searchParams.set('delay', '2')
  return url.toString()
}

export async function captureProjectScreenshot(
  db: SentinelDb,
  project: Pick<ProjectRow, 'id' | 'slug' | 'productionUrl'>,
  options: ScreenshotCaptureOptions = {},
): Promise<{ success: boolean; screenshotUrl: string | null; message: string }> {
  const accessKey = options.accessKey ?? getEnv().apiflashAccessKey
  if (!accessKey) {
    return { success: false, screenshotUrl: null, message: 'APIFLASH_ACCESS_KEY is not configured' }
  }
  if (!project.productionUrl) {
    return { success: false, screenshotUrl: null, message: 'Project has no production URL' }
  }

  const requestUrl = buildApiFlashUrl(project.productionUrl, accessKey, {
    width: options.width,
    height: options.height,
  })
  if (!requestUrl) {
    return { success: false, screenshotUrl: null, message: 'Invalid production URL for screenshot' }
  }

  const fetchImpl = options.fetchImpl ?? fetch
  const response = await fetchImpl(requestUrl, {
    signal: AbortSignal.timeout(25_000),
  })

  if (!response.ok) {
    return {
      success: false,
      screenshotUrl: null,
      message: `ApiFlash returned HTTP ${response.status}`,
    }
  }

  const contentType = response.headers.get('content-type')?.split(';')[0]?.trim() || 'image/jpeg'
  if (!contentType.startsWith('image/')) {
    return {
      success: false,
      screenshotUrl: null,
      message: `Unexpected screenshot content-type: ${contentType}`,
    }
  }

  const arrayBuffer = await response.arrayBuffer()
  const buffer = Buffer.from(arrayBuffer)
  if (buffer.byteLength === 0 || buffer.byteLength > MAX_SCREENSHOT_BYTES) {
    return {
      success: false,
      screenshotUrl: null,
      message: `Invalid screenshot size (${buffer.byteLength} bytes)`,
    }
  }

  const now = new Date()
  const dataBase64 = buffer.toString('base64')

  await db
    .insert(projectScreenshots)
    .values({
      projectId: project.id,
      contentType,
      dataBase64,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: projectScreenshots.projectId,
      set: {
        contentType,
        dataBase64,
        updatedAt: now,
      },
    })

  await db
    .update(projects)
    .set({
      screenshotUpdatedAt: now,
      updatedAt: now,
    })
    .where(eq(projects.id, project.id))

  const screenshotUrl = `/api/projects/${encodeURIComponent(project.slug)}/screenshot?v=${Math.floor(now.getTime() / 1000)}`
  return {
    success: true,
    screenshotUrl,
    message: 'Screenshot updated',
  }
}

export async function captureAllProjectsScreenshots(
  db: SentinelDb,
  options: ScreenshotCaptureOptions & { force?: boolean } = {},
): Promise<{ capturedCount: number; skippedCount: number; failedSlugs: string[] }> {
  const allProjects = await db.select().from(projects)
  let capturedCount = 0
  let skippedCount = 0
  const failedSlugs: string[] = []

  for (const project of allProjects) {
    if (!project.productionUrl) {
      skippedCount += 1
      continue
    }
    if (!options.force && project.screenshotUpdatedAt) {
      skippedCount += 1
      continue
    }

    try {
      const result = await captureProjectScreenshot(db, project, options)
      if (result.success) {
        capturedCount += 1
      } else {
        failedSlugs.push(project.slug)
      }
    } catch (error) {
      console.error(`[sentinel:screenshot] Failed for ${project.slug}:`, error)
      failedSlugs.push(project.slug)
    }
  }

  return { capturedCount, skippedCount, failedSlugs }
}
