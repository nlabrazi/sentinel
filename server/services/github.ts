import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { githubPullRequests, type ProjectRow, projects } from '#server/db/schema'
import { getEnv } from '#server/utils/env'
import { extractGithubRepo, isValidHttpUrl } from '#shared/schemas/project'
import type { CiStatus } from '#shared/types/sentinel'

const GITHUB_API_BASE = 'https://api.github.com'

export interface GithubCiSummary {
  status: CiStatus
  url: string | null
}

export interface GithubCommitSummary {
  sha: string
  message: string
  date: string | null
  htmlUrl: string | null
}

export interface GithubCompareResult {
  aheadBy: number
  behindBy: number
  status: 'identical' | 'ahead' | 'behind' | 'diverged'
  htmlUrl: string | null
}

export interface NormalizedPullRequest {
  number: number
  title: string
  state: 'open' | 'merged' | 'closed'
  isRenovate: boolean
  draft: boolean
  authorLogin: string | null
  headRef: string | null
  baseRef: string | null
  htmlUrl: string | null
  openedAt: Date | null
  closedAt: Date | null
  mergedAt: Date | null
  githubUpdatedAt: Date | null
}

export interface GithubSyncOptions {
  token?: string
  fetchImpl?: typeof fetch
}

export function isRenovatePullRequest(
  authorLogin: string | null | undefined,
  headRef: string | null | undefined,
): boolean {
  const login = (authorLogin ?? '').trim().toLowerCase()
  const branch = (headRef ?? '').trim().toLowerCase()
  return (
    login === 'renovate[bot]' ||
    login === 'renovate' ||
    login === 'renovate-bot' ||
    login === 'app/renovate' ||
    branch.startsWith('renovate/')
  )
}

function buildGithubHeaders(token: string): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'Sentinel-Control-Plane/2.0',
    'X-GitHub-Api-Version': '2022-11-28',
  }
  if (token) {
    headers.Authorization = `Bearer ${token}`
  }
  return headers
}

async function githubGetJson<T>(
  endpoint: string,
  token: string,
  fetchImpl: typeof fetch = fetch,
): Promise<T | null> {
  const response = await fetchImpl(`${GITHUB_API_BASE}${endpoint}`, {
    headers: buildGithubHeaders(token),
    signal: AbortSignal.timeout(15_000),
  })
  if (!response.ok) {
    console.warn(`[sentinel:github] GET ${endpoint} failed (${response.status})`)
    return null
  }
  return (await response.json()) as T
}

export interface GithubRepoMetadata {
  homepage: string | null
  defaultBranch: string | null
}

export function normalizeHomepageUrl(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? '').trim()
  if (!trimmed) {
    return null
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed) && !/^https?:\/\//i.test(trimmed)) {
    return null
  }
  const candidate = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
  return isValidHttpUrl(candidate) ? candidate.replace(/\/+$/, '') : null
}

export async function fetchRepoMetadata(
  repo: string,
  options: GithubSyncOptions = {},
): Promise<GithubRepoMetadata | null> {
  const token = options.token ?? getEnv().githubToken
  const fetchImpl = options.fetchImpl ?? fetch

  const data = await githubGetJson<{
    homepage?: string | null
    default_branch?: string | null
  }>(`/repos/${repo}`, token, fetchImpl)

  if (!data) {
    return null
  }

  return {
    homepage: normalizeHomepageUrl(data.homepage),
    defaultBranch: data.default_branch?.trim() || null,
  }
}

export async function fetchLatestBranchCommit(
  repo: string,
  branch: string,
  options: GithubSyncOptions = {},
): Promise<GithubCommitSummary | null> {
  const token = options.token ?? getEnv().githubToken
  const fetchImpl = options.fetchImpl ?? fetch

  const data = await githubGetJson<{
    sha?: string
    html_url?: string
    commit?: { message?: string; committer?: { date?: string } }
  }>(`/repos/${repo}/commits/${encodeURIComponent(branch)}`, token, fetchImpl)

  if (!data?.sha) {
    return null
  }

  return {
    sha: data.sha,
    message: (data.commit?.message ?? '').split('\n')[0]?.trim() ?? '',
    date: data.commit?.committer?.date ?? null,
    htmlUrl: data.html_url ?? null,
  }
}

interface RawCompareResponse {
  ahead_by?: number
  behind_by?: number
  html_url?: string
  base_commit?: {
    sha?: string
    commit?: { tree?: { sha?: string } }
    parents?: Array<{ sha?: string }>
  }
  merge_base_commit?: {
    sha?: string
    commit?: { tree?: { sha?: string } }
  }
}

