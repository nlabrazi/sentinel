import {
  decryptPayload,
  isAdminAuthorized,
  isDevBypassActive,
  SESSION_COOKIE_NAME,
  type SessionPayload,
} from '#server/services/auth'
import { getEnv } from '#server/utils/env'

export default defineEventHandler((event) => {
  const env = getEnv()
  if (isDevBypassActive(env)) {
    return sendRedirect(event, '/', 302)
  }

  const rawCookie = getCookie(event, SESSION_COOKIE_NAME)
  const session = env.sessionSecret
    ? decryptPayload<SessionPayload>(rawCookie, env.sessionSecret)
    : null

  if (session?.user && isAdminAuthorized(session.user, env)) {
    return sendRedirect(event, '/', 302)
  }

  return sendRedirect(event, '/login', 302)
})
