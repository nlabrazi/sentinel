import { getDb } from '#server/db'
import { syncAllProjectsUmami } from '#server/services/umami'

export default defineEventHandler(async () => {
  return await syncAllProjectsUmami(getDb())
})