export function computeEffectiveBehindBy(comparison: RawCompareResponse): number {
  const rawBehind = comparison.behind_by ?? 0
  if (rawBehind <= 0) {
    return 0
  }

  const mergeBaseSha = comparison.merge_base_commit?.sha
  const baseCommitSha = comparison.base_commit?.sha
  if (!mergeBaseSha || !baseCommitSha) {
    return rawBehind
  }

  if (baseCommitSha === mergeBaseSha) {
    return 0
  }

  if ((comparison.ahead_by ?? 0) === 0) {
    const baseTree = comparison.base_commit?.commit?.tree?.sha
    const mergeBaseTree = comparison.merge_base_commit?.commit?.tree?.sha
    if (baseTree && baseTree === mergeBaseTree) {
      return 0
    }
  }

  const baseParents = (comparison.base_commit?.parents ?? [])
    .map((parent) => parent.sha)
    .filter((sha): sha is string => Boolean(sha))
  if (baseParents.includes(mergeBaseSha)) {
    return 0
  }

  return rawBehind
}

export async function compareGithubRefs(
  repo: string,
  base: string,
  head: string,
  options: GithubSyncOptions = {},
): Promise<GithubCompareResult | null> {
  const token = options.token ?? getEnv().githubToken
  const fetchImpl = options.fetchImpl ?? fetch

  const data = await githubGetJson<RawCompareResponse>(
    `/repos/${repo}/compare/${encodeURIComponent(base)}...${encodeURIComponent(head)}`,
    token,
    fetchImpl,
  )

  if (!data) {
    return null
  }

  const aheadBy = data.ahead_by ?? 0
  const behindBy = computeEffectiveBehindBy(data)

  let status: GithubCompareResult['status'] = 'identical'
  if (aheadBy > 0 && behindBy === 0) {
    status = 'ahead'
  } else if (aheadBy === 0 && behindBy > 0) {
    status = 'behind'
  } else if (aheadBy > 0 && behindBy > 0) {
    status = 'diverged'
  }

  return {
    aheadBy,
    behindBy,
    status,
    htmlUrl: data.html_url ?? null,
  }
}

interface RawPullRequest {
  number: number
  title: string
  state: string
  draft?: boolean
  user?: { login?: string } | null
  head?: { ref?: string } | null
  base?: { ref?: string } | null
  html_url?: string
  created_at?: string | null
  closed_at?: string | null
  merged_at?: string | null
  updated_at?: string | null
}

