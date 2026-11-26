import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  buildAuthorizationUrl,
  clearOidcDiscoveryCache,
  createPkcePair,
  decryptPayload,
  encryptPayload,
  exchangeOidcCode,
  fetchOidcDiscovery,
  isAdminAuthorized,
  isDevBypassActive,
  isPublicPath,
  type SessionPayload,
  type SessionUser,
  sanitizeReturnTo,
} from '#server/services/auth'
import { getEnv, getEnvStatusReport } from '#server/utils/env'

const TEST_SECRET = '0123456789abcdef0123456789abcdef0123456789abcdef'

describe('auth service & env helpers', () => {
  afterEach(() => {
    clearOidcDiscoveryCache()
  })

  it('encrypts and decrypts session payloads and rejects tampered or expired tokens', () => {
    const payload: SessionPayload = {
      user: {
        sub: 'user-1',
        username: 'nabil',
        name: 'Nabil',
        email: 'admin@example.com',
        groups: ['authentik Admins'],
      },
      exp: 2_000_000_000,
    }

    const token = encryptPayload(payload, TEST_SECRET)
    const tampered = `${token.slice(0, 10)}${token[10] === 'A' ? 'B' : 'A'}${token.slice(11)}`
    expect(decryptPayload<SessionPayload>(token, TEST_SECRET, 1_900_000_000)).toEqual(payload)
    expect(decryptPayload<SessionPayload>(token, TEST_SECRET, 2_000_000_001)).toBeNull()
    expect(decryptPayload<SessionPayload>(`${token}x`, TEST_SECRET, 1_900_000_000)).toBeNull()
    expect(decryptPayload<SessionPayload>(tampered, TEST_SECRET, 1_900_000_000)).toBeNull()
    expect(
      decryptPayload<SessionPayload>(token, 'wrong-secret-0123456789', 1_900_000_000),
    ).toBeNull()
  })

  it('enforces admin authorization by Authentik group or email and fails closed when unconfigured', () => {
    const adminByGroup: SessionUser = {
      sub: '1',
      username: 'nabil',
      name: 'Nabil',
      email: 'other@example.com',
      groups: ['Authentik Admins'],
    }
    const adminByEmail: SessionUser = {
      sub: '2',
      username: 'nabil',
      name: 'Nabil',
      email: 'admin@example.com',
      groups: ['users'],
    }
    const regularUser: SessionUser = {
      sub: '3',
      username: 'guest',
      name: 'Guest',
      email: 'guest@example.com',
      groups: ['users'],
    }

    const env = getEnv({
      AUTHENTIK_ALLOWED_GROUPS: 'authentik Admins',
      AUTHENTIK_ALLOWED_EMAILS: 'admin@example.com',
    })

    expect(isAdminAuthorized(adminByGroup, env)).toBe(true)
    expect(isAdminAuthorized(adminByEmail, env)).toBe(true)
    expect(isAdminAuthorized(regularUser, env)).toBe(false)

    const emptyEnv = getEnv({
      AUTHENTIK_ALLOWED_GROUPS: '',
      AUTHENTIK_ALLOWED_EMAILS: '',
    })
    expect(isAdminAuthorized(adminByGroup, emptyEnv)).toBe(false)
  })

  it('strictly disables dev bypass in production', () => {
    expect(isDevBypassActive(getEnv({ NODE_ENV: 'development', AUTH_DEV_BYPASS: 'true' }))).toBe(
      true,
    )
    expect(isDevBypassActive(getEnv({ NODE_ENV: 'test', AUTH_DEV_BYPASS: 'true' }))).toBe(true)
    expect(isDevBypassActive(getEnv({ NODE_ENV: 'production', AUTH_DEV_BYPASS: 'true' }))).toBe(
      false,
    )
    expect(isDevBypassActive(getEnv({ NODE_ENV: 'development', AUTH_DEV_BYPASS: 'false' }))).toBe(
      false,
    )
  })

  it('identifies public vs protected routes and sanitizes returnTo URLs', () => {
    expect(isPublicPath('/login')).toBe(true)
    expect(isPublicPath('/users/sign_in')).toBe(true)
    expect(isPublicPath('/api/health')).toBe(true)
    expect(isPublicPath('/metrics')).toBe(true)
    expect(isPublicPath('/favicon.ico')).toBe(true)
    expect(isPublicPath('/favicon-32x32.png')).toBe(true)
    expect(isPublicPath('/apple-touch-icon.png')).toBe(true)
    expect(isPublicPath('/icon-192.png')).toBe(true)
    expect(isPublicPath('/icon-512.png')).toBe(true)
    expect(isPublicPath('/logo.png')).toBe(true)
    expect(isPublicPath('/site.webmanifest')).toBe(true)
    expect(isPublicPath('/robots.txt')).toBe(true)
    expect(isPublicPath('/auth/login')).toBe(true)
    expect(isPublicPath('/auth/callback?code=abc')).toBe(true)
    expect(isPublicPath('/users/auth/openid_connect/callback?code=abc')).toBe(true)
    expect(isPublicPath('/_nuxt/app.js')).toBe(true)
    expect(isPublicPath('/')).toBe(false)
    expect(isPublicPath('/api/projects')).toBe(false)

    expect(sanitizeReturnTo('/projects/sentinel')).toBe('/projects/sentinel')
    expect(sanitizeReturnTo('https://evil.com')).toBe('/')
    expect(sanitizeReturnTo('//evil.com')).toBe('/')
    expect(sanitizeReturnTo('/auth/login')).toBe('/')
    expect(sanitizeReturnTo('/login')).toBe('/')
    expect(sanitizeReturnTo('/login?logged_out=1')).toBe('/')
    expect(sanitizeReturnTo('/users/sign_in')).toBe('/')
    expect(sanitizeReturnTo('/users/sign_in?from=rails')).toBe('/')
    expect(sanitizeReturnTo(undefined)).toBe('/')
  })

  it('builds PKCE authorization URL and exchanges OIDC authorization codes', async () => {
    const { codeVerifier, codeChallenge } = createPkcePair()
    expect(codeVerifier.length).toBeGreaterThan(20)
    expect(codeChallenge).not.toBe(codeVerifier)

    const authUrl = buildAuthorizationUrl({
      authorizationEndpoint: 'https://auth.nabster.dev/application/o/authorize/',
      clientId: 'sentinel',
      redirectUri: 'https://sentinel.nabster.dev/auth/callback',
      state: 'abc-state',
      codeChallenge,
    })

    const parsed = new URL(authUrl)
    expect(parsed.searchParams.get('scope')).toBe('openid profile email')
    expect(parsed.searchParams.get('code_challenge_method')).toBe('S256')
    expect(parsed.searchParams.get('state')).toBe('abc-state')

    const mockFetch = vi.fn<typeof fetch>()
    mockFetch.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          authorization_endpoint: 'https://auth.nabster.dev/application/o/authorize/',
          token_endpoint: 'https://auth.nabster.dev/application/o/token/',
          userinfo_endpoint: 'https://auth.nabster.dev/application/o/userinfo/',
        }),
        { status: 200 },
      ),
    )

    const discovery = await fetchOidcDiscovery(
      'https://auth.nabster.dev/application/o/sentinel/',
      mockFetch,
    )

    const fakeIdTokenPayload = Buffer.from(
      JSON.stringify({ sub: 'sub-42', preferred_username: 'nabil' }),
    ).toString('base64url')

    mockFetch
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            access_token: 'access-123',
            id_token: `header.${fakeIdTokenPayload}.sig`,
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            sub: 'sub-42',
            preferred_username: 'nabil',
            name: 'Nabil Labrazi',
            email: 'admin@example.com',
            groups: ['authentik Admins'],
          }),
          { status: 200 },
        ),
      )

    const user = await exchangeOidcCode({
      discovery,
      code: 'auth-code',
      codeVerifier,
      clientId: 'sentinel',
      clientSecret: 'secret',
      redirectUri: 'https://sentinel.nabster.dev/auth/callback',
      fetchImpl: mockFetch,
    })

    expect(user).toEqual({
      sub: 'sub-42',
      username: 'nabil',
      name: 'Nabil Labrazi',
      email: 'admin@example.com',
      groups: ['authentik Admins'],
    })
  })

  it('reports env status without leaking values', () => {
    const report = getEnvStatusReport({
      SESSION_SECRET: TEST_SECRET,
      GITHUB_TOKEN: 'ghp_secret',
      VPS_HOST: 'vps.example.com',
    })
    expect(report.find((item) => item.key === 'GITHUB_TOKEN')?.configured).toBe(true)
    expect(report.find((item) => item.key === 'GRAFANA_BASE_URL')?.configured).toBe(false)
    expect(JSON.stringify(report)).not.toContain('ghp_secret')
  })
})
