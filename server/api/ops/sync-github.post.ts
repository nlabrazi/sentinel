import { getDb } from '#server/db'
import { syncAllProjectsGithub } from '#server/services/github'

export default defineEventHandler(async () => {
  return await syncAllProjectsGithub(getDb())
})
