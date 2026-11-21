<script setup lang="ts">
import type { ProjectSummaryDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectSummaryDto
}>()

const kindColor = computed(() => {
  if (props.project.kind === 'cron') {
    return 'warning' as const
  }
  if (props.project.kind === 'service') {
    return 'info' as const
  }
  return 'primary' as const
})

const cronBadgeColor = computed(() => {
  switch (props.project.cronSummaryStatus) {
    case 'ok':
      return 'success' as const
    case 'failed':
      return 'error' as const
    case 'overdue':
    case 'never_run':
    case 'not_reported':
      return 'warning' as const
    default:
      return 'neutral' as const
  }
})
</script>

<template>
  <UCard class="flex h-full flex-col transition-colors hover:border-primary/50">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <NuxtLink
          :to="`/projects/${project.slug}`"
          class="block truncate text-base font-semibold hover:text-primary"
        >
          {{ project.name }}
        </NuxtLink>
        <p class="mt-0.5 truncate font-mono text-xs text-muted">{{ project.vpsPath }}</p>
      </div>

      <div class="flex shrink-0 items-center gap-1.5">
        <UBadge v-if="project.maintenanceMode" color="warning" variant="subtle" size="sm">
          Maintenance
        </UBadge>
        <UBadge :color="kindColor" variant="soft" size="sm">
          {{ project.kind }}
        </UBadge>
      </div>
    </div>

    <div class="mt-4 flex flex-wrap items-center gap-2 text-xs">
      <UBadge v-if="project.hasRunningDeployment" color="info" variant="subtle">
        <UIcon name="i-lucide-loader-circle" class="size-3 animate-spin" aria-hidden="true" />
        Déploiement en cours
      </UBadge>

      <UBadge v-if="project.commitsBehind > 0" color="warning" variant="subtle">
        {{ project.commitsBehind }} commit(s) à déployer
      </UBadge>

      <UBadge
        v-if="project.stagingSyncStatus === 'ahead'"
        color="info"
        variant="subtle"
      >
        staging +{{ project.stagingCommitsAhead }}
      </UBadge>

      <UBadge
        v-else-if="project.stagingSyncStatus === 'diverged'"
        color="warning"
        variant="subtle"
      >
        staging +{{ project.stagingCommitsAhead }}/-{{ project.stagingCommitsBehind }}
      </UBadge>

      <UBadge v-if="project.openRenovatePrsCount > 0" color="secondary" variant="subtle">
        {{ project.openRenovatePrsCount }} Renovate PR
      </UBadge>

      <UBadge
        v-if="project.openPrsCount > project.openRenovatePrsCount"
        color="neutral"
        variant="subtle"
      >
        {{ project.openPrsCount - project.openRenovatePrsCount }} PR ouverte(s)
      </UBadge>

      <UBadge v-if="project.cronMonitoringEnabled" :color="cronBadgeColor" variant="subtle">
        Cron: {{ project.cronSummaryStatus }}
      </UBadge>
    </div>

    <div class="mt-4 grid grid-cols-2 gap-2 rounded-lg bg-elevated/60 p-2.5 text-xs">
      <div>
        <span class="block text-muted">Commit VPS</span>
        <span class="font-mono font-medium">{{ shortSha(project.lastCommitDeployed) }}</span>
      </div>
      <div>
        <span class="block text-muted">Branche prod</span>
        <span class="font-mono font-medium">{{ project.productionBranch }}</span>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between gap-2 text-xs text-muted">
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1"
            :class="project.hasDeployScript ? 'text-default' : 'opacity-45'"
          >
            <UIcon name="i-lucide-rocket" class="size-3.5" aria-hidden="true" />
            deploy.sh
          </span>
          <span
            class="inline-flex items-center gap-1"
            :class="project.hasStatusScript ? 'text-default' : 'opacity-45'"
          >
            <UIcon name="i-lucide-clock" class="size-3.5" aria-hidden="true" />
            status.sh
          </span>
        </div>

        <div class="flex items-center gap-1.5">
          <UButton
            v-if="project.productionUrl"
            :to="project.productionUrl"
            target="_blank"
            icon="i-lucide-external-link"
            color="neutral"
            variant="ghost"
            size="xs"
            :aria-label="`Ouvrir ${project.name}`"
          />
          <UButton
            :to="`/projects/${project.slug}`"
            color="neutral"
            variant="soft"
            size="xs"
            trailing-icon="i-lucide-arrow-right"
          >
            Ouvrir
          </UButton>
        </div>
      </div>
    </template>
  </UCard>
</template>
