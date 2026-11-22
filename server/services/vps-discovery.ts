import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { projects } from '#server/db/schema'
import {
  defaultSshExecutor,
  type SshExecutor,
  shellEscape,
  wrapBashCommand,
} from '#server/services/ssh'
import { getEnv } from '#server/utils/env'
import {
  DEFAULT_VPS_ROOT,
  isSafeVpsPath,
  normalizeGithubRepoUrl,
  type SentinelManifest,
  sentinelManifestSchema,
} from '#shared/schemas/project'
import type { ProjectKind } from '#shared/types/sentinel'

export interface DiscoveredVpsProject {
  slug: string
  name: string
  kind: ProjectKind
  vpsPath: string
  repoUrl: string | null
  productionBranch: string
  stagingBranch: string | null
  productionUrl: string | null
  grafanaAppValue: string | null
  umamiWebsiteId: string | null
  hasDeployScript: boolean
  hasStatusScript: boolean
  cronMonitoringEnabled: boolean
  maintenanceMode: boolean
  lastCommitDeployed: string | null
  manifest: SentinelManifest | null
}

export interface VpsDiscoverySummary {
  discoveredCount: number
  createdSlugs: string[]
  updatedSlugs: string[]
  missingOnVpsSlugs: string[]
  warnings: string[]
}

const FIELD_SEP = '\t'

