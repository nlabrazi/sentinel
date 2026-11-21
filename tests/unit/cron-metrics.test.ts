import { describe, expect, it } from 'vitest'
import {
  evaluateCronJobStatus,
  isCronJobOverdue,
  isProjectCronSyncStale,
  renderPrometheusCronMetrics,
  verifyMetricsBearerToken,
} from '#server/services/cron-metrics'
import { normalizeCronStatus, parseCronStatusPayload } from '#server/services/cron-sync'

describe('cron status parser', () => {
  it('normalizes status aliases and parses v1 jobs, deprecated cron_jobs and legacy maps', () => {
    expect(normalizeCronStatus('ok')).toBe('success')
    expect(normalizeCronStatus('PASSED')).toBe('success')
    expect(normalizeCronStatus('error')).toBe('failed')
    expect(normalizeCronStatus('pending')).toBe('unknown')

    const v1 = parseCronStatusPayload({
      version: 1,
      jobs: [
        {
          name: 'daily-scan',
          command: 'npm run scan',
          schedule: '0 2 * * *',
          last_execution_at: '2026-11-21T02:00:05Z',
          last_status: 'ok',
          last_duration: 0,
          last_log: 'All good',
        },
      ],
    })
    expect(v1).toHaveLength(1)
    expect(v1[0]).toMatchObject({
      name: 'daily-scan',
      lastStatus: 'success',
      lastDuration: 0,
    })

    const deprecated = parseCronStatusPayload({
      cron_jobs: [{ name: 'backup', status: 'error', last_run: '2026-11-21T01:00:00Z' }],
    })
    expect(deprecated[0]).toMatchObject({ name: 'backup', lastStatus: 'failed' })

    const legacy = parseCronStatusPayload({
      version: 1,
      cleanup: { schedule: '0 * * * *', status: 'success' },
    })
    expect(legacy[0]).toMatchObject({ name: 'cleanup', lastStatus: 'success' })
  })
})

describe('cron overdue evaluation & Prometheus metrics export', () => {
  it('detects overdue jobs respecting UTC schedules and grace period', () => {
    // Hourly job at minute 0
    const job = {
      schedule: '0 * * * *',
      lastStatus: 'success' as const,
      lastExecutionAt: new Date('2026-11-21T10:00:00Z'),
    }

    // 11:14 UTC -> within 15m grace period of 11:00 occurrence -> NOT overdue
    expect(
      isCronJobOverdue(job, {
        at: new Date('2026-11-21T11:14:00Z'),
        overdueGraceMinutes: 15,
      }),
    ).toBe(false)

    // 11:15 UTC -> cutoff hits 11:00:00 -> OVERDUE
    expect(
      isCronJobOverdue(job, {
        at: new Date('2026-11-21T11:15:00Z'),
        overdueGraceMinutes: 15,
      }),
    ).toBe(true)

    // Failed takes priority over overdue
    expect(
      evaluateCronJobStatus(
        { ...job, lastStatus: 'failed' },
        { at: new Date('2026-11-21T11:30:00Z'), overdueGraceMinutes: 15 },
      ),
    ).toBe('failed')

    // Invalid schedule returns unknown and does not throw
    expect(
      evaluateCronJobStatus(
        {
          schedule: 'not a cron',
          lastStatus: 'success',
          lastExecutionAt: new Date('2026-11-21T10:00:00Z'),
        },
        { at: new Date('2026-11-21T11:30:00Z') },
      ),
    ).toBe('unknown')
  })

  it('detects stale syncs and renders exact Prometheus 0.0.4 metrics', () => {
    const at = new Date('2026-11-21T12:00:00Z')
    expect(
      isProjectCronSyncStale(
        { cronMonitoringEnabled: true, cronSyncedAt: new Date('2026-11-21T11:45:00Z') },
        { at, syncStaleAfterMinutes: 15 },
      ),
    ).toBe(true)

    const output = renderPrometheusCronMetrics(
      [
        {
          project: {
            slug: 'sjvtdm',
            cronMonitoringEnabled: true,
            cronSyncedAt: new Date('2026-11-21T11:55:00Z'),
          },
          jobs: [
            {
              name: 'daily-import',
              schedule: '0 2 * * *',
              lastStatus: 'success',
              lastDuration: 0,
              lastExecutionAt: new Date('2026-11-21T02:00:12Z'),
            },
          ],
        },
        {
          project: {
            slug: 'disabled-app',
            cronMonitoringEnabled: false,
            cronSyncedAt: null,
          },
          jobs: [],
        },
      ],
      { at, overdueGraceMinutes: 15, syncStaleAfterMinutes: 15 },
    )

    expect(output).toContain('# TYPE sentinel_cron_job_healthy gauge')
    expect(output).toContain('sentinel_cron_job_healthy{project="sjvtdm",job="daily-import"} 1')
    expect(output).toContain('sentinel_cron_job_failed{project="sjvtdm",job="daily-import"} 0')
    expect(output).toContain('sentinel_cron_job_overdue{project="sjvtdm",job="daily-import"} 0')
    expect(output).toContain(
      'sentinel_cron_job_last_duration_seconds{project="sjvtdm",job="daily-import"} 0',
    )
    expect(output).toContain('sentinel_cron_project_sync_stale{project="sjvtdm"} 0')
    expect(output).toContain('sentinel_cron_project_healthy{project="sjvtdm"} 1')
    expect(output).not.toContain('disabled-app')
  })

  it('verifies Bearer token using timing-safe comparison', () => {
    expect(verifyMetricsBearerToken('Bearer secret-token', 'secret-token')).toBe(true)
    expect(verifyMetricsBearerToken('Bearer wrong-token', 'secret-token')).toBe(false)
    expect(verifyMetricsBearerToken('Basic secret-token', 'secret-token')).toBe(false)
    expect(verifyMetricsBearerToken('Bearer secret-token', '')).toBe(false)
  })
})
