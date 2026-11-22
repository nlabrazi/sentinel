import type { H3Event } from 'h3'
import {
  decryptPayload,
  encryptPayload,
  exchangeOidcCode,
  fetchOidcDiscovery,
  isAdminAuthorized,
  OIDC_TX_COOKIE_NAME,
  type OidcTransactionPayload,
  SESSION_COOKIE_NAME,
  SESSION_TTL_SECONDS,
  type SessionPayload,
  sanitizeReturnTo,
} from '#server/services/auth'
import { getEnv } from '#server/utils/env'

export async function handleOidcCallback(event: H3Event) {
  const env = getEnv()
  const query = getQuery(event)

  if (typeof query.error === 'string' && query.error) {
    console.warn('[sentinel:auth] OIDC provider returned error:', query.error)
    return sendRedirect(
      event,
      `/login?error=${encodeURIComponent(query.error === 'access_denied' ? 'access_denied' : 'oidc_failed')}`,
      302,
    )
  }

  const code = typeof query.code === 'string' ? query.code : ''
  const state = typeof query.state === 'string' ? query.state : ''

  if (!code || !state) {
    return sendRedirect(event, '/login?error=invalid_state', 302)
  }

  const rawTx = getCookie(event, OIDC_TX_COOKIE_NAME)
  deleteCookie(event, OIDC_TX_COOKIE_NAME, { path: '/' })

  const tx = decryptPayload<OidcTransactionPayload>(rawTx, env.sessionSecret)
  if (!tx || tx.state !== state) {
    return sendRedirect(event, '/login?error=invalid_state', 302)
  }

  const requestUrl = getRequestURL(event)
  const redirectUri = env.authentik.redirectUri || `${requestUrl.origin}${requestUrl.pathname}`

  let user: SessionPayload['user']
  try {
    const discovery = await fetchOidcDiscovery(env.authentik.issuer)
    user = await exchangeOidcCode({
      discovery,
      code,
      codeVerifier: tx.codeVerifier,
      clientId: env.authentik.clientId,
      clientSecret: env.authentik.clientSecret,
      redirectUri,
    })
  } catch (error) {
    console.error('[sentinel:auth] OIDC callback exchange failed:', error)
    return sendRedirect(event, '/login?error=oidc_failed', 302)
  }

  if (!isAdminAuthorized(user, env)) {
    console.warn(
      `[sentinel:auth] Rejected non-admin Authentik user username=${user.username} email=${user.email} groups=${JSON.stringify(user.groups)}`,
    )
    return sendRedirect(event, '/login?error=forbidden', 302)
  }

  const session: SessionPayload = {
    user,
    exp: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS,
  }

  setCookie(event, SESSION_COOKIE_NAME, encryptPayload(session, env.sessionSecret), {
    httpOnly: true,
    sameSite: 'lax',
    secure: env.isProduction,
    path: '/',
    maxAge: SESSION_TTL_SECONDS,
  })

  return sendRedirect(event, sanitizeReturnTo(tx.returnTo), 302)
}
