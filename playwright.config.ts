import { defineSharedPlaywrightConfig } from '@nlabrazi/config-playwright'

export default defineSharedPlaywrightConfig({
  useBuiltServerInCI: true,
  env: {
    NODE_ENV: 'test',
    AUTH_DEV_BYPASS: process.env.AUTH_DEV_BYPASS || 'true',
    SESSION_SECRET: process.env.SESSION_SECRET || 'e2e-session-secret-0123456789abcdef0123456789',
    PROMETHEUS_METRICS_TOKEN: process.env.PROMETHEUS_METRICS_TOKEN || 'e2e-metrics-token',
    DATABASE_URL:
      process.env.DATABASE_URL ||
      'postgresql://postgres:postgres@localhost:5432/sentinel_development',
  },
})
