# Sentinel v2

**Sentinel** is a self-hosted DevOps & VPS operations control plane built with **Nuxt 4 (Nitro)**, **TypeScript**, **`@nuxt/ui` v4**, **PostgreSQL 16 + Drizzle ORM**, and shared **`@nlabrazi/dev-platform`** tooling.

It centralizes day-to-day operations across all Docker/Git projects hosted under `/srv/apps/*` without duplicating your Prometheus/Grafana monitoring stack:

- **Automatic VPS Discovery (`/srv/apps/*`)**: Scans your VPS over SSH to discover deployed directories, GitHub remotes, live `HEAD` commits, `deploy.sh` / `status.sh` scripts, `maintenance.on` flags, and optional `sentinel.json` manifests — zero manual seeding.
- **GitHub Drift & Renovate Queue**: Tracks deployed commit lag, `staging` vs `production` branch drift with direct GitHub Compare links, and aggregates all open **Renovate PRs** across your repositories.
- **1-Click SSH Deployments with Live SSE Logs**: Executes `/srv/apps/<slug>/deploy.sh` with a PostgreSQL transactional lock (`SELECT FOR UPDATE`) and real-time Server-Sent Events log streaming.
- **Cron Supervision & Prometheus Export (`/metrics`)**: Evaluates UTC cron schedules (`cron-parser`) with overdue grace periods and exposes `sentinel_cron_*` gauges in Prometheus 0.0.4 format protected by a Bearer token.
- **Zero-Reload Maintenance Mode & Whitelisted Quick Terminal**: Instant `maintenance.on` toggling and strictly sandboxed SSH diagnostic commands.
- **Authentik Admin SSO + Direct Grafana Access**: Stateless Authentik OIDC (PKCE S256, encrypted `httpOnly` cookie, no local passwords) restricted to Authentik admin groups/emails, establishing your `*.nabster.dev` SSO session for seamless Grafana access.
- **Umami v2 Analytics & Grafana Embed**: 24h site metrics and theme-synced Grafana embeds.

---

## Quick Start

### Prerequisites
- Node.js **26** (`.nvmrc`)
- Docker & Docker Compose (for PostgreSQL 16 or full containerized dev)
- Access to GitHub Packages (`@nlabrazi:registry=https://npm.pkg.github.com/`)

### Local Development

```bash
cp .env.example .env
# Fill in VPS_HOST, GITHUB_TOKEN, SESSION_SECRET, AUTHENTIK_*, etc.

# Start PostgreSQL 16
docker compose up -d sentinel-db

# Install dependencies & apply Drizzle migrations
npm ci
npm run db:migrate

# Start Nuxt dev server (http://localhost:3000)
npm run dev
```

Or boot the entire stack with Docker Compose:

```bash
docker compose up --build
```

---

## Authentik OIDC & Direct Grafana SSO (No Re-Auth)

Sentinel uses **stateless Authentik OIDC** (no `users` table, no local passwords). Access is restricted via `AUTHENTIK_ALLOWED_GROUPS` (default: `authentik Admins`) and/or `AUTHENTIK_ALLOWED_EMAILS`.

1. In Authentik (`https://auth.nabster.dev`), point the Sentinel OIDC provider Redirect URI to:
   - Production: `https://sentinel.nabster.dev/auth/callback`
   - Local dev: `http://localhost:3000/auth/callback`
2. Ensure scopes include `openid profile email groups`.
3. To open or embed **Grafana** directly from Sentinel without logging in again (sharing the `*.nabster.dev` Authentik SSO session), configure `grafana.ini`:

```ini
[auth]
oauth_auto_login = true

[security]
allow_embedding = true
cookie_samesite = none
cookie_secure = true
```

> **Local dev / E2E bypass**: Set `AUTH_DEV_BYPASS=true` in `.env`. This flag is strictly ignored when `NODE_ENV=production`.

---

## VPS Operational Contracts

Every workload under `/srv/apps/<slug>` works with Sentinel through lightweight, stack-agnostic contracts:

### 1. Optional `sentinel.json` Manifest
Projects are discovered automatically without any config file. Adding `/srv/apps/<slug>/sentinel.json` lets a project declare rich metadata:

```json
{
  "name": "My App",
  "kind": "app",
  "production_url": "https://app.nabster.dev",
  "production_branch": "master",
  "staging_branch": "staging",
  "grafana_app_value": "https://app.nabster.dev",
  "cron_monitoring": true
}
```

### 2. Deployment Script (`/srv/apps/<slug>/deploy.sh`)
- Executable (`chmod +x deploy.sh`), strictly non-interactive.
- Returns exit code `0` on success, non-zero on failure.
- Streamed live to Sentinel over SSE and stored (truncated safely at 64 KB).

### 3. Cron Status Contract (`/srv/apps/<slug>/status.sh` or `sentinel/cron-status.json`)
Outputs JSON:

```json
{
  "version": 1,
  "jobs": [
    {
      "name": "daily-import",
      "command": "./bin/daily-import",
      "schedule": "0 2 * * *",
      "last_execution_at": "2026-11-21T02:00:12Z",
      "last_status": "success",
      "last_duration": 42,
      "last_log": "Completed successfully"
    }
  ]
}
```

*(Deprecated `cron_jobs` array and legacy object maps remain supported.)*

### 4. Prometheus Scrape Endpoint (`GET /metrics`)
Requires `Authorization: Bearer $PROMETHEUS_METRICS_TOKEN` (timing-safe check; never passed in query params):

```bash
curl --fail -H "Authorization: Bearer $PROMETHEUS_METRICS_TOKEN" \
  https://sentinel.nabster.dev/metrics
```

Exported gauges (prefix `sentinel_cron_`):
- `job_healthy`, `job_failed`, `job_overdue`, `job_last_execution_timestamp_seconds`, `job_last_duration_seconds`
- `project_last_sync_timestamp_seconds`, `project_sync_stale`, `project_healthy`

### 5. Zero-Reload Maintenance Mode
Sentinel creates or removes `/srv/apps/<slug>/maintenance.on` over SSH for instant Nginx `503` detection without reloading Nginx.

### 6. Quick Terminal Security Model
Enforced server-side in `server/services/quick-command.ts`:
- Whitelisted read-only/diagnostic binaries (`docker`, `docker-compose`, `git`, `cat`, `head`, `tail`, `grep`, `ls`, `df`, `free`, `ps`, `uptime`, etc.) and local `./*.sh` scripts.
- Rejects privilege escalation, destructive commands, interpreters, network tools, chaining (`;`, `&&`), redirections (`>`, `<`), command substitution (`$()`, backticks), path traversal (`..`), and secret files (`.env`, `*.key`, `*.pem`, `id_rsa`, `sentinel_control_panel`).
- Hard 10-second timeout and 64 KB output limit.

---

## Quality, Testing & CI

```bash
npm run check          # Biome lint + format (@nlabrazi/config-biome)
npm run typecheck      # Nuxt / Vue TypeScript strict check
npm test               # Vitest unit test suite (@nlabrazi/config-vitest)
npm run build          # Production Nuxt + Nitro build
npm run test:e2e       # Playwright E2E suite (@nlabrazi/config-playwright)
```

CI is driven by [Jenkinsfile](./Jenkinsfile) using the `nabster-ci` shared library (`npmCi`, `dockerBuildWithPackages`, `notifyTelegram`) and automated dependency updates via Renovate targeting `staging`.

---

## License

MIT — see [LICENSE](./LICENSE).
