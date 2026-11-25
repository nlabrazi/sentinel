import {
  boolean,
  index,
  integer,
  pgTable,
  serial,
  text,
  timestamp,
  uniqueIndex,
} from 'drizzle-orm/pg-core'
import type {
  CiStatus,
  CronStatus,
  DeploymentStatus,
  ProjectKind,
} from '../../shared/types/sentinel'

export const projects = pgTable(
  'projects',
  {
    id: serial('id').primaryKey(),
    slug: text('slug').notNull(),
    name: text('name').notNull(),
    kind: text('kind').$type<ProjectKind>().notNull().default('app'),
    vpsPath: text('vps_path').notNull(),
    repoUrl: text('repo_url'),
    productionBranch: text('production_branch').notNull().default('master'),
    stagingBranch: text('staging_branch').default('staging'),
    productionUrl: text('production_url'),
    grafanaAppValue: text('grafana_app_value'),
    umamiWebsiteId: text('umami_website_id'),
    hasDeployScript: boolean('has_deploy_script').notNull().default(false),
    hasStatusScript: boolean('has_status_script').notNull().default(false),
    cronMonitoringEnabled: boolean('cron_monitoring_enabled').notNull().default(false),
    maintenanceMode: boolean('maintenance_mode').notNull().default(false),
    lastCommitDeployed: text('last_commit_deployed'),
    latestCommitAvailable: text('latest_commit_available'),
    commitsBehind: integer('commits_behind').notNull().default(0),
    productionCiStatus: text('production_ci_status').$type<CiStatus>().notNull().default('unknown'),
    productionCiUrl: text('production_ci_url'),
    stagingCommitsAhead: integer('staging_commits_ahead').notNull().default(0),
    stagingCommitsBehind: integer('staging_commits_behind').notNull().default(0),
    umamiVisitors24h: integer('umami_visitors_24h').notNull().default(0),
    umamiPageviews24h: integer('umami_pageviews_24h').notNull().default(0),
    umamiBounceRate: integer('umami_bounce_rate').notNull().default(0),
    umamiSyncError: text('umami_sync_error'),
    umamiSyncedAt: timestamp('umami_synced_at', { withTimezone: true }),
    screenshotUpdatedAt: timestamp('screenshot_updated_at', { withTimezone: true }),
    vpsSyncedAt: timestamp('vps_synced_at', { withTimezone: true }),
    githubSyncedAt: timestamp('github_synced_at', { withTimezone: true }),
    cronSyncedAt: timestamp('cron_synced_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex('projects_slug_unique').on(table.slug),
    uniqueIndex('projects_vps_path_unique').on(table.vpsPath),
    index('projects_kind_idx').on(table.kind),
    index('projects_umami_website_id_idx').on(table.umamiWebsiteId),
  ],
)

export const deployments = pgTable(
  'deployments',
  {
    id: serial('id').primaryKey(),
    projectId: integer('project_id')
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    commitSha: text('commit_sha'),
    status: text('status').$type<DeploymentStatus>().notNull().default('running'),
    triggeredBy: text('triggered_by').notNull().default('web'),
    durationSeconds: integer('duration_seconds'),
    log: text('log').notNull().default(''),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index('deployments_project_created_idx').on(table.projectId, table.createdAt),
    index('deployments_created_idx').on(table.createdAt),
    index('deployments_status_idx').on(table.status),
  ],
)

export const cronJobs = pgTable(
  'cron_jobs',
  {
    id: serial('id').primaryKey(),
    projectId: integer('project_id')
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    command: text('command').notNull().default('unknown'),
    schedule: text('schedule').notNull().default('unknown'),
    lastStatus: text('last_status').$type<CronStatus>().notNull().default('unknown'),
    lastDuration: integer('last_duration'),
    lastExecutionAt: timestamp('last_execution_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [uniqueIndex('cron_jobs_project_name_unique').on(table.projectId, table.name)],
)

export const jobExecutions = pgTable(
  'job_executions',
  {
    id: serial('id').primaryKey(),
    cronJobId: integer('cron_job_id')
      .notNull()
      .references(() => cronJobs.id, { onDelete: 'cascade' }),
    status: text('status').$type<CronStatus>().notNull().default('unknown'),
    duration: integer('duration'),
    log: text('log').notNull().default(''),
    executedAt: timestamp('executed_at', { withTimezone: true }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index('job_executions_cron_executed_idx').on(table.cronJobId, table.executedAt)],
)

export const githubPullRequests = pgTable(
  'github_pull_requests',
  {
    id: serial('id').primaryKey(),
    projectId: integer('project_id')
      .notNull()
      .references(() => projects.id, { onDelete: 'cascade' }),
    number: integer('number').notNull(),
    title: text('title').notNull(),
    state: text('state').notNull(),
    isRenovate: boolean('is_renovate').notNull().default(false),
    draft: boolean('draft').notNull().default(false),
    authorLogin: text('author_login'),
    headRef: text('head_ref'),
    baseRef: text('base_ref'),
    htmlUrl: text('html_url'),
    openedAt: timestamp('opened_at', { withTimezone: true }),
    closedAt: timestamp('closed_at', { withTimezone: true }),
    mergedAt: timestamp('merged_at', { withTimezone: true }),
    githubUpdatedAt: timestamp('github_updated_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex('github_prs_project_number_unique').on(table.projectId, table.number),
    index('github_prs_project_state_idx').on(table.projectId, table.state),
    index('github_prs_renovate_state_idx').on(table.isRenovate, table.state),
  ],
)

export const projectScreenshots = pgTable('project_screenshots', {
  projectId: integer('project_id')
    .primaryKey()
    .references(() => projects.id, { onDelete: 'cascade' }),
  contentType: text('content_type').notNull().default('image/jpeg'),
  dataBase64: text('data_base64').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
})

export type ProjectRow = typeof projects.$inferSelect
export type NewProjectRow = typeof projects.$inferInsert
export type DeploymentRow = typeof deployments.$inferSelect
export type CronJobRow = typeof cronJobs.$inferSelect
export type JobExecutionRow = typeof jobExecutions.$inferSelect
export type GithubPullRequestRow = typeof githubPullRequests.$inferSelect
export type ProjectScreenshotRow = typeof projectScreenshots.$inferSelect
