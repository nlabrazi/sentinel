import type {
  BranchSyncStatus,
  CronStatus,
  DeploymentStatus,
  ProjectKind,
} from '#shared/types/sentinel'

export interface PullRequestDto {
  id: number
  projectId: number
  projectSlug?: string
  projectName?: string
  number: number
  title: string
  state: string
  isRenovate: boolean
  draft: boolean
  authorLogin: string | null
  headRef: string | null
  baseRef: string | null
  htmlUrl: string | null
  openedAt: string | null
  mergedAt: string | null
  githubUpdatedAt: string | null
}

export interface DeploymentDto {
  id: number
  projectId: number
  projectSlug?: string
  projectName?: string
  commitSha: string | null
  status: DeploymentStatus
  triggeredBy: string
  durationSeconds: number | null
  log: string
  createdAt: string
  updatedAt: string
}

export interface JobExecutionDto {
  id: number
  cronJobId: number
  status: CronStatus
  duration: number | null
  log: string
  executedAt: string
}

export interface CronJobDto {
  id: number
  projectId: number
  name: string
  command: string
  schedule: string
  lastStatus: CronStatus
  displayStatus: 'ok' | 'failed' | 'overdue' | 'never_run' | 'unknown'
  lastDuration: number | null
  lastExecutionAt: string | null
  executions: JobExecutionDto[]
}

export interface ProjectSummaryDto {
  id: number
  slug: string
  name: string
  kind: ProjectKind
  vpsPath: string
  repoUrl: string | null
  githubRepo: string | null
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
  latestCommitAvailable: string | null
  commitsBehind: number
  stagingCommitsAhead: number
  stagingCommitsBehind: number
  stagingSyncStatus: BranchSyncStatus
  githubCompareStagingUrl: string | null
  githubCompareDeployUrl: string | null
  umamiVisitors24h: number
  umamiPageviews24h: number
  umamiBounceRate: number
  umamiSyncError: string | null
  umamiSyncedAt: string | null
  screenshotUrl: string | null
  screenshotUpdatedAt: string | null
  vpsSyncedAt: string | null
  githubSyncedAt: string | null
  cronSyncedAt: string | null
  openPrsCount: number
  openRenovatePrsCount: number
  hasRunningDeployment: boolean
  cronSummaryStatus:
    | 'disabled'
    | 'ok'
    | 'failed'
    | 'overdue'
    | 'never_run'
    | 'not_reported'
    | 'unknown'
}

export interface ProjectDetailDto extends ProjectSummaryDto {
  deployments: DeploymentDto[]
  runningDeployment: DeploymentDto | null
  cronJobs: CronJobDto[]
  pullRequests: PullRequestDto[]
  grafanaEmbedUrl: string | null
  grafanaDirectUrl: string | null
}

export interface ProjectsDashboardResponse {
  projects: ProjectSummaryDto[]
  openPullRequests: PullRequestDto[]
  kpis: {
    totalProjects: number
    deployPendingCount: number
    openRenovatePrsCount: number
    openPrsCount: number
    maintenanceCount: number
    cronAlertsCount: number
  }
}

export interface VpsScanResponseDto {
  discoveredCount: number
  createdSlugs: string[]
  updatedSlugs: string[]
  missingOnVpsSlugs: string[]
  warnings: string[]
}
