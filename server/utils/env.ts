export interface SentinelEnv {
  nodeEnv: string
  isProduction: boolean
  isTest: boolean
  sessionSecret: string
  authDevBypass: boolean
  authentik: {
    enabled: boolean
    issuer: string
    clientId: string
    clientSecret: string
    redirectUri: string
    allowedGroups: string[]
    allowedEmails: string[]
  }
  databaseUrl: string
  githubToken: string
  apiflashAccessKey: string
  vps: {
    host: string
    user: string
    appsRoot: string
    sshKeyPath: string
    sshKnownHostsPath: string
    sshVerifyHostKey: 'always' | 'accept_new' | 'never'
    connectTimeoutSeconds: number
    commandTimeoutSeconds: number
  }
  cron: {
    overdueGraceMinutes: number
    syncStaleAfterMinutes: number
  }
  prometheusMetricsToken: string
  umami: {
    baseUrl: string
    authToken: string
    apiKey: string
    username: string
    password: string
  }
  grafana: {
    baseUrl: string
    dashboardUid: string
    dashboardSlug: string
    variableName: string
    defaultTheme: 'dark' | 'light'
    orgId: string
    defaultFrom: string
    defaultTo: string
    defaultTimezone: string
    refresh: string
    panelId: string
    globalVariableValue: string
  }
}

export interface EnvStatusItem {
  category: string
  key: string
  configured: boolean
  required: boolean
}

function splitCsv(value: string | undefined): string[] {
  if (!value) {
    return []
  }
  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
}

