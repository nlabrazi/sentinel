import { z } from 'zod'
import { type BranchSyncStatus, type CiStatus, PROJECT_KINDS } from '#shared/types/sentinel'

export const DEFAULT_VPS_ROOT = '/srv/apps'
const SAFE_PATH_SEGMENT = /^[A-Za-z0-9._-]+$/
const GITHUB_HTTPS_PATH = /^\/[A-Za-z0-9-]+\/[A-Za-z0-9._-]+(?:\.git)?$/

export function isSafeVpsPath(value: string, root = DEFAULT_VPS_ROOT): boolean {
  const normalizedRoot = root.replace(/\/+$/, '')
  if (!value.startsWith(`${normalizedRoot}/`)) {
    return false
  }
  if (value.includes('..') || value.includes('//')) {
    return false
  }
  const relative = value.slice(normalizedRoot.length + 1)
  if (!relative) {
    return false
  }
  return relative.split('/').every((segment) => SAFE_PATH_SEGMENT.test(segment))
}

export function normalizeGithubRepoUrl(rawUrl: string | null | undefined): string | null {
  if (!rawUrl) {
    return null
  }
  const trimmed = rawUrl.trim()
  if (!trimmed) {
    return null
  }

  const sshMatch = trimmed.match(
    /^git@github(?:[.-][A-Za-z0-9._-]+)?:([A-Za-z0-9-]+\/[A-Za-z0-9._-]+?)(?:\.git)?$/,
  )
  if (sshMatch?.[1]) {
    return `https://github.com/${sshMatch[1]}.git`
  }

  try {
    const uri = new URL(trimmed)
    if (
      uri.protocol === 'https:' &&
      uri.hostname === 'github.com' &&
      !uri.username &&
      !uri.password &&
      GITHUB_HTTPS_PATH.test(uri.pathname)
    ) {
      return trimmed
    }
  } catch {
    return null
  }

  return null
}

export function extractGithubRepo(repoUrl: string | null | undefined): string | null {
  const normalized = normalizeGithubRepoUrl(repoUrl)
  if (!normalized) {
    return null
  }
  const uri = new URL(normalized)
  return uri.pathname.replace(/^\//, '').replace(/\.git$/, '')
}

export function isValidHttpUrl(value: string): boolean {
  try {
    const uri = new URL(value)
    return (
      (uri.protocol === 'http:' || uri.protocol === 'https:') &&
      Boolean(uri.hostname) &&
      !uri.username &&
      !uri.password
    )
  } catch {
    return false
  }
}

export function computeStagingSyncStatus(
  stagingBranch: string | null | undefined,
  ahead: number,
  behind: number,
): BranchSyncStatus {
  if (!stagingBranch) {
    return 'not_configured'
  }
  if (ahead <= 0 && behind <= 0) {
    return 'synced'
  }
  if (ahead > 0 && behind <= 0) {
    return 'ahead'
  }
  if (ahead <= 0 && behind > 0) {
    return 'behind'
  }
  return 'diverged'
}

export function buildGithubCompareStagingUrl(
  repoUrl: string | null | undefined,
  productionBranch: string,
  stagingBranch: string | null | undefined,
): string | null {
  const repo = extractGithubRepo(repoUrl)
  if (!repo || !stagingBranch) {
    return null
  }
  return `https://github.com/${repo}/compare/${encodeURIComponent(productionBranch)}...${encodeURIComponent(stagingBranch)}`
}

export function buildGithubCompareDeployUrl(
  repoUrl: string | null | undefined,
  lastCommitDeployed: string | null | undefined,
  productionBranch: string,
): string | null {
  const repo = extractGithubRepo(repoUrl)
  if (!repo || !lastCommitDeployed) {
    return null
  }
  return `https://github.com/${repo}/compare/${encodeURIComponent(lastCommitDeployed)}...${encodeURIComponent(productionBranch)}`
}

export function isProjectDeployReady(
  commitsBehind: number,
  productionCiStatus: CiStatus | null | undefined = 'unknown',
): boolean {
  return commitsBehind > 0 && productionCiStatus !== 'failed' && productionCiStatus !== 'pending'
}

export function matchesCommitSha(
  left: string | null | undefined,
  right: string | null | undefined,
): boolean {
  const a = (left ?? '').trim().toLowerCase()
  const b = (right ?? '').trim().toLowerCase()
  if (!a || !b) {
    return false
  }
  if (a === b) {
    return true
  }
  if (a.length >= 7 && b.length >= 7) {
    return a.startsWith(b) || b.startsWith(a)
  }
  return false
}

const optionalNullableString = z
  .string()
  .trim()
  .transform((value) => (value === '' ? null : value))
  .nullable()
  .optional()

export const sentinelManifestSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  kind: z.enum(PROJECT_KINDS).optional(),
  production_url: z
    .string()
    .trim()
    .refine(isValidHttpUrl, 'Must be a valid HTTP/HTTPS URL')
    .nullable()
    .optional(),
  production_branch: z.string().trim().min(1).max(100).optional(),
  staging_branch: z.string().trim().max(100).nullable().optional(),
  grafana_app_value: z.string().trim().max(255).nullable().optional(),
  umami_website_id: z.string().trim().max(120).nullable().optional(),
  cron_monitoring: z.boolean().optional(),
})

export type SentinelManifest = z.infer<typeof sentinelManifestSchema>

export const projectUpdateSchema = z.object({
  name: z.string().trim().min(1).max(120).optional(),
  kind: z.enum(PROJECT_KINDS).optional(),
  repoUrl: optionalNullableString.refine(
    (value) => value === undefined || value === null || normalizeGithubRepoUrl(value) !== null,
    'Must be a valid GitHub HTTPS repository URL',
  ),
  productionBranch: z.string().trim().min(1).max(100).optional(),
  stagingBranch: optionalNullableString,
  productionUrl: optionalNullableString.refine(
    (value) => value === undefined || value === null || isValidHttpUrl(value),
    'Must be a valid HTTP or HTTPS URL',
  ),
  grafanaAppValue: optionalNullableString,
  umamiWebsiteId: optionalNullableString,
  cronMonitoringEnabled: z.boolean().optional(),
})

export type ProjectUpdateInput = z.infer<typeof projectUpdateSchema>
