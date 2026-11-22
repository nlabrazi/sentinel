import { describe, expect, it, vi } from 'vitest'
import type { SentinelDb } from '#server/db'
import { buildApiFlashUrl, captureProjectScreenshot } from '#server/services/screenshot'

describe('screenshot service (ApiFlash)', () => {
  it('builds a valid ApiFlash capture URL and rejects invalid URLs or missing keys', () => {
    const url = buildApiFlashUrl('https://argandici.com', 'api-key-123')
    expect(url).not.toBeNull()
    const parsed = new URL(url ?? '')
    expect(parsed.origin).toBe('https://api.apiflash.com')
    expect(parsed.searchParams.get('access_key')).toBe('api-key-123')
    expect(parsed.searchParams.get('url')).toBe('https://argandici.com')
    expect(parsed.searchParams.get('width')).toBe('1280')
    expect(parsed.searchParams.get('height')).toBe('720')
    expect(parsed.searchParams.get('format')).toBe('jpeg')

    expect(buildApiFlashUrl('https://argandici.com', '')).toBeNull()
    expect(buildApiFlashUrl('ftp://invalid.example', 'api-key-123')).toBeNull()
  })

  it('captures JPEG image bytes, stores base64 in PostgreSQL and rejects non-image responses', async () => {
    const insertValues = vi.fn(() => ({
      onConflictDoUpdate: vi.fn(async () => []),
    }))
    const updateSet = vi.fn(() => ({
      where: vi.fn(async () => []),
    }))
    const fakeDb = {
      insert: vi.fn(() => ({ values: insertValues })),
      update: vi.fn(() => ({ set: updateSet })),
    } as unknown as SentinelDb

    const fakeJpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10])
    const okFetch = vi.fn<typeof fetch>().mockResolvedValueOnce(
      new Response(fakeJpeg, {
        status: 200,
        headers: { 'Content-Type': 'image/jpeg' },
      }),
    )

    const res = await captureProjectScreenshot(
      fakeDb,
      { id: 1, slug: 'argandici', productionUrl: 'https://argandici.com' },
      { accessKey: 'key-1', fetchImpl: okFetch },
    )

    expect(res.success).toBe(true)
    expect(res.screenshotUrl).toMatch(/^\/api\/projects\/argandici\/screenshot\?v=\d+$/)
    expect(insertValues).toHaveBeenCalledTimes(1)
    expect(updateSet).toHaveBeenCalledTimes(1)

    const htmlFetch = vi.fn<typeof fetch>().mockResolvedValueOnce(
      new Response('<html>error</html>', {
        status: 200,
        headers: { 'Content-Type': 'text/html' },
      }),
    )
    const badRes = await captureProjectScreenshot(
      fakeDb,
      { id: 1, slug: 'argandici', productionUrl: 'https://argandici.com' },
      { accessKey: 'key-1', fetchImpl: htmlFetch },
    )
    expect(badRes.success).toBe(false)
    expect(badRes.message).toContain('Unexpected screenshot content-type')
  })
})
