import { getDb } from '#server/db'
import { syncAllProjectsCronStatus } from '#server/services/cron-sync'

export default defineEventHandler(async () => {
  return await syncAllProjectsCronStatus(getDb())
})
