import { expect, test } from '@playwright/test'

test.describe('Sentinel v2 core user journeys', () => {
  test('renders Cockpit dashboard with KPIs, filters and VPS scan action', async ({ page }) => {
    await page.goto('/')

    await expect(page.getByRole('heading', { name: 'Cockpit VPS' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Scanner le VPS' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Sync GitHub' })).toBeVisible()
    await expect(page.getByPlaceholder(/Rechercher un projet/i)).toBeVisible()

    // Kind filter buttons
    await page.getByRole('button', { name: 'Apps' }).click()
    await page.getByRole('button', { name: 'Crons' }).click()
    await page.getByRole('button', { name: 'Tous' }).click()
  })

  test('navigates between Cockpit, Deployments Hub and Ops Control Center', async ({ page }) => {
    await page.goto('/')

    await page.getByRole('link', { name: 'Déploiements' }).click()
    await expect(page).toHaveURL(/\/deploys/)
    await expect(page.getByRole('heading', { name: 'Hub Déploiements' })).toBeVisible()
    await expect(page.getByText('Taux de succès')).toBeVisible()

    await page.getByRole('link', { name: 'Ops Center' }).click()
    await expect(page).toHaveURL(/\/settings/)
    await expect(page.getByRole('heading', { name: 'Ops Control Center' })).toBeVisible()
    await expect(page.getByText('PostgreSQL OK')).toBeVisible()
    await expect(page.getByRole('heading', { name: "Variables d'environnement" })).toBeVisible()
  })

  test('protects Prometheus /metrics with Bearer token and returns 0.0.4 text format', async ({
    request,
  }) => {
    const unauthorized = await request.get('/metrics')
    expect(unauthorized.status()).toBe(401)
    expect(unauthorized.headers()['www-authenticate']).toContain('Bearer')

    const token = process.env.PROMETHEUS_METRICS_TOKEN || 'e2e-metrics-token'
    const authorized = await request.get('/metrics', {
      headers: { Authorization: `Bearer ${token}` },
    })
    expect(authorized.status()).toBe(200)
    expect(authorized.headers()['content-type']).toContain('text/plain')
    const body = await authorized.text()
    expect(body).toContain('# TYPE sentinel_cron_job_healthy gauge')
    expect(body).toContain('# TYPE sentinel_cron_project_healthy gauge')
  })

  test('exposes typed JSON for /api/auth/me and /api/projects', async ({ request }) => {
    const meRes = await request.get('/api/auth/me')
    expect(meRes.status()).toBe(200)
    const me = (await meRes.json()) as { user: { username: string }; authMode: string }
    expect(me.user.username).toBe('admin')

    const projectsRes = await request.get('/api/projects')
    expect(projectsRes.status()).toBe(200)
    const payload = (await projectsRes.json()) as {
      projects: unknown[]
      openPullRequests: unknown[]
      kpis: { totalProjects: number }
    }
    expect(Array.isArray(payload.projects)).toBe(true)
    expect(Array.isArray(payload.openPullRequests)).toBe(true)
    expect(typeof payload.kpis.totalProjects).toBe('number')
  })
})
