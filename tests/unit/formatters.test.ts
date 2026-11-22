import { describe, expect, it } from 'vitest'
import { formatDuration, formatRelativeTime, shortSha } from '~/utils/formatters'

describe('UI formatting helpers', () => {
  it('truncates commit SHAs and handles missing values', () => {
    expect(shortSha('1234567890abcdef')).toBe('1234567')
    expect(shortSha(null)).toBe('—')
  })

  it('formats durations cleanly in seconds and minutes', () => {
    expect(formatDuration(0)).toBe('0s')
    expect(formatDuration(45)).toBe('45s')
    expect(formatDuration(120)).toBe('2m')
    expect(formatDuration(135)).toBe('2m 15s')
    expect(formatDuration(null)).toBe('—')
  })

  it('formats relative timestamps in French', () => {
    const now = new Date('2026-11-21T12:00:00Z')
    expect(formatRelativeTime(null, now)).toBe('Jamais')
    expect(formatRelativeTime('2026-11-21T11:59:30Z', now)).toBe("à l'instant")
    expect(formatRelativeTime('2026-11-21T11:45:00Z', now)).toBe('il y a 15 min')
    expect(formatRelativeTime('2026-11-21T09:00:00Z', now)).toBe('il y a 3 h')
    expect(formatRelativeTime('2026-11-19T12:00:00Z', now)).toBe('il y a 2 j')
  })
})
