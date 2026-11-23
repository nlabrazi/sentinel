import type { ProjectSummaryDto } from '#shared/types/api'

export type AttentionSeverity = 'critical' | 'running' | 'warning' | 'info' | 'ok'

export interface ProjectAttentionState {
  severity: AttentionSeverity
  priority: number
  needsAttention: boolean
  label: string
  color: 'error' | 'info' | 'warning' | 'success' | 'neutral'
  icon: string
}

export function hasCronAlert(
  project: Pick<ProjectSummaryDto, 'cronMonitoringEnabled' | 'cronSummaryStatus'>,
): boolean {
  if (!project.cronMonitoringEnabled) {
    return false
  }
  return (
    project.cronSummaryStatus === 'failed' ||
    project.cronSummaryStatus === 'overdue' ||
    project.cronSummaryStatus === 'not_reported'
  )
}

export function getProjectAttentionState(
  project: Pick<
    ProjectSummaryDto,
    | 'cronMonitoringEnabled'
    | 'cronSummaryStatus'
    | 'hasRunningDeployment'
    | 'commitsBehind'
    | 'maintenanceMode'
    | 'stagingSyncStatus'
    | 'stagingCommitsAhead'
  >,
): ProjectAttentionState {
  if (project.cronMonitoringEnabled && project.cronSummaryStatus === 'failed') {
    return {
      severity: 'critical',
      priority: 0,
      needsAttention: true,
      label: 'Cron en échec',
      color: 'error',
      icon: 'i-lucide-alert-circle',
    }
  }

  if (project.hasRunningDeployment) {
    return {
      severity: 'running',
      priority: 1,
      needsAttention: true,
      label: 'Déploiement en cours',
      color: 'info',
      icon: 'i-lucide-loader-circle',
    }
  }

  if (project.cronMonitoringEnabled && project.cronSummaryStatus === 'overdue') {
    return {
      severity: 'warning',
      priority: 2,
      needsAttention: true,
      label: 'Cron en retard',
      color: 'warning',
      icon: 'i-lucide-clock-alert',
    }
  }

  if (project.commitsBehind > 0) {
    return {
      severity: 'warning',
      priority: 3,
      needsAttention: true,
      label: `${project.commitsBehind} commit(s) à déployer`,
      color: 'warning',
      icon: 'i-lucide-arrow-up-circle',
    }
  }

  if (project.maintenanceMode) {
    return {
      severity: 'warning',
      priority: 4,
      needsAttention: true,
      label: 'Maintenance',
      color: 'warning',
      icon: 'i-lucide-wrench',
    }
  }

  if (project.cronMonitoringEnabled && project.cronSummaryStatus === 'not_reported') {
    return {
      severity: 'warning',
      priority: 5,
      needsAttention: true,
      label: 'Cron non remonté',
      color: 'warning',
      icon: 'i-lucide-clock-alert',
    }
  }

  if (project.stagingSyncStatus === 'ahead' || project.stagingSyncStatus === 'diverged') {
    return {
      severity: 'info',
      priority: 6,
      needsAttention: false,
      label: `Staging +${project.stagingCommitsAhead}`,
      color: 'info',
      icon: 'i-lucide-git-branch',
    }
  }

  return {
    severity: 'ok',
    priority: 7,
    needsAttention: false,
    label: 'À jour',
    color: 'success',
    icon: 'i-lucide-check-circle-2',
  }
}

export function sortProjectsByPriority<T extends ProjectSummaryDto>(projects: readonly T[]): T[] {
  return [...projects].sort((a, b) => {
    const diff = getProjectAttentionState(a).priority - getProjectAttentionState(b).priority
    if (diff !== 0) {
      return diff
    }
    return a.name.localeCompare(b.name, 'fr', { sensitivity: 'base' })
  })
}