function parsePositiveInt(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback
  }
  const parsed = Number.parseInt(value, 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

function parseBool(value: string | undefined, fallback = false): boolean {
  if (value === undefined || value === '') {
    return fallback
  }
  return ['1', 'true', 'yes', 'on'].includes(value.trim().toLowerCase())
}

function parseVerifyHostKey(value: string | undefined): 'always' | 'accept_new' | 'never' {
  const normalized = (value ?? 'always').trim().toLowerCase()
  if (normalized === 'never' || normalized === 'false') {
    return 'never'
  }
  if (normalized === 'accept_new') {
    return 'accept_new'
  }
  return 'always'
}

export function getEnv(source: Record<string, string | undefined> = process.env): SentinelEnv {
  const nodeEnv = source.NODE_ENV || 'development'
  const isProduction = nodeEnv === 'production'
  const isTest = nodeEnv === 'test' || Boolean(source.VITEST)

  const pgUser = source.POSTGRES_USER || 'postgres'
  const pgPass = source.POSTGRES_PASSWORD || 'postgres'
  const pgHost = source.POSTGRES_HOST || 'localhost'
  const pgDb = source.POSTGRES_DB || 'sentinel_development'
  const defaultDbUrl = `postgresql://${pgUser}:${pgPass}@${pgHost}:5432/${pgDb}`

  const defaultTheme =
    (source.GRAFANA_DEFAULT_THEME || 'dark').trim().toLowerCase() === 'light' ? 'light' : 'dark'

  return {
    nodeEnv,
    isProduction,
    isTest,
    sessionSecret: source.SESSION_SECRET || '',
    authDevBypass: parseBool(source.AUTH_DEV_BYPASS, false),
    authentik: {
      enabled: parseBool(source.AUTHENTIK_ENABLED, true),
      issuer: (source.AUTHENTIK_ISSUER || '').trim().replace(/\/+$/, ''),
      clientId: (source.AUTHENTIK_CLIENT_ID || '').trim(),
      clientSecret: (source.AUTHENTIK_CLIENT_SECRET || '').trim(),
      redirectUri: (source.AUTHENTIK_REDIRECT_URI || '').trim(),
      allowedGroups: splitCsv(source.AUTHENTIK_ALLOWED_GROUPS),
      allowedEmails: splitCsv(source.AUTHENTIK_ALLOWED_EMAILS),
    },
    databaseUrl: (source.DATABASE_URL || defaultDbUrl).trim(),
    githubToken: (source.GITHUB_TOKEN || '').trim(),
    apiflashAccessKey: (source.APIFLASH_ACCESS_KEY || '').trim(),
    vps: {
      host: (source.VPS_HOST || '').trim(),
      user: (source.VPS_USER || 'control-panel').trim(),
      appsRoot: (source.VPS_APPS_ROOT || '/srv/apps').trim().replace(/\/+$/, ''),
      sshKeyPath: (source.SSH_KEY_PATH || 'config/ssh_key/sentinel_control_panel').trim(),
      sshKnownHostsPath: (source.SSH_KNOWN_HOSTS_PATH || 'config/ssh_key/known_hosts').trim(),
      sshVerifyHostKey: parseVerifyHostKey(source.SSH_VERIFY_HOST_KEY),
      connectTimeoutSeconds: parsePositiveInt(source.SSH_CONNECT_TIMEOUT_SECONDS, 10),
      commandTimeoutSeconds: parsePositiveInt(source.SSH_COMMAND_TIMEOUT_SECONDS, 600),
    },
    cron: {
      overdueGraceMinutes: parsePositiveInt(source.CRON_OVERDUE_GRACE_MINUTES, 15),
      syncStaleAfterMinutes: parsePositiveInt(source.CRON_SYNC_STALE_AFTER_MINUTES, 15),
    },
    prometheusMetricsToken: (source.PROMETHEUS_METRICS_TOKEN || '').trim(),
    umami: {
      baseUrl: (source.UMAMI_BASE_URL || 'https://umami.nabster.dev').trim().replace(/\/+$/, ''),
      authToken: (source.UMAMI_AUTH_TOKEN || '').trim(),
      apiKey: (source.UMAMI_API_KEY || '').trim(),
      username: (source.UMAMI_USERNAME || '').trim(),
      password: (source.UMAMI_PASSWORD || '').trim(),
    },
    grafana: {
      baseUrl: (source.GRAFANA_BASE_URL || '').trim().replace(/\/+$/, ''),
      dashboardUid: (source.GRAFANA_DASHBOARD_UID || '').trim(),
      dashboardSlug: (source.GRAFANA_DASHBOARD_SLUG || 'applications-overview').trim(),
      variableName: (source.GRAFANA_VARIABLE_NAME || 'app').trim(),
      defaultTheme,
      orgId: (source.GRAFANA_ORG_ID || '1').trim(),
      defaultFrom: (source.GRAFANA_DEFAULT_FROM || 'now-6h').trim(),
      defaultTo: (source.GRAFANA_DEFAULT_TO || 'now').trim(),
      defaultTimezone: (source.GRAFANA_DEFAULT_TIMEZONE || 'browser').trim(),
      refresh: (source.GRAFANA_REFRESH || '30s').trim(),
      panelId: (source.GRAFANA_PANEL_ID || 'panel-6').trim(),
      globalVariableValue: (source.GRAFANA_GLOBAL_VARIABLE_VALUE || 'All').trim(),
    },
  }
}

export function getEnvStatusReport(
  source: Record<string, string | undefined> = process.env,
): EnvStatusItem[] {
  const env = getEnv(source)

  return [
    { category: 'Core', key: 'DATABASE_URL', configured: Boolean(env.databaseUrl), required: true },
    {
      category: 'Core',
      key: 'SESSION_SECRET',
      configured: env.sessionSecret.length >= 32,
      required: true,
    },
    {
      category: 'Authentik SSO',
      key: 'AUTHENTIK_ISSUER',
      configured: Boolean(env.authentik.issuer),
      required: env.authentik.enabled,
    },
    {
      category: 'Authentik SSO',
      key: 'AUTHENTIK_CLIENT_ID',
      configured: Boolean(env.authentik.clientId),
      required: env.authentik.enabled,
    },
    {
      category: 'Authentik SSO',
      key: 'AUTHENTIK_CLIENT_SECRET',
      configured: Boolean(env.authentik.clientSecret),
      required: env.authentik.enabled,
    },
    {
      category: 'Authentik SSO',
      key: 'AUTHENTIK_REDIRECT_URI',
      configured: Boolean(env.authentik.redirectUri),
      required: env.authentik.enabled,
    },
    {
      category: 'VPS / SSH',
      key: 'VPS_HOST',
      configured: Boolean(env.vps.host),
      required: true,
    },
    {
      category: 'VPS / SSH',
      key: 'VPS_USER',
      configured: Boolean(env.vps.user),
      required: true,
    },
    {
      category: 'VPS / SSH',
      key: 'SSH_KEY_PATH',
      configured: Boolean(env.vps.sshKeyPath),
      required: true,
    },
    {
      category: 'GitHub',
      key: 'GITHUB_TOKEN',
      configured: Boolean(env.githubToken),
      required: true,
    },
    {
      category: 'Screenshots',
      key: 'APIFLASH_ACCESS_KEY',
      configured: Boolean(env.apiflashAccessKey),
      required: false,
    },
    {
      category: 'Monitoring',
      key: 'PROMETHEUS_METRICS_TOKEN',
      configured: Boolean(env.prometheusMetricsToken),
      required: false,
    },
    {
      category: 'Grafana',
      key: 'GRAFANA_BASE_URL',
      configured: Boolean(env.grafana.baseUrl),
      required: false,
    },
    {
      category: 'Grafana',
      key: 'GRAFANA_DASHBOARD_UID',
      configured: Boolean(env.grafana.dashboardUid),
      required: false,
    },
    {
      category: 'Umami',
      key: 'UMAMI_BASE_URL',
      configured: Boolean(env.umami.baseUrl),
      required: false,
    },
    {
      category: 'Umami',
      key: 'UMAMI_AUTH_TOKEN / API_KEY / LOGIN',
      configured: Boolean(
        env.umami.authToken || env.umami.apiKey || (env.umami.username && env.umami.password),
      ),
      required: false,
    },
  ]
}
