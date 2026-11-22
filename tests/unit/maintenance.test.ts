import { describe, expect, it } from 'vitest'
import { buildMaintenanceCommand } from '#server/services/maintenance'

describe('maintenance service', () => {
  it('builds safe touch and rm commands for maintenance.on and rejects traversal', () => {
    expect(buildMaintenanceCommand('/srv/apps/sentinel', true, '/srv/apps')).toContain('touch')
    expect(buildMaintenanceCommand('/srv/apps/sentinel', true, '/srv/apps')).toContain(
      '/srv/apps/sentinel/maintenance.on',
    )
    expect(buildMaintenanceCommand('/srv/apps/sentinel', false, '/srv/apps')).toContain('rm -f')
    expect(() => buildMaintenanceCommand('/srv/apps/../etc', true, '/srv/apps')).toThrow(
      /Unsafe VPS path/,
    )
  })
})
