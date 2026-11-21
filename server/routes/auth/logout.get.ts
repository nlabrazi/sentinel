import { fetchOidcDiscovery, isDevBypassActive, SESSION_COOKIE_NAME } from '#server/services/auth'
import { getEnv } from '#server/utils/env'

export default defineEventHandler(async (event) => {
  const env = getEnv()
  deleteCookie(event, SESSION_COOKIE_NAME, { path: '/' })

  if (isDevBypassActive(env) || !env.authentik.enabled || !env.authentik.issuer) {
    return sendRedirect(event, '/', 302)
  }

  try {
    const discovery = await fetchOidcDiscovery(env.authentik.issuer)
    if (discovery.end_session_endpoint) {
      return sendRedirect(event, discovery.end_session_endpoint, 302)
    }
  } catch {
    // Fall back to local login screen if discovery is unavailable during logout
  }

  return sendRedirect(event, '/auth/login', 302)
})
