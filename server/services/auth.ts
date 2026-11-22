import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto'
import type { SentinelEnv } from '#server/utils/env'

export const SESSION_COOKIE_NAME = 'sentinel_session'
export const OIDC_TX_COOKIE_NAME = 'sentinel_oidc_tx'
export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 7
export const OIDC_TX_TTL_SECONDS = 60 * 10

export interface SessionUser {
  sub: string
  username: string
  name: string
  email: string
  groups: string[]
  devBypass?: boolean
}

export interface SessionPayload {
  user: SessionUser
  exp: number
}

export interface OidcTransactionPayload {
  state: string
  codeVerifier: string
  returnTo: string
  exp: number
}

export interface OidcDiscoveryDocument {
  authorization_endpoint: string
  token_endpoint: string
  userinfo_endpoint?: string
  end_session_endpoint?: string
}

export const DEV_ADMIN_USER: SessionUser = {
  sub: 'dev-admin',
  username: 'admin',
  name: 'Local Admin',
  email: 'admin@sentinel.local',
  groups: ['authentik Admins'],
  devBypass: true,
}

const PUBLIC_PREFIXES = ['/_nuxt/', '/__nuxt_error', '/api/_nuxt_icon/', '/auth/', '/users/auth/']
const PUBLIC_EXACT_PATHS = new Set([
  '/login',
  '/users/sign_in',
  '/metrics',
  '/favicon.ico',
  '/favicon-32x32.png',
  '/apple-touch-icon.png',
  '/icon-192.png',
  '/icon-512.png',
  '/logo.png',
  '/site.webmanifest',
  '/robots.txt',
])

const discoveryCache = new Map<string, { doc: OidcDiscoveryDocument; expiresAt: number }>()

export function isPublicPath(pathname: string): boolean {
  const normalized = pathname.split('?')[0] || '/'
  if (PUBLIC_EXACT_PATHS.has(normalized)) {
    return true
  }
  return PUBLIC_PREFIXES.some((prefix) => normalized.startsWith(prefix))
}

export function isDevBypassActive(env: SentinelEnv): boolean {
  return !env.isProduction && env.authDevBypass
}

export function sanitizeReturnTo(raw: string | undefined): string {
  if (!raw || typeof raw !== 'string') {
    return '/'
  }
  const trimmed = raw.trim()
  if (!trimmed.startsWith('/') || trimmed.startsWith('//') || trimmed.startsWith('/\\')) {
    return '/'
  }
  const pathOnly = trimmed.split(/[?#]/)[0] || '/'
  if (
    pathOnly.startsWith('/auth/') ||
    pathOnly.startsWith('/users/auth/') ||
    pathOnly === '/login' ||
    pathOnly === '/users/sign_in'
  ) {
    return '/'
  }
  return trimmed
}

export function isAdminAuthorized(user: SessionUser, env: SentinelEnv): boolean {
  const allowedGroups = env.authentik.allowedGroups.map((group) => group.toLowerCase())
  const allowedEmails = env.authentik.allowedEmails.map((email) => email.toLowerCase())

  if (allowedGroups.length === 0 && allowedEmails.length === 0) {
    return false
  }

  const userGroups = user.groups.map((group) => group.toLowerCase())
  const groupMatch =
    allowedGroups.length > 0 && userGroups.some((group) => allowedGroups.includes(group))
  const emailMatch =
    allowedEmails.length > 0 &&
    Boolean(user.email) &&
    allowedEmails.includes(user.email.toLowerCase())

  return groupMatch || emailMatch
}

function deriveEncryptionKey(secret: string): Buffer {
  if (!secret || secret.length < 16) {
    throw new Error('SESSION_SECRET must be at least 16 characters long')
  }
  return createHash('sha256').update(secret).digest()
}

export function encryptPayload<T extends object>(payload: T, secret: string): string {
  const key = deriveEncryptionKey(secret)
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  const plaintext = Buffer.from(JSON.stringify(payload), 'utf8')
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()])
  const authTag = cipher.getAuthTag()
  return Buffer.concat([iv, authTag, encrypted]).toString('base64url')
}

export function decryptPayload<T extends { exp?: number }>(
  token: string | undefined,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): T | null {
  if (!token || !secret) {
    return null
  }
  try {
    const key = deriveEncryptionKey(secret)
    const raw = Buffer.from(token, 'base64url')
    if (raw.length < 29 || raw.toString('base64url') !== token) {
      return null
    }
    const iv = raw.subarray(0, 12)
    const authTag = raw.subarray(12, 28)
    const ciphertext = raw.subarray(28)
    const decipher = createDecipheriv('aes-256-gcm', key, iv)
    decipher.setAuthTag(authTag)
    const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString(
      'utf8',
    )
    const parsed = JSON.parse(decrypted) as T
    if (typeof parsed.exp === 'number' && parsed.exp <= nowSeconds) {
      return null
    }
    return parsed
  } catch {
    return null
  }
}

