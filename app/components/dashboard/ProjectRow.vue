<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { ProjectSummaryDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectSummaryDto
  priority?: boolean
  deploying?: boolean
}>()

const emit = defineEmits<{
  deploy: [project: ProjectSummaryDto]
  syncGithub: [project: ProjectSummaryDto]
  syncCron: [project: ProjectSummaryDto]
}>()

const attention = computed(() => getProjectAttentionState(props.project))

const canDeploy = computed(() => props.project.hasDeployScript && props.project.kind !== 'service')

const showDirectDeploy = computed(
  () => canDeploy.value && !props.project.hasRunningDeployment && isDeployReady(props.project),
)

const showCiLink = computed(
  () =>
    !props.project.hasRunningDeployment &&
    props.project.commitsBehind > 0 &&
    (props.project.productionCiStatus === 'failed' ||
      props.project.productionCiStatus === 'pending') &&
    Boolean(props.project.productionCiUrl),
)

const displayDomain = computed(() => {
  if (!props.project.productionUrl) {
    return props.project.vpsPath
  }
  return props.project.productionUrl.replace(/^https?:\/\//, '').replace(/\/$/, '')
})

const leftAccentClass = computed(() => {
  if (attention.value.severity === 'critical') {
    return 'border-l-error'
  }
  if (attention.value.severity === 'warning') {
    return 'border-l-warning'
  }
  if (attention.value.severity === 'running') {
    return 'border-l-info'
  }
  return 'border-l-transparent'
})

const menuItems = computed<DropdownMenuItem[][]>(() => {
  const primaryGroup: DropdownMenuItem[] = [
    {
      label: 'Ouvrir la fiche',
      icon: 'i-lucide-folder-open',
      to: `/projects/${props.project.slug}`,
    },
  ]

  if (canDeploy.value && !props.project.hasRunningDeployment) {
    primaryGroup.push({
      label: 'Déployer maintenant',
      icon: 'i-lucide-rocket',
      onSelect: () => emit('deploy', props.project),
    })
  }

  if (props.project.productionUrl) {
    primaryGroup.push({
      label: 'Ouvrir le site',
      icon: 'i-lucide-external-link',
      to: props.project.productionUrl,
      target: '_blank',
    })
  }

  const syncGroup: DropdownMenuItem[] = []
  if (props.project.repoUrl) {
    syncGroup.push({
      label: 'Sync GitHub',
      icon: 'i-lucide-git-branch',
      onSelect: () => emit('syncGithub', props.project),
    })
  }
  if (props.project.cronMonitoringEnabled) {
    syncGroup.push({
      label: 'Sync Crons',
      icon: 'i-lucide-clock',
      onSelect: () => emit('syncCron', props.project),
    })
  }

  return syncGroup.length > 0 ? [primaryGroup, syncGroup] : [primaryGroup]
})
</script>

<template>
  <article
    class="group border-l-2 px-4 py-3.5 transition-colors hover:bg-elevated/45 sm:px-5"
    :class="leftAccentClass"
  >
    <div
      class="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,1fr)_auto_auto] lg:items-center lg:gap-5"
    >
      <!-- 1. Identity & Primary Status -->
      <div class="flex min-w-0 items-center gap-3.5">
        <NuxtLink
          :to="`/projects/${project.slug}`"
          class="hidden h-14 w-24 shrink-0 overflow-hidden rounded-md border border-default bg-elevated/70 sm:block"
        >
          <img
            v-if="project.screenshotUrl"
            :src="project.screenshotUrl"
            :alt="`Aperçu de ${project.name}`"
            width="1280"
            height="720"
            :loading="priority ? undefined : 'lazy'"
            :fetchpriority="priority ? 'high' : undefined"
            decoding="async"
            class="h-full w-full object-cover object-top transition-transform duration-300 group-hover:scale-[1.03]"
          />
          <div
            v-else
            class="flex h-full w-full flex-col items-center justify-center gap-0.5 text-[10px] font-medium uppercase tracking-wider text-muted"
          >
            <UIcon
              :name="
                project.kind === 'cron'
                  ? 'i-lucide-clock'
                  : project.kind === 'service'
                    ? 'i-lucide-server'
                    : 'i-lucide-globe'
              "
              class="size-4 opacity-60"
              aria-hidden="true"
            />
            <span>{{ project.kind }}</span>
          </div>
        </NuxtLink>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-2">
            <NuxtLink
              :to="`/projects/${project.slug}`"
              class="truncate text-[15px] font-semibold tracking-tight hover:text-primary"
            >
              {{ project.name }}
            </NuxtLink>

            <UBadge :color="attention.color" variant="subtle" size="xs">
              <UIcon
                :name="attention.icon"
                class="size-3"
                :class="attention.severity === 'running' ? 'animate-spin' : ''"
                aria-hidden="true"
              />
              {{ attention.label }}
            </UBadge>

            <UBadge
              v-if="project.kind !== 'app'"
              color="neutral"
              variant="outline"
              size="xs"
              class="capitalize"
            >
              {{ project.kind }}
            </UBadge>
          </div>

          <div class="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-0.5 text-xs text-muted">
            <a
              v-if="project.productionUrl"
              :href="project.productionUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="truncate text-primary/90 hover:text-primary hover:underline"
            >
              {{ displayDomain }}
            </a>
            <span v-else class="truncate font-mono">{{ displayDomain }}</span>

            <span v-if="project.lastCommitDeployed" class="font-mono text-muted/80">
              · {{ shortSha(project.lastCommitDeployed) }}
            </span>

            <span v-if="project.vpsSyncedAt" class="hidden sm:inline">
              · sync {{ formatRelativeTime(project.vpsSyncedAt) }}
            </span>
          </div>
        </div>
      </div>

      <!-- 2. Compact Secondary Signals (only shown when meaningful) -->
      <div class="flex flex-wrap items-center gap-2 text-xs lg:justify-end">
        <UBadge
          v-if="
            project.stagingSyncStatus === 'ahead' &&
            attention.severity !== 'info'
          "
          color="info"
          variant="soft"
          size="xs"
        >
          staging +{{ project.stagingCommitsAhead }}
        </UBadge>
        <UBadge
          v-else-if="project.stagingSyncStatus === 'diverged'"
          color="warning"
          variant="soft"
          size="xs"
        >
          staging +{{ project.stagingCommitsAhead }}/-{{ project.stagingCommitsBehind }}
        </UBadge>

        <UBadge v-if="project.openRenovatePrsCount > 0" color="secondary" variant="soft" size="xs">
          {{ project.openRenovatePrsCount }} Renovate
        </UBadge>
        <UBadge
          v-else-if="project.openPrsCount > 0"
          color="neutral"
          variant="soft"
          size="xs"
        >
          {{ project.openPrsCount }} PR
        </UBadge>

        <UBadge
          v-if="project.cronMonitoringEnabled && hasCronAlert(project) && attention.severity !== 'critical'"
          color="error"
          variant="soft"
          size="xs"
        >
          Cron {{ project.cronSummaryStatus }}
        </UBadge>
      </div>

      <!-- 3. Consistent Right-Aligned Action Slot -->
      <div class="flex items-center justify-end gap-1.5">
        <UButton
          v-if="project.hasRunningDeployment"
          :to="`/projects/${project.slug}`"
          color="info"
          variant="soft"
          size="sm"
          icon="i-lucide-loader-circle"
          class="w-32 justify-center"
        >
          En cours…
        </UButton>

        <UButton
          v-else-if="showDirectDeploy"
          color="primary"
          variant="solid"
          size="sm"
          icon="i-lucide-rocket"
          :loading="deploying"
          class="w-32 justify-center"
          @click="emit('deploy', project)"
        >
          Déployer
        </UButton>

        <UButton
          v-else-if="showCiLink && project.productionCiUrl"
          :to="project.productionCiUrl"
          target="_blank"
          :color="project.productionCiStatus === 'failed' ? 'error' : 'info'"
          variant="soft"
          size="sm"
          icon="i-lucide-external-link"
          class="w-32 justify-center"
        >
          Voir la CI
        </UButton>

        <UButton
          v-else
          :to="`/projects/${project.slug}`"
          color="neutral"
          variant="soft"
          size="sm"
          trailing-icon="i-lucide-chevron-right"
          class="w-32 justify-center"
        >
          Ouvrir
        </UButton>

        <UDropdownMenu :items="menuItems" :content="{ align: 'end' }">
          <UButton
            color="neutral"
            variant="ghost"
            size="sm"
            icon="i-lucide-ellipsis-vertical"
            :aria-label="`Actions pour ${project.name}`"
          />
        </UDropdownMenu>
      </div>
    </div>
  </article>
</template>
