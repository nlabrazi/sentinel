import { existsSync } from 'node:fs'
import path from 'node:path'
import { closeDb, getDb, runMigrations } from '#server/db'
import { reconcileInterruptedDeployments } from '#server/services/deploy'
import { getEnv } from '#server/utils/env'

export default defineNitroPlugin(async (nitroApp) => {
  const env = getEnv()
  const migrationsDir = path.resolve(process.cwd(), 'server/db/migrations')

  if (!env.isTest && existsSync(path.join(migrationsDir, 'meta', '_journal.json'))) {
    try {
      await runMigrations(migrationsDir)
      console.info('[sentinel:db] PostgreSQL migrations up to date')
      void reconcileInterruptedDeployments(getDb()).catch((error) => {
        console.error('[sentinel:deploy] Failed to reconcile interrupted deployments:', error)
      })
    } catch (error) {
      console.error('[sentinel:db] Failed to run PostgreSQL migrations on startup:', error)
    }
  }

  nitroApp.hooks.hook('close', async () => {
    await closeDb()
  })
})
