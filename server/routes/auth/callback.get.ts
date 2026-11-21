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

export default defineEventHandler(async (event) => {
  const env = getEnv()
  const query = getQuery(event)
  const code = typeof query.code === 'string' ? query.code : ''
  const state = typeof query.state === 'string' ? query.state : ''

  if (!code || !state) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Missing OIDC authorization code or state',
    })
  }

  const rawTx = getCookie(event, OIDC_TX_COOKIE_NAME)
  deleteCookie(event, OIDC_TX_COOKIE_NAME, { path: '/' })

  const tx = decryptPayload<OidcTransactionPayload>(rawTx, env.sessionSecret)
  if (!tx || tx.state !== state) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Invalid or expired OIDC state',
    })
  }

  const discovery = await fetchOidcDiscovery(env.authentik.issuer)
  const requestUrl = getRequestURL(event)
  const redirectUri = env.authentik.redirectUri || `${requestUrl.origin}/auth/callback`

  const user = await exchangeOidcCode({
    discovery,
    code,
    codeVerifier: tx.codeVerifier,
    clientId: env.authentik.clientId,
    clientSecret: env.authentik.clientSecret,
    redirectUri,
  })

  if (!isAdminAuthorized(user, env)) {
    throw createError({
      statusCode: 403,
      statusMessage: 'Forbidden',
      message: 'Your Authentik account does not have admin access to Sentinel.',
    })
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
})
