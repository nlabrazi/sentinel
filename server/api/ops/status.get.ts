import { count, eq, sql } from 'drizzle-orm'
import { getDb } from '#server/db'
import { cronJobs, deployments, githubPullRequests, projects } from '#server/db/schema'
import { isDevBypassActive } from '#server/services/auth'
import { sentinelScheduler } from '#server/services/scheduler'
import { getEnv, getEnvStatusReport } from '#server/utils/env'

export default defineEventHandler(async () => {
  const env = getEnv()
  const db = getDb()

  let databaseConnected = false
  let projectsCount = 0
  let deploymentsCount = 0
  let cronJobsCount = 0
  let openPrsCount = 0

  try {
    await db.execute(sql`SELECT 1`)
    databaseConnected = true

    const [pCount, dCount, cCount, prCount] = await Promise.all([
      db.select({ value: count() }).from(projects),
      db.select({ value: count() }).from(deployments),
      db.select({ value: count() }).from(cronJobs),
      db
        .select({ value: count() })
        .from(githubPullRequests)
        .where(eq(githubPullRequests.state, 'open')),
    ])

    projectsCount = pCount[0]?.value ?? 0
    deploymentsCount = dCount[0]?.value ?? 0
    cronJobsCount = cCount[0]?.value ?? 0
    openPrsCount = prCount[0]?.value ?? 0
  } catch {
    databaseConnected = false
  }

  return {
    runtime: {
      nodeVersion: process.version,
      nodeEnv: env.nodeEnv,
      uptimeSeconds: Math.floor(process.uptime()),
      authMode: isDevBypassActive(env) ? 'dev-bypass' : 'authentik-oidc',
      vpsHost: env.vps.host || null,
      vpsAppsRoot: env.vps.appsRoot,
      databaseConnected,
      counts: {
        projects: projectsCount,
        deployments: deploymentsCount,
        cronJobs: cronJobsCount,
        openPrs: openPrsCount,
      },
    },
    envStatus: getEnvStatusReport(),
    schedulerTasks: sentinelScheduler.getStatuses(),
  }
})
