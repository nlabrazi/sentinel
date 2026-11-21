import { getDb } from '#server/db'
import {
  generatePrometheusMetricsText,
  verifyMetricsBearerToken,
} from '#server/services/cron-metrics'
import { getEnv } from '#server/utils/env'

export default defineEventHandler(async (event) => {
  const env = getEnv()
  const authHeader = getHeader(event, 'authorization')

  if (!verifyMetricsBearerToken(authHeader, env.prometheusMetricsToken)) {
    setHeader(event, 'WWW-Authenticate', 'Bearer realm="metrics"')
    setResponseStatus(event, 401)
    return ''
  }

  setHeader(event, 'Cache-Control', 'no-store')
  setHeader(event, 'Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  return await generatePrometheusMetricsText(getDb())
})
