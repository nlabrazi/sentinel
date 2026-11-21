import { isDevBypassActive } from '#server/services/auth'
import { getEnv } from '#server/utils/env'

export default defineEventHandler((event) => {
  const env = getEnv()
  return {
    user: event.context.user ?? null,
    authMode: isDevBypassActive(env) ? 'dev-bypass' : 'authentik-oidc',
    grafanaBaseUrl: env.grafana.baseUrl || null,
  }
})