function parseOptionalDate(value: string | null | undefined): Date | null {
  if (!value) {
    return null
  }
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

export async function fetchRecentPullRequests(
  repo: string,
  limit = 25,
  options: GithubSyncOptions = {},
): Promise<NormalizedPullRequest[]> {
  const token = options.token ?? getEnv().githubToken
  const fetchImpl = options.fetchImpl ?? fetch

  const data = await githubGetJson<RawPullRequest[]>(
    `/repos/${repo}/pulls?state=all&sort=updated&direction=desc&per_page=${limit}`,
    token,
    fetchImpl,
  )

  if (!Array.isArray(data)) {
    return []
  }

  return data.map((pr) => {
    const authorLogin = pr.user?.login ?? null
    const headRef = pr.head?.ref ?? null
    const state: NormalizedPullRequest['state'] = pr.merged_at
      ? 'merged'
      : pr.state === 'open'
        ? 'open'
        : 'closed'

    return {
      number: pr.number,
      title: pr.title,
      state,
      isRenovate: isRenovatePullRequest(authorLogin, headRef),
      draft: Boolean(pr.draft),
      authorLogin,
      headRef,
      baseRef: pr.base?.ref ?? null,
      htmlUrl: pr.html_url ?? null,
      openedAt: parseOptionalDate(pr.created_at),
      closedAt: parseOptionalDate(pr.closed_at),
      mergedAt: parseOptionalDate(pr.merged_at),
      githubUpdatedAt: parseOptionalDate(pr.updated_at),
    }
  })
}

export interface RawCommitStatus {
  context?: string | null
  state?: string | null
  target_url?: string | null
}

export interface RawCheckRun {
  name?: string | null
  status?: string | null
  conclusion?: string | null
  html_url?: string | null
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function normalizeOptionalHttpUrl(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? '').trim()
  return trimmed && isValidHttpUrl(trimmed) ? trimmed : null
}

function matchesJenkinsBranchUrl(url: string | null | undefined, branch: string): boolean {
  if (!url || !branch) {
    return false
  }
  const rawBranch = escapeRegExp(branch)
  const encodedBranch = escapeRegExp(encodeURIComponent(branch))
  const pattern = new RegExp(`/job/(?:${rawBranch}|${encodedBranch})/`, 'i')
  return pattern.test(url)
}

function mapGithubStatusState(state: string | null | undefined): CiStatus | null {
  const normalized = (state ?? '').trim().toLowerCase()
  if (normalized === 'failure' || normalized === 'error') {
    return 'failed'
  }
  if (normalized === 'pending') {
    return 'pending'
  }
  if (normalized === 'success') {
    return 'success'
  }
  return null
}

function mapCheckRunState(run: RawCheckRun): CiStatus | null {
  const status = (run.status ?? '').trim().toLowerCase()
  if (status && status !== 'completed') {
    return 'pending'
  }
  const conclusion = (run.conclusion ?? '').trim().toLowerCase()
  if (!conclusion || conclusion === 'neutral' || conclusion === 'skipped') {
    return null
  }
  if (conclusion === 'success') {
    return 'success'
  }
  return 'failed'
}

export function resolveCommitCiSummary(params: {
  productionBranch: string
  statuses: RawCommitStatus[]
  checkRuns: RawCheckRun[]
}): GithubCiSummary {
  const effectiveStatuses = new Map<string, { status: CiStatus; url: string | null }>()
  const branchMatchedContexts = new Set<string>()

  // GitHub returns /statuses newest-first. Prefer the newest status whose Jenkins URL targets
  // the production branch so a sibling staging build on the same SHA cannot mask master CI.
  for (const item of params.statuses) {
    const context = (item.context ?? '').trim() || 'default'
    const mapped = mapGithubStatusState(item.state)
    if (!mapped) {
      continue
    }
    if (matchesJenkinsBranchUrl(item.target_url, params.productionBranch)) {
      if (!branchMatchedContexts.has(context)) {
        branchMatchedContexts.add(context)
        effectiveStatuses.set(context, {
          status: mapped,
          url: normalizeOptionalHttpUrl(item.target_url),
        })
      }
    }
  }

  for (const item of params.statuses) {
    const context = (item.context ?? '').trim() || 'default'
    if (effectiveStatuses.has(context)) {
      continue
    }
    const mapped = mapGithubStatusState(item.state)
    if (!mapped) {
      continue
    }
    effectiveStatuses.set(context, {
      status: mapped,
      url: normalizeOptionalHttpUrl(item.target_url),
    })
  }

  const evaluations: Array<{ status: CiStatus; url: string | null }> = [
    ...effectiveStatuses.values(),
  ]

  for (const run of params.checkRuns) {
    const mapped = mapCheckRunState(run)
    if (!mapped) {
      continue
    }
    evaluations.push({
      status: mapped,
      url: normalizeOptionalHttpUrl(run.html_url),
    })
  }

  const failed = evaluations.find((entry) => entry.status === 'failed')
  if (failed) {
    return failed
  }

  const pending = evaluations.find((entry) => entry.status === 'pending')
  if (pending) {
    return pending
  }

  const success = evaluations.find((entry) => entry.status === 'success')
  if (success) {
    return success
  }

  return { status: 'unknown', url: null }
}

export async function fetchCommitCiStatus(
  repo: string,
  sha: string,
  productionBranch: string,
  options: GithubSyncOptions = {},
): Promise<GithubCiSummary | null> {
  const token = options.token ?? getEnv().githubToken
  const fetchImpl = options.fetchImpl ?? fetch
  const encodedSha = encodeURIComponent(sha)

  const [statusesData, checkRunsData] = await Promise.all([
    githubGetJson<RawCommitStatus[]>(
      `/repos/${repo}/commits/${encodedSha}/statuses?per_page=30`,
      token,
      fetchImpl,
    ),
    githubGetJson<{ check_runs?: RawCheckRun[] }>(
      `/repos/${repo}/commits/${encodedSha}/check-runs?per_page=30`,
      token,
      fetchImpl,
    ),
  ])

  if (!Array.isArray(statusesData) && !checkRunsData) {
    return null
  }

  return resolveCommitCiSummary({
    productionBranch,
    statuses: Array.isArray(statusesData) ? statusesData : [],
    checkRuns: Array.isArray(checkRunsData?.check_runs) ? checkRunsData.check_runs : [],
  })
}

export async function syncProjectGithub(
  db: SentinelDb,
  project: ProjectRow,
  options: GithubSyncOptions = {},
): Promise<{ synced: boolean; pullRequestsSynced: number; renovateOpenCount: number }> {
  const repo = extractGithubRepo(project.repoUrl)
  if (!repo) {
    return { synced: false, pullRequestsSynced: 0, renovateOpenCount: 0 }
  }

  const latestCommit = await fetchLatestBranchCommit(repo, project.productionBranch, options)

  let commitsBehind = project.commitsBehind
  if (latestCommit && project.lastCommitDeployed) {
    if (latestCommit.sha === project.lastCommitDeployed) {
      commitsBehind = 0
    } else {
      const deployComparison = await compareGithubRefs(
        repo,
        project.lastCommitDeployed,
        project.productionBranch,
        options,
      )
      if (deployComparison) {
        commitsBehind = deployComparison.aheadBy
      }
    }
  }

  let productionCiStatus: CiStatus = project.productionCiStatus ?? 'unknown'
  let productionCiUrl: string | null = project.productionCiUrl ?? null
  if (latestCommit?.sha) {
    const ciSummary = await fetchCommitCiStatus(
      repo,
      latestCommit.sha,
      project.productionBranch,
      options,
    )
    if (ciSummary) {
      productionCiStatus = ciSummary.status
      productionCiUrl = ciSummary.url
    }
  }

  let stagingAhead = 0
  let stagingBehind = 0
  if (project.stagingBranch) {
    const branchComparison = await compareGithubRefs(
      repo,
      project.productionBranch,
      project.stagingBranch,
      options,
    )
    if (branchComparison) {
      stagingAhead = branchComparison.aheadBy
      stagingBehind = branchComparison.behindBy
    }
  }

  let resolvedProductionUrl = project.productionUrl
  let resolvedGrafanaAppValue = project.grafanaAppValue
  if (!resolvedProductionUrl || !resolvedGrafanaAppValue) {
    const meta = await fetchRepoMetadata(repo, options)
    if (!resolvedProductionUrl && meta?.homepage) {
      resolvedProductionUrl = meta.homepage
    }
    if (!resolvedGrafanaAppValue && resolvedProductionUrl) {
      resolvedGrafanaAppValue = resolvedProductionUrl
    }
  }

  const pullRequests = await fetchRecentPullRequests(repo, 25, options)
  const now = new Date()

  for (const pr of pullRequests) {
    await db
      .insert(githubPullRequests)
      .values({
        projectId: project.id,
        number: pr.number,
        title: pr.title,
        state: pr.state,
        isRenovate: pr.isRenovate,
        draft: pr.draft,
        authorLogin: pr.authorLogin,
        headRef: pr.headRef,
        baseRef: pr.baseRef,
        htmlUrl: pr.htmlUrl,
        openedAt: pr.openedAt,
        closedAt: pr.closedAt,
        mergedAt: pr.mergedAt,
        githubUpdatedAt: pr.githubUpdatedAt,
        updatedAt: now,
      })
      .onConflictDoUpdate({
        target: [githubPullRequests.projectId, githubPullRequests.number],
        set: {
          title: pr.title,
          state: pr.state,
          isRenovate: pr.isRenovate,
          draft: pr.draft,
          authorLogin: pr.authorLogin,
          headRef: pr.headRef,
          baseRef: pr.baseRef,
          htmlUrl: pr.htmlUrl,
          closedAt: pr.closedAt,
          mergedAt: pr.mergedAt,
          githubUpdatedAt: pr.githubUpdatedAt,
          updatedAt: now,
        },
      })
  }

  await db
    .update(projects)
    .set({
      productionUrl: resolvedProductionUrl,
      grafanaAppValue: resolvedGrafanaAppValue,
      latestCommitAvailable: latestCommit?.sha ?? project.latestCommitAvailable,
      commitsBehind,
      productionCiStatus,
      productionCiUrl,
      stagingCommitsAhead: stagingAhead,
      stagingCommitsBehind: stagingBehind,
      githubSyncedAt: now,
      updatedAt: now,
    })
    .where(eq(projects.id, project.id))

  return {
    synced: true,
    pullRequestsSynced: pullRequests.length,
    renovateOpenCount: pullRequests.filter((pr) => pr.state === 'open' && pr.isRenovate).length,
  }
}

export async function syncAllProjectsGithub(
  db: SentinelDb,
  options: GithubSyncOptions = {},
): Promise<{ syncedCount: number; failedSlugs: string[] }> {
  const allProjects = await db.select().from(projects)
  let syncedCount = 0
  const failedSlugs: string[] = []

  for (const project of allProjects) {
    if (!project.repoUrl) {
      continue
    }
    try {
      const result = await syncProjectGithub(db, project, options)
      if (result.synced) {
        syncedCount += 1
      }
    } catch (error) {
      console.error(`[sentinel:github] Sync failed for ${project.slug}:`, error)
      failedSlugs.push(project.slug)
    }
  }

  return { syncedCount, failedSlugs }
}
