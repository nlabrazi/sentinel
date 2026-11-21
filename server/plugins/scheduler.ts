import { getDb } from '#server/db'
import { syncAllProjectsCronStatus } from '#server/services/cron-sync'
import { syncAllProjectsGithub } from '#server/services/github'
import { sentinelScheduler } from '#server/services/scheduler'
import { isUmamiConfigured, syncAllProjectsUmami } from '#server/services/umami'
import { discoverVpsProjects } from '#server/services/vps-discovery'
import { getEnv } from '#server/utils/env'

export default defineNitroPlugin((nitroApp) => {
  const env = getEnv()
  if (env.isTest) {
    return
  }

  sentinelScheduler.register('sync-github', '*/5 * * * *', async () => {
    if (!getEnv().githubToken) {
      return
    }
    await syncAllProjectsGithub(getDb())
  })

  sentinelScheduler.register('sync-cron', '*/5 * * * *', async () => {
    if (!getEnv().vps.host) {
      return
    }
    await syncAllProjectsCronStatus(getDb())
  })

  sentinelScheduler.register('scan-vps', '*/30 * * * *', async () => {
    if (!getEnv().vps.host) {
      return
    }
    await discoverVpsProjects(getDb())
  })

  sentinelScheduler.register('sync-umami', '*/15 * * * *', async () => {
    if (!isUmamiConfigured()) {
      return
    }
    await syncAllProjectsUmami(getDb())
  })

  nitroApp.hooks.hook('close', () => {
    sentinelScheduler.stopAll()
  })
})