export function createPkcePair(): { codeVerifier: string; codeChallenge: string } {
  const codeVerifier = randomBytes(32).toString('base64url')
  const codeChallenge = createHash('sha256').update(codeVerifier).digest('base64url')
  return { codeVerifier, codeChallenge }
}

export function createOidcState(): string {
  return randomBytes(24).toString('base64url')
}

export function clearOidcDiscoveryCache(): void {
  discoveryCache.clear()
}

export async function fetchOidcDiscovery(
  issuer: string,
  fetchImpl: typeof fetch = fetch,
): Promise<OidcDiscoveryDocument> {
  const normalizedIssuer = issuer.replace(/\/+$/, '')
  const cached = discoveryCache.get(normalizedIssuer)
  if (cached && cached.expiresAt > Date.now()) {
    return cached.doc
  }

  const discoveryUrl = `${normalizedIssuer}/.well-known/openid-configuration`
  const response = await fetchImpl(discoveryUrl, {
    headers: { Accept: 'application/json' },
  })
  if (!response.ok) {
    throw new Error(`OIDC discovery failed (${response.status}) for ${discoveryUrl}`)
  }

  const doc = (await response.json()) as OidcDiscoveryDocument
  if (!doc.authorization_endpoint || !doc.token_endpoint) {
    throw new Error('OIDC discovery document is missing required endpoints')
  }

  discoveryCache.set(normalizedIssuer, {
    doc,
    expiresAt: Date.now() + 60 * 60 * 1000,
  })
  return doc
}

export function buildAuthorizationUrl(params: {
  authorizationEndpoint: string
  clientId: string
  redirectUri: string
  state: string
  codeChallenge: string
}): string {
  const url = new URL(params.authorizationEndpoint)
  url.searchParams.set('response_type', 'code')
  url.searchParams.set('client_id', params.clientId)
  url.searchParams.set('redirect_uri', params.redirectUri)
  url.searchParams.set('scope', 'openid profile email')
  url.searchParams.set('state', params.state)
  url.searchParams.set('code_challenge', params.codeChallenge)
  url.searchParams.set('code_challenge_method', 'S256')
  return url.toString()
}

function decodeJwtPayload(jwt: string | undefined): Record<string, unknown> {
  if (!jwt) {
    return {}
  }
  const parts = jwt.split('.')
  if (parts.length !== 3 || !parts[1]) {
    return {}
  }
  try {
    return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')) as Record<
      string,
      unknown
    >
  } catch {
    return {}
  }
}

export async function exchangeOidcCode(params: {
  discovery: OidcDiscoveryDocument
  code: string
  codeVerifier: string
  clientId: string
  clientSecret: string
  redirectUri: string
  fetchImpl?: typeof fetch
}): Promise<SessionUser> {
  const fetchImpl = params.fetchImpl ?? fetch
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code: params.code,
    redirect_uri: params.redirectUri,
    client_id: params.clientId,
    client_secret: params.clientSecret,
    code_verifier: params.codeVerifier,
  })

  const tokenResponse = await fetchImpl(params.discovery.token_endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body,
  })

  if (!tokenResponse.ok) {
    throw new Error(`OIDC token exchange failed (${tokenResponse.status})`)
  }

  const tokenData = (await tokenResponse.json()) as {
    access_token?: string
    id_token?: string
  }

  let claims = decodeJwtPayload(tokenData.id_token)

  if (params.discovery.userinfo_endpoint && tokenData.access_token) {
    const userinfoResponse = await fetchImpl(params.discovery.userinfo_endpoint, {
      headers: {
        Authorization: `Bearer ${tokenData.access_token}`,
        Accept: 'application/json',
      },
    })
    if (userinfoResponse.ok) {
      const userinfo = (await userinfoResponse.json()) as Record<string, unknown>
      claims = { ...claims, ...userinfo }
    }
  }

  const rawGroups = claims.groups
  const groups = Array.isArray(rawGroups)
    ? rawGroups.filter((g): g is string => typeof g === 'string')
    : []

  const sub = typeof claims.sub === 'string' ? claims.sub : ''
  const email = typeof claims.email === 'string' ? claims.email : ''
  const username =
    (typeof claims.preferred_username === 'string' && claims.preferred_username) ||
    (typeof claims.nickname === 'string' && claims.nickname) ||
    email ||
    sub
  const name = (typeof claims.name === 'string' && claims.name) || username

  if (!sub && !email) {
    throw new Error('OIDC provider did not return a user identifier')
  }

  return {
    sub: sub || email,
    username,
    name,
    email,
    groups,
  }
}
