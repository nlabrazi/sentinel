import type { ProjectRow } from '#server/db/schema'
import { getEnv, type SentinelEnv } from '#server/utils/env'

const VARIABLE_NAME_PATTERN = /^[A-Za-z0-9_-]+$/

export interface GrafanaUrlOptions {
  project?: Pick<ProjectRow, 'grafanaAppValue'> | null
  panelId?: string | null
  kiosk?: boolean | string
  theme?: 'dark' | 'light'
  from?: string
  to?: string
  env?: SentinelEnv['grafana']
}

function parseSafeBaseUrl(rawUrl: string): URL | null {
  if (!rawUrl) {
    return null
  }
  try {
    const uri = new URL(rawUrl)
    if (uri.protocol !== 'http:' && uri.protocol !== 'https:') {
      return null
    }
    if (!uri.hostname || uri.username || uri.password || uri.search || uri.hash) {
      return null
    }
    return uri
  } catch {
    return null
  }
}

export function buildGrafanaUrl(options: GrafanaUrlOptions = {}): string | null {
  const cfg = options.env ?? getEnv().grafana
  const baseUri = parseSafeBaseUrl(cfg.baseUrl)
  if (!baseUri || !cfg.dashboardUid || !VARIABLE_NAME_PATTERN.test(cfg.variableName)) {
    return null
  }

  const variableValue = options.project
    ? (options.project.grafanaAppValue ?? '').trim()
    : cfg.globalVariableValue

  if (options.project && !variableValue) {
    return null
  }

  const resolvedPanelId =
    options.panelId === null ? '' : (options.panelId ?? cfg.panelId ?? '').trim()

  const baseSegments = baseUri.pathname.split('/').filter(Boolean)
  const routeSegments = [
    ...baseSegments,
    resolvedPanelId ? 'd-solo' : 'd',
    encodeURIComponent(cfg.dashboardUid),
    encodeURIComponent(cfg.dashboardSlug || 'applications-overview'),
  ]

  const result = new URL(baseUri.toString())
  result.pathname = `/${routeSegments.join('/')}`

  const params = new URLSearchParams()
  params.set('orgId', cfg.orgId || '1')
  params.set('from', options.from || cfg.defaultFrom || 'now-6h')
  params.set('to', options.to || cfg.defaultTo || 'now')
  params.set('timezone', cfg.defaultTimezone || 'browser')
  if (cfg.refresh) {
    params.set('refresh', cfg.refresh)
  }
  params.set('theme', options.theme || cfg.defaultTheme || 'dark')
  if (resolvedPanelId) {
    params.set('panelId', resolvedPanelId)
  }
  if (options.kiosk === true) {
    params.set('kiosk', '')
  } else if (typeof options.kiosk === 'string' && options.kiosk) {
    params.set('kiosk', options.kiosk)
  }
  if (variableValue) {
    params.set(`var-${cfg.variableName}`, variableValue)
  }

  result.search = params.toString()
  return result.toString()
}

export function buildGrafanaDirectDashboardUrl(
  options: Omit<GrafanaUrlOptions, 'panelId'> = {},
): string | null {
  return buildGrafanaUrl({ ...options, panelId: null })
}
