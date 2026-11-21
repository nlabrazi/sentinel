import { describe, expect, it } from 'vitest'
import { buildGrafanaDirectDashboardUrl, buildGrafanaUrl } from '#server/services/grafana'

const baseGrafanaEnv = {
  baseUrl: 'https://grafana.nabster.dev',
  dashboardUid: 'apps-uid',
  dashboardSlug: 'applications-overview',
  variableName: 'app',
  defaultTheme: 'dark' as const,
  orgId: '1',
  defaultFrom: 'now-6h',
  defaultTo: 'now',
  defaultTimezone: 'browser',
  refresh: '30s',
  panelId: 'panel-6',
  globalVariableValue: 'All',
}

describe('grafana embed URL builder', () => {
  it('builds project-scoped solo panel embed URL and direct full dashboard URL', () => {
    const embedUrl = buildGrafanaUrl({
      project: { grafanaAppValue: 'https://nabster.dev' },
      env: baseGrafanaEnv,
    })
    if (!embedUrl) {
      throw new Error('Expected embedUrl to be non-null')
    }
    const parsedEmbed = new URL(embedUrl)
    expect(parsedEmbed.pathname).toBe('/d-solo/apps-uid/applications-overview')
    expect(parsedEmbed.searchParams.get('panelId')).toBe('panel-6')
    expect(parsedEmbed.searchParams.get('var-app')).toBe('https://nabster.dev')
    expect(parsedEmbed.searchParams.get('theme')).toBe('dark')

    const directUrl = buildGrafanaDirectDashboardUrl({
      project: { grafanaAppValue: 'https://nabster.dev' },
      theme: 'light',
      env: baseGrafanaEnv,
    })
    if (!directUrl) {
      throw new Error('Expected directUrl to be non-null')
    }
    const parsedDirect = new URL(directUrl)
    expect(parsedDirect.pathname).toBe('/d/apps-uid/applications-overview')
    expect(parsedDirect.searchParams.get('panelId')).toBeNull()
    expect(parsedDirect.searchParams.get('theme')).toBe('light')
  })

  it('returns null when project value is missing or base URL contains credentials/query', () => {
    expect(buildGrafanaUrl({ project: { grafanaAppValue: null }, env: baseGrafanaEnv })).toBeNull()

    expect(
      buildGrafanaUrl({
        project: { grafanaAppValue: 'app' },
        env: { ...baseGrafanaEnv, baseUrl: 'https://user:pass@grafana.nabster.dev' },
      }),
    ).toBeNull()

    expect(
      buildGrafanaUrl({
        project: { grafanaAppValue: 'app' },
        env: { ...baseGrafanaEnv, variableName: 'bad var!' },
      }),
    ).toBeNull()
  })
})
