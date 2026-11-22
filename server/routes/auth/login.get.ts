import {
  buildAuthorizationUrl,
  createOidcState,
  createPkcePair,
  encryptPayload,
  fetchOidcDiscovery,
  isDevBypassActive,
  OIDC_TX_COOKIE_NAME,
  OIDC_TX_TTL_SECONDS,
  type OidcTransactionPayload,
  sanitizeReturnTo,
} from '#server/services/auth'
import { getEnv } from '#server/utils/env'

export default defineEventHandler(async (event) => {
  const env = getEnv()
  const query = getQuery(event)
  const returnTo = sanitizeReturnTo(typeof query.returnTo === 'string' ? query.returnTo : '/')

  if (isDevBypassActive(env)) {
    return sendRedirect(event, returnTo, 302)
  }

  if (!env.authentik.enabled || !env.authentik.issuer || !env.authentik.clientId) {
    return sendRedirect(event, '/login?error=not_configured', 302)
  }

  if (!env.sessionSecret || env.sessionSecret.length < 16) {
    return sendRedirect(event, '/login?error=not_configured', 302)
  }

  const discovery = await fetchOidcDiscovery(env.authentik.issuer)
  const state = createOidcState()
  const { codeVerifier, codeChallenge } = createPkcePair()

  const requestUrl = getRequestURL(event)
  const redirectUri = env.authentik.redirectUri || `${requestUrl.origin}/auth/callback`

  const txPayload: OidcTransactionPayload = {
    state,
    codeVerifier,
    returnTo,
    exp: Math.floor(Date.now() / 1000) + OIDC_TX_TTL_SECONDS,
  }

  setCookie(event, OIDC_TX_COOKIE_NAME, encryptPayload(txPayload, env.sessionSecret), {
    httpOnly: true,
    sameSite: 'lax',
    secure: env.isProduction,
    path: '/',
    maxAge: OIDC_TX_TTL_SECONDS,
  })

  const authorizationUrl = buildAuthorizationUrl({
    authorizationEndpoint: discovery.authorization_endpoint,
    clientId: env.authentik.clientId,
    redirectUri,
    state,
    codeChallenge,
  })

  return sendRedirect(event, authorizationUrl, 302)
})
