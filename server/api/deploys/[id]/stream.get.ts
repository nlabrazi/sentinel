import { eq } from 'drizzle-orm'
import { getDb } from '#server/db'
import { deployments } from '#server/db/schema'
import { deployLogBus } from '#server/services/deploy'

export default defineEventHandler(async (event) => {
  const id = Number.parseInt(getRouterParam(event, 'id') ?? '', 10)
  if (!Number.isFinite(id) || id <= 0) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid deployment id' })
  }

  const db = getDb()
  const [row] = await db.select().from(deployments).where(eq(deployments.id, id)).limit(1)
  if (!row) {
    throw createError({ statusCode: 404, statusMessage: 'Deployment not found' })
  }

  const eventStream = createEventStream(event)

  // If deployment is already finished, replay persisted log and close immediately
  if (row.status !== 'running' && !deployLogBus.isActive(id)) {
    void (async () => {
      if (row.log) {
        await eventStream.push({ event: 'chunk', data: JSON.stringify({ text: row.log }) })
      }
      await eventStream.push({
        event: 'done',
        data: JSON.stringify({
          status: row.status,
          durationSeconds: row.durationSeconds ?? 0,
        }),
      })
      await eventStream.close()
    })()
    return eventStream.send()
  }

  const existingBuffer = deployLogBus.getActiveBuffer(id)
  if (existingBuffer) {
    void eventStream.push({ event: 'chunk', data: JSON.stringify({ text: existingBuffer }) })
  }

  const unsubscribe = deployLogBus.subscribe(id, (msg) => {
    if (msg.type === 'chunk') {
      void eventStream.push({ event: 'chunk', data: JSON.stringify({ text: msg.data ?? '' }) })
      return
    }
    void (async () => {
      await eventStream.push({
        event: 'done',
        data: JSON.stringify({
          status: msg.status ?? 'failed',
          durationSeconds: msg.durationSeconds ?? 0,
        }),
      })
      unsubscribe()
      await eventStream.close()
    })()
  })

  eventStream.onClosed(() => {
    unsubscribe()
  })

  return eventStream.send()
})
