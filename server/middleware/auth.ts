import {
  DEV_ADMIN_USER,
  decryptPayload,
  isAdminAuthorized,
  isDevBypassActive,
  isPublicPath,
  SESSION_COOKIE_NAME,
  type SessionPayload,
  type SessionUser,
} from '#server/services/auth'
import { getEnv } from '#server/utils/env'

declare module 'h3' {
  interface H3EventContext {
    user?: SessionUser
  }
}

export default defineEventHandler((event) => {
  const pathname = getRequestURL(event).pathname
  if (isPublicPath(pathname)) {
    return
  }

  const env = getEnv()

  if (isDevBypassActive(env)) {
    event.context.user = DEV_ADMIN_USER
    return
  }

  const rawCookie = getCookie(event, SESSION_COOKIE_NAME)
  const session = env.sessionSecret
    ? decryptPayload<SessionPayload>(rawCookie, env.sessionSecret)
    : null

  if (session?.user && isAdminAuthorized(session.user, env)) {
    event.context.user = session.user
    return
  }

  if (pathname.startsWith('/api/')) {
    throw createError({
      statusCode: 401,
      statusMessage: 'Unauthorized',
      message: 'Authentication required',
    })
  }

  const returnTo = encodeURIComponent(`${pathname}${getRequestURL(event).search}`)
  return sendRedirect(event, `/login?returnTo=${returnTo}`, 302)
})
