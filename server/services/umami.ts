import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { type ProjectRow, projects } from '#server/db/schema'
import { getEnv, type SentinelEnv } from '#server/utils/env'

export interface UmamiWebsite {
  id: string
  name?: string
  domain: string
}

export interface UmamiStats {
  visitors: number
  pageviews: number
  visits: number
  bounces: number
  bounceRate: number
}

export interface UmamiClientOptions {
  env?: SentinelEnv['umami']
  fetchImpl?: typeof fetch
}

const tokenCache = new Map<string, { token: string; expiresAt: number }>()

export function clearUmamiTokenCache(): void {
  tokenCache.clear()
}

export function extractDomainHost(urlOrDomain: string | null | undefined): string {
  const trimmed = (urlOrDomain ?? '').trim()
  if (!trimmed) {
    return ''
  }
  const normalized = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
  try {
    return new URL(normalized).hostname.toLowerCase()
  } catch {
    return trimmed.toLowerCase()
  }
}

function extractMetricValue(metric: unknown): number {
  if (typeof metric === 'number' && Number.isFinite(metric)) {
    return Math.round(metric)
  }
  if (metric && typeof metric === 'object' && 'value' in metric) {
    const val = Number((metric as { value?: unknown }).value)
    return Number.isFinite(val) ? Math.round(val) : 0
  }
  return 0
}

export function parseUmamiStatsResponse(data: unknown): UmamiStats {
  if (!data || typeof data !== 'object') {
    return { visitors: 0, pageviews: 0, visits: 0, bounces: 0, bounceRate: 0 }
  }
  const record = data as Record<string, unknown>
  const pageviews = extractMetricValue(record.pageviews)
  const visitors = extractMetricValue(record.visitors)
  const visits = extractMetricValue(record.visits)
  const bounces = extractMetricValue(record.bounces)
  const bounceRate = visits > 0 ? Math.round((bounces / visits) * 100) : 0
  return { visitors, pageviews, visits, bounces, bounceRate }
}

export function isUmamiConfigured(cfg: SentinelEnv['umami'] = getEnv().umami): boolean {
  return Boolean(cfg.baseUrl && (cfg.authToken || cfg.apiKey || (cfg.username && cfg.password)))
}

