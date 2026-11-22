export const PROJECT_KINDS = ['app', 'service', 'cron'] as const
export type ProjectKind = (typeof PROJECT_KINDS)[number]

export const DEPLOYMENT_STATUSES = ['running', 'success', 'failed'] as const
export type DeploymentStatus = (typeof DEPLOYMENT_STATUSES)[number]

export const CRON_STATUSES = ['success', 'failed', 'unknown'] as const
export type CronStatus = (typeof CRON_STATUSES)[number]

export const BRANCH_SYNC_STATUSES = [
  'not_configured',
  'synced',
  'ahead',
  'behind',
  'diverged',
] as const
export type BranchSyncStatus = (typeof BRANCH_SYNC_STATUSES)[number]
