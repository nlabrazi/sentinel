import { afterEach, describe, expect, it, vi } from 'vitest'
import { SentinelScheduler } from '#server/services/scheduler'

describe('SentinelScheduler', () => {
  const scheduler = new SentinelScheduler()

  afterEach(() => {
    scheduler.stopAll()
  })

  it('registers tasks, tracks heartbeats on success and captures failures cleanly', async () => {
    const okHandler = vi.fn(async () => {})
    const failHandler = vi.fn(async () => {
      throw new Error('upstream timeout')
    })

    scheduler.register('sync-github', '*/5 * * * *', okHandler)
    scheduler.register('sync-failing', '*/10 * * * *', failHandler)

    expect(await scheduler.triggerNow('sync-github')).toBe(true)
    expect(await scheduler.triggerNow('sync-failing')).toBe(true)
    expect(await scheduler.triggerNow('unknown')).toBe(false)

    const statuses = scheduler.getStatuses()
    const okStatus = statuses.find((t) => t.name === 'sync-github')
    const failStatus = statuses.find((t) => t.name === 'sync-failing')

    expect(okStatus).toMatchObject({
      name: 'sync-github',
      schedule: '*/5 * * * *',
      running: false,
      lastError: null,
      runCount: 1,
    })
    expect(okStatus?.lastSuccessAt).not.toBeNull()
    expect(okStatus?.nextRunAt).not.toBeNull()

    expect(failStatus).toMatchObject({
      name: 'sync-failing',
      running: false,
      lastError: 'upstream timeout',
      runCount: 1,
    })
    expect(failStatus?.lastSuccessAt).toBeNull()
  })
})
