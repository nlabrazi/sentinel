import { getDb } from '#server/db'
import { syncAllProjectsGithub } from '#server/services/github'
import { sentinelScheduler } from '#server/services/scheduler'
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

  sentinelScheduler.register('scan-vps', '*/30 * * * *', async () => {
    if (!getEnv().vps.host) {
      return
    }
    await discoverVpsProjects(getDb())
  })

  nitroApp.hooks.hook('close', () => {
    sentinelScheduler.stopAll()
  })
})