async function resolveUmamiHeaders(
  cfg: SentinelEnv['umami'],
  fetchImpl: typeof fetch,
): Promise<Record<string, string> | null> {
  if (cfg.authToken) {
    return {
      Authorization: `Bearer ${cfg.authToken}`,
      Accept: 'application/json',
    }
  }
  if (cfg.apiKey) {
    return {
      'x-umami-api-key': cfg.apiKey,
      Accept: 'application/json',
    }
  }
  if (cfg.username && cfg.password) {
    const cached = tokenCache.get(cfg.baseUrl)
    if (cached && cached.expiresAt > Date.now()) {
      return {
        Authorization: `Bearer ${cached.token}`,
        Accept: 'application/json',
      }
    }

    const res = await fetchImpl(`${cfg.baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ username: cfg.username, password: cfg.password }),
      signal: AbortSignal.timeout(10_000),
    })
    if (!res.ok) {
      return null
    }
    const payload = (await res.json()) as { token?: string }
    if (!payload.token) {
      return null
    }
    tokenCache.set(cfg.baseUrl, {
      token: payload.token,
      expiresAt: Date.now() + 12 * 60 * 60 * 1000,
    })
    return {
      Authorization: `Bearer ${payload.token}`,
      Accept: 'application/json',
    }
  }

  return null
}

export async function fetchUmamiWebsites(
  options: UmamiClientOptions = {},
): Promise<UmamiWebsite[]> {
  const cfg = options.env ?? getEnv().umami
  const fetchImpl = options.fetchImpl ?? fetch
  const headers = await resolveUmamiHeaders(cfg, fetchImpl)
  if (!headers || !cfg.baseUrl) {
    return []
  }

  const response = await fetchImpl(`${cfg.baseUrl}/api/websites`, {
    headers,
    signal: AbortSignal.timeout(10_000),
  })
  if (!response.ok) {
    return []
  }

  const data = (await response.json()) as { data?: UmamiWebsite[] } | UmamiWebsite[]
  if (Array.isArray(data)) {
    return data
  }
  return Array.isArray(data?.data) ? data.data : []
}

export async function fetchUmamiStats24h(
  websiteId: string,
  options: UmamiClientOptions = {},
): Promise<{ stats?: UmamiStats; error?: string }> {
  const cfg = options.env ?? getEnv().umami
  const fetchImpl = options.fetchImpl ?? fetch
  const headers = await resolveUmamiHeaders(cfg, fetchImpl)
  if (!headers || !cfg.baseUrl) {
    return { error: 'Umami credentials are not configured' }
  }

  const endAt = Date.now()
  const startAt = endAt - 24 * 60 * 60 * 1000
  const url = `${cfg.baseUrl}/api/websites/${encodeURIComponent(websiteId)}/stats?startAt=${startAt}&endAt=${endAt}`

  const response = await fetchImpl(url, {
    headers,
    signal: AbortSignal.timeout(10_000),
  })
  if (!response.ok) {
    return { error: `HTTP ${response.status}` }
  }

  const payload = (await response.json()) as unknown
  return { stats: parseUmamiStatsResponse(payload) }
}

export async function syncProjectUmami(
  db: SentinelDb,
  project: ProjectRow,
  options: UmamiClientOptions = {},
): Promise<{ success: boolean; message: string }> {
  const cfg = options.env ?? getEnv().umami
  if (!isUmamiConfigured(cfg)) {
    return { success: false, message: 'Umami is not configured' }
  }

  let websiteId = project.umamiWebsiteId
  if (!websiteId && project.productionUrl) {
    const targetHost = extractDomainHost(project.productionUrl)
    const websites = await fetchUmamiWebsites(options)
    const match = websites.find((site) => extractDomainHost(site.domain) === targetHost)
    if (match?.id) {
      websiteId = match.id
    }
  }

  const now = new Date()
  if (!websiteId) {
    const message = 'No matching Umami website found'
    await db
      .update(projects)
      .set({ umamiSyncError: message, umamiSyncedAt: now, updatedAt: now })
      .where(eq(projects.id, project.id))
    return { success: false, message }
  }

  const result = await fetchUmamiStats24h(websiteId, options)
  if (result.error || !result.stats) {
    const message = result.error || 'Unable to load Umami stats'
    await db
      .update(projects)
      .set({
        umamiWebsiteId: websiteId,
        umamiSyncError: message,
        umamiSyncedAt: now,
        updatedAt: now,
      })
      .where(eq(projects.id, project.id))
    return { success: false, message }
  }

  await db
    .update(projects)
    .set({
      umamiWebsiteId: websiteId,
      umamiVisitors24h: result.stats.visitors,
      umamiPageviews24h: result.stats.pageviews,
      umamiBounceRate: result.stats.bounceRate,
      umamiSyncError: null,
      umamiSyncedAt: now,
      updatedAt: now,
    })
    .where(eq(projects.id, project.id))

  return { success: true, message: 'Umami metrics synced' }
}

export async function syncAllProjectsUmami(
  db: SentinelDb,
  options: UmamiClientOptions = {},
): Promise<{ syncedCount: number; failedSlugs: string[] }> {
  const allProjects = await db.select().from(projects)
  let syncedCount = 0
  const failedSlugs: string[] = []

  for (const project of allProjects) {
    if (!project.umamiWebsiteId && !project.productionUrl) {
      continue
    }
    const res = await syncProjectUmami(db, project, options)
    if (res.success) {
      syncedCount += 1
    } else {
      failedSlugs.push(project.slug)
    }
  }

  return { syncedCount, failedSlugs }
}
