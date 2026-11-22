import { getDb } from '#server/db'
import { captureAllProjectsScreenshots } from '#server/services/screenshot'

export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const force = query.force === 'true' || query.force === '1'
  return await captureAllProjectsScreenshots(getDb(), { force })
})
