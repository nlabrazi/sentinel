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
  () => canDeploy.value && !props.project.hasRunningDeployment && props.project.commitsBehind > 0,
)

const displayDomain = computed(() =>
  props.project.productionUrl
    ? props.project.productionUrl.replace(/^https?:\/\//, '').replace(/\/$/, '')
    : props.project.vpsPath,
)

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
  <UCard class="flex h-full flex-col transition-colors hover:border-primary/45">
    <NuxtLink
      :to="`/projects/${project.slug}`"
      class="group mb-3 block aspect-video overflow-hidden rounded-lg border border-default bg-elevated/60"
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
        class="h-full w-full object-cover object-top transition-transform duration-300 group-hover:scale-[1.02]"
      />
      <div
        v-else
        class="flex h-full w-full flex-col items-center justify-center gap-1.5 px-3 text-center text-xs text-muted"
      >
        <UIcon
          :name="
            project.kind === 'cron'
              ? 'i-lucide-clock'
              : project.kind === 'service'
                ? 'i-lucide-server'
                : 'i-lucide-globe'
          "
          class="size-6 opacity-50"
          aria-hidden="true"
        />
        <span>{{ project.productionUrl ? 'Aperçu non capturé' : project.kind }}</span>
      </div>
    </NuxtLink>

    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <NuxtLink
          :to="`/projects/${project.slug}`"
          class="block truncate text-base font-semibold hover:text-primary"
        >
          {{ project.name }}
        </NuxtLink>
        <p class="mt-0.5 truncate text-xs text-muted">{{ displayDomain }}</p>
      </div>

      <UBadge :color="attention.color" variant="subtle" size="xs" class="shrink-0">
        {{ attention.label }}
      </UBadge>
    </div>

    <div class="mt-3 flex flex-wrap items-center gap-1.5 text-xs text-muted">
      <span v-if="project.lastCommitDeployed" class="font-mono">
        {{ shortSha(project.lastCommitDeployed) }}
      </span>
      <UBadge
        v-if="project.stagingSyncStatus === 'ahead' && attention.severity !== 'info'"
        color="info"
        variant="soft"
        size="xs"
      >
        staging +{{ project.stagingCommitsAhead }}
      </UBadge>
      <UBadge v-if="project.openRenovatePrsCount > 0" color="secondary" variant="soft" size="xs">
        {{ project.openRenovatePrsCount }} Renovate
      </UBadge>
    </div>

    <template #footer>
      <div class="flex items-center justify-between gap-2">
        <UButton
          v-if="project.hasRunningDeployment"
          :to="`/projects/${project.slug}`"
          color="info"
          variant="soft"
          size="xs"
          icon="i-lucide-loader-circle"
        >
          En cours…
        </UButton>
        <UButton
          v-else-if="showDirectDeploy"
          color="primary"
          variant="solid"
          size="xs"
          icon="i-lucide-rocket"
          :loading="deploying"
          @click="emit('deploy', project)"
        >
          Déployer
        </UButton>
        <UButton
          v-else
          :to="`/projects/${project.slug}`"
          color="neutral"
          variant="soft"
          size="xs"
          trailing-icon="i-lucide-chevron-right"
        >
          Ouvrir
        </UButton>

        <UDropdownMenu :items="menuItems" :content="{ align: 'end' }">
          <UButton
            color="neutral"
            variant="ghost"
            size="xs"
            icon="i-lucide-ellipsis-vertical"
            :aria-label="`Actions pour ${project.name}`"
          />
        </UDropdownMenu>
      </div>
    </template>
  </UCard>
</template>
