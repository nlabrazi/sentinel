import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  clearUmamiTokenCache,
  extractDomainHost,
  fetchUmamiStats24h,
  fetchUmamiWebsites,
  parseUmamiStatsResponse,
} from '#server/services/umami'

describe('umami v2 client', () => {
  afterEach(() => {
    clearUmamiTokenCache()
  })

  it('extracts normalized hostnames and parses v2 nested/flat metric objects', () => {
    expect(extractDomainHost('https://sentinel.nabster.dev/dashboard')).toBe('sentinel.nabster.dev')
    expect(extractDomainHost('NABSTER.DEV')).toBe('nabster.dev')

    expect(
      parseUmamiStatsResponse({
        visitors: { value: 42 },
        pageviews: { value: 128 },
        visits: { value: 50 },
        bounces: { value: 15 },
      }),
    ).toEqual({
      visitors: 42,
      pageviews: 128,
      visits: 50,
      bounces: 15,
      bounceRate: 30,
    })

    expect(
      parseUmamiStatsResponse({ visitors: 10, pageviews: 20, visits: 0, bounces: 0 }),
    ).toMatchObject({ visitors: 10, pageviews: 20, bounceRate: 0 })
  })

  it('fetches websites and 24h stats using Bearer JWT authentication', async () => {
    const mockFetch = vi.fn<typeof fetch>()
    mockFetch
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            data: [{ id: 'site-1', name: 'Portfolio', domain: 'nabster.dev' }],
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            visitors: { value: 12 },
            pageviews: { value: 30 },
            visits: { value: 15 },
            bounces: { value: 3 },
          }),
          { status: 200 },
        ),
      )

    const env = {
      baseUrl: 'https://umami.nabster.dev',
      authToken: 'jwt-token',
      apiKey: '',
      username: '',
      password: '',
    }

    const sites = await fetchUmamiWebsites({ env, fetchImpl: mockFetch })
    expect(sites).toEqual([{ id: 'site-1', name: 'Portfolio', domain: 'nabster.dev' }])

    const res = await fetchUmamiStats24h('site-1', { env, fetchImpl: mockFetch })
    expect(res.stats).toEqual({
      visitors: 12,
      pageviews: 30,
      visits: 15,
      bounces: 3,
      bounceRate: 20,
    })
  })
})
