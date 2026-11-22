import { describe, expect, it } from 'vitest'
import { DEPLOYMENT_STATUSES, PROJECT_KINDS } from '#shared/types/sentinel'

describe('sentinel shared types', () => {
  it('exposes the supported project kinds and deployment statuses', () => {
    expect(PROJECT_KINDS).toEqual(['app', 'service', 'cron'])
    expect(DEPLOYMENT_STATUSES).toEqual(['running', 'success', 'failed'])
  })
})