export function humanizeSlug(slug: string): string {
  return slug
    .split(/[-_]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

export function buildVpsDiscoveryCommand(appsRoot = DEFAULT_VPS_ROOT): string {
  const escapedRoot = shellEscape(appsRoot)
  const script = [
    `ROOT=${escapedRoot}`,
    'if [ ! -d "$ROOT" ]; then exit 0; fi',
    'for dir in "$ROOT"/*; do',
    '  [ -d "$dir" ] || continue',
    '  slug="$(basename "$dir")"',
    '  case "$slug" in .*) continue ;; esac',
    '  gitdir="$dir"',
    '  [ -d "$dir/repo/.git" ] && gitdir="$dir/repo"',
    '  repo="$(git -c safe.directory="*" -C "$gitdir" remote get-url origin 2>/dev/null || true)"',
    '  branch="$(git -c safe.directory="*" -C "$gitdir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"',
    '  sha="$(git -c safe.directory="*" -C "$gitdir" rev-parse HEAD 2>/dev/null || true)"',
    '  if command -v docker >/dev/null 2>&1; then',
    '    oci_rev=""; oci_src=""',
    '    for cid in $(docker ps -q --filter "label=com.docker.compose.project=$slug" 2>/dev/null || true); do',
    '      [ -n "$cid" ] || continue',
    '      img="$(docker inspect --format \'{{.Config.Image}}\' "$cid" 2>/dev/null || true)"',
    '      case "$img" in ghcr.io/*) ;; *) continue ;; esac',
    '      rev="$(docker inspect --format \'{{index .Config.Labels "org.opencontainers.image.revision"}}\' "$cid" 2>/dev/null || true)"',
    '      src="$(docker inspect --format \'{{index .Config.Labels "org.opencontainers.image.source"}}\' "$cid" 2>/dev/null || true)"',
    '      if [ -z "$oci_rev" ] && [ -n "$rev" ] && [ "$rev" != "<no value>" ]; then oci_rev="$rev"; fi',
    '      if [ -z "$oci_src" ] && [ -n "$src" ] && [ "$src" != "<no value>" ]; then oci_src="$src"; fi',
    '    done',
    '    [ -n "$oci_rev" ] && sha="$oci_rev"',
    '    [ -z "$repo" ] && [ -n "$oci_src" ] && repo="$oci_src"',
    '  fi',
    '  has_deploy=0; [ -x "$dir/deploy.sh" ] && has_deploy=1',
    '  has_status=0; ([ -x "$dir/status.sh" ] || [ -f "$dir/sentinel/cron-status.json" ]) && has_status=1',
    '  maint=0; [ -f "$dir/maintenance.on" ] && maint=1',
    '  manifest=""',
    '  if [ -f "$dir/sentinel.json" ]; then manifest="$(base64 "$dir/sentinel.json" 2>/dev/null | tr -d "\\n\\r" || true)"; elif [ -f "$dir/repo/sentinel.json" ]; then manifest="$(base64 "$dir/repo/sentinel.json" 2>/dev/null | tr -d "\\n\\r" || true)"; fi',
    '  printf "%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n" "$slug" "$dir" "$repo" "$branch" "$sha" "$has_deploy" "$has_status" "$maint" "$manifest"',
    'done',
  ].join('\n')

  return wrapBashCommand(script)
}

export function parseDiscoveryOutput(
  stdout: string,
  appsRoot = DEFAULT_VPS_ROOT,
): { projects: DiscoveredVpsProject[]; warnings: string[] } {
  const discovered: DiscoveredVpsProject[] = []
  const warnings: string[] = []

  for (const rawLine of stdout.split(/\r?\n/)) {
    const line = rawLine.trimEnd()
    if (!line) {
      continue
    }

    const parts = line.split(FIELD_SEP)
    if (parts.length < 8) {
      warnings.push(`Malformed VPS discovery line skipped: ${line.slice(0, 80)}`)
      continue
    }

    const [
      slug = '',
      vpsPath = '',
      rawRepo = '',
      rawBranch = '',
      rawSha = '',
      hasDeployRaw = '0',
      hasStatusRaw = '0',
      maintRaw = '0',
      manifestB64 = '',
    ] = parts

    if (!slug || !isSafeVpsPath(vpsPath, appsRoot)) {
      warnings.push(`Skipped unsafe VPS path: ${vpsPath || slug}`)
      continue
    }

    let manifest: SentinelManifest | null = null
    if (manifestB64) {
      try {
        const decoded = Buffer.from(manifestB64, 'base64').toString('utf8')
        const parsedJson = JSON.parse(decoded) as unknown
        const parsed = sentinelManifestSchema.safeParse(parsedJson)
        if (parsed.success) {
          manifest = parsed.data
        } else {
          warnings.push(`Invalid sentinel.json in ${slug}: ${parsed.error.issues[0]?.message}`)
        }
      } catch {
        warnings.push(`Unable to parse sentinel.json in ${slug}`)
      }
    }

    const hasDeployScript = hasDeployRaw === '1'
    const hasStatusScript = hasStatusRaw === '1'
    const maintenanceMode = maintRaw === '1'

    const repoUrl = normalizeGithubRepoUrl(rawRepo)
    const gitBranch =
      rawBranch && rawBranch !== 'HEAD' && rawBranch !== 'unknown' ? rawBranch : null
    const productionBranch = manifest?.production_branch ?? gitBranch ?? 'master'
    const lastCommitDeployed = /^[0-9a-f]{7,40}$/i.test(rawSha) ? rawSha : null

    const inferredKind: ProjectKind =
      manifest?.kind ??
      (!repoUrl && !hasDeployScript
        ? 'service'
        : hasStatusScript && !manifest?.production_url && !hasDeployScript
          ? 'cron'
          : 'app')

    discovered.push({
      slug,
      name: manifest?.name ?? humanizeSlug(slug),
      kind: inferredKind,
      vpsPath,
      repoUrl,
      productionBranch,
      stagingBranch: manifest?.staging_branch !== undefined ? manifest.staging_branch : 'staging',
      productionUrl: manifest?.production_url ?? null,
      grafanaAppValue: manifest?.grafana_app_value ?? null,
      umamiWebsiteId: manifest?.umami_website_id ?? null,
      hasDeployScript,
      hasStatusScript,
      cronMonitoringEnabled: manifest?.cron_monitoring ?? hasStatusScript,
      maintenanceMode,
      lastCommitDeployed,
      manifest,
    })
  }

  return { projects: discovered, warnings }
}

export async function discoverVpsProjects(
  db: SentinelDb,
  ssh: SshExecutor = defaultSshExecutor,
  appsRoot = getEnv().vps.appsRoot,
): Promise<VpsDiscoverySummary> {
  const command = buildVpsDiscoveryCommand(appsRoot)
  const result = await ssh.execute(command, { timeoutSeconds: 30 })

  if (result.exitCode !== 0) {
    throw new Error(result.stderr.trim() || `VPS scan failed with exit code ${result.exitCode}`)
  }

  const { projects: scanned, warnings } = parseDiscoveryOutput(result.stdout, appsRoot)
  const existingRows = await db.select().from(projects)
  const existingBySlug = new Map(existingRows.map((row) => [row.slug, row]))
  const scannedSlugs = new Set<string>()

  const createdSlugs: string[] = []
  const updatedSlugs: string[] = []
  const now = new Date()

  for (const item of scanned) {
    scannedSlugs.add(item.slug)
    const existing = existingBySlug.get(item.slug)

    if (!existing) {
      await db.insert(projects).values({
        slug: item.slug,
        name: item.name,
        kind: item.kind,
        vpsPath: item.vpsPath,
        repoUrl: item.repoUrl,
        productionBranch: item.productionBranch,
        stagingBranch: item.stagingBranch,
        productionUrl: item.productionUrl,
        grafanaAppValue: item.grafanaAppValue,
        umamiWebsiteId: item.umamiWebsiteId,
        hasDeployScript: item.hasDeployScript,
        hasStatusScript: item.hasStatusScript,
        cronMonitoringEnabled: item.cronMonitoringEnabled,
        maintenanceMode: item.maintenanceMode,
        lastCommitDeployed: item.lastCommitDeployed,
        vpsSyncedAt: now,
        updatedAt: now,
      })
      createdSlugs.push(item.slug)
      continue
    }

    await db
      .update(projects)
      .set({
        vpsPath: item.vpsPath,
        name: item.manifest?.name ?? existing.name,
        kind: item.manifest?.kind ?? existing.kind,
        repoUrl: item.repoUrl ?? existing.repoUrl,
        productionBranch: item.manifest?.production_branch ?? existing.productionBranch,
        stagingBranch:
          item.manifest?.staging_branch !== undefined
            ? item.manifest.staging_branch
            : existing.stagingBranch,
        productionUrl:
          item.manifest?.production_url !== undefined
            ? item.manifest.production_url
            : existing.productionUrl,
        grafanaAppValue:
          item.manifest?.grafana_app_value !== undefined
            ? item.manifest.grafana_app_value
            : existing.grafanaAppValue,
        umamiWebsiteId:
          item.manifest?.umami_website_id !== undefined
            ? item.manifest.umami_website_id
            : existing.umamiWebsiteId,
        hasDeployScript: item.hasDeployScript,
        hasStatusScript: item.hasStatusScript,
        cronMonitoringEnabled:
          item.manifest?.cron_monitoring !== undefined
            ? item.manifest.cron_monitoring
            : existing.cronMonitoringEnabled || item.hasStatusScript,
        maintenanceMode: item.maintenanceMode,
        lastCommitDeployed: item.lastCommitDeployed ?? existing.lastCommitDeployed,
        vpsSyncedAt: now,
        updatedAt: now,
      })
      .where(eq(projects.id, existing.id))

    updatedSlugs.push(item.slug)
  }

  const missingOnVpsSlugs = existingRows
    .filter((row) => !scannedSlugs.has(row.slug))
    .map((row) => row.slug)

  return {
    discoveredCount: scanned.length,
    createdSlugs,
    updatedSlugs,
    missingOnVpsSlugs,
    warnings,
  }
}
