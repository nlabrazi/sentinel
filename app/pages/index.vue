<script setup lang="ts">
import type {
  DeploymentDto,
  ProjectSummaryDto,
  ProjectsDashboardResponse,
  VpsScanResponseDto,
} from '#shared/types/api'

useHead({ title: 'Cockpit | Sentinel' })

type StatusFilter = 'all' | 'attention' | 'deploy' | 'cron' | 'staging'
type ViewMode = 'list' | 'grid'

const VIEW_MODE_KEY = 'sentinel_cockpit_view'

const toast = useToast()
const { data, pending, refresh } = await useFetch<ProjectsDashboardResponse>('/api/projects')

const search = ref('')
const kindFilter = ref<'all' | 'app' | 'service' | 'cron'>('all')
const statusFilter = ref<StatusFilter>('all')
const viewMode = ref<ViewMode>('list')
const scanning = ref(false)
const syncingGithub = ref(false)
const renovateDrawerOpen = ref(false)
const deployingSlug = ref<string | null>(null)

const liveDeploy = reactive<{
  open: boolean
  deploymentId: number | null
  projectName: string
  projectSlug: string
}>({
  open: false,
  deploymentId: null,
  projectName: '',
  projectSlug: '',
})

onMounted(() => {
  const saved = window.localStorage.getItem(VIEW_MODE_KEY)
  if (saved === 'list' || saved === 'grid') {
    viewMode.value = saved
  }
})

function setViewMode(mode: ViewMode) {
  viewMode.value = mode
  if (import.meta.client) {
    window.localStorage.setItem(VIEW_MODE_KEY, mode)
  }
}

const allProjects = computed(() => data.value?.projects ?? [])

const attentionCount = computed(
  () => allProjects.value.filter((p) => getProjectAttentionState(p).needsAttention).length,
)

const stagingAheadCount = computed(
  () =>
    allProjects.value.filter(
      (p) => p.stagingSyncStatus === 'ahead' || p.stagingSyncStatus === 'diverged',
    ).length,
)

const filteredProjects = computed(() => {
  const q = search.value.trim().toLowerCase()

  const matched = allProjects.value.filter((project) => {
    if (kindFilter.value !== 'all' && project.kind !== kindFilter.value) {
      return false
    }
    if (statusFilter.value === 'attention' && !getProjectAttentionState(project).needsAttention) {
      return false
    }
    if (statusFilter.value === 'deploy' && project.commitsBehind <= 0) {
      return false
    }
    if (statusFilter.value === 'cron' && !hasCronAlert(project)) {
      return false
    }
    if (
      statusFilter.value === 'staging' &&
      project.stagingSyncStatus !== 'ahead' &&
      project.stagingSyncStatus !== 'diverged'
    ) {
      return false
    }
    if (!q) {
      return true
    }
    return (
      project.name.toLowerCase().includes(q) ||
      project.slug.toLowerCase().includes(q) ||
      (project.githubRepo ?? '').toLowerCase().includes(q) ||
      (project.productionUrl ?? '').toLowerCase().includes(q)
    )
  })

  return sortProjectsByPriority(matched)
})

function toggleStatusFilter(next: StatusFilter) {
  statusFilter.value = statusFilter.value === next ? 'all' : next
}

async function handleSyncAllGithub() {
  syncingGithub.value = true
  try {
    const result = await $fetch<{ syncedCount: number; failedSlugs: string[] }>(
      '/api/ops/sync-github',
      { method: 'POST' },
    )
    await refresh()
    toast.add({
      title: 'Synchro GitHub terminée',
      description: `${result.syncedCount} dépôt(s) synchronisé(s).`,
      color: result.failedSlugs.length > 0 ? 'warning' : 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Échec de synchro GitHub',
      description: error instanceof Error ? error.message : 'Erreur GitHub API.',
      color: 'error',
    })
  } finally {
    syncingGithub.value = false
  }
}

async function handleScanVps() {
  scanning.value = true
  try {
    const result = await $fetch<VpsScanResponseDto>('/api/ops/scan-vps', { method: 'POST' })
    await refresh()
    toast.add({
      title: 'Scan VPS terminé',
      description: `${result.discoveredCount} projet(s) détecté(s) (${result.createdSlugs.length} créé(s), ${result.updatedSlugs.length} mis à jour).`,
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Échec du scan VPS',
      description: error instanceof Error ? error.message : 'Vérifiez la connexion SSH VPS.',
      color: 'error',
    })
  } finally {
    scanning.value = false
  }
}

async function handleDirectDeploy(project: ProjectSummaryDto) {
  deployingSlug.value = project.slug
  try {
    const created = await $fetch<DeploymentDto>(`/api/projects/${project.slug}/deploy`, {
      method: 'POST',
    })
    liveDeploy.deploymentId = created.id
    liveDeploy.projectName = project.name
    liveDeploy.projectSlug = project.slug
    liveDeploy.open = true
    await refresh()
  } catch (error) {
    toast.add({
      title: `Déploiement impossible (${project.name})`,
      description: error instanceof Error ? error.message : 'Erreur SSH ou verrou actif.',
      color: 'error',
    })
  } finally {
    deployingSlug.value = null
  }
}

async function handleProjectSyncGithub(project: ProjectSummaryDto) {
  try {
    await $fetch(`/api/projects/${project.slug}/sync-github`, { method: 'POST' })
    await refresh()
    toast.add({ title: `GitHub synchronisé (${project.name})`, color: 'success' })
  } catch (error) {
    toast.add({
      title: `Échec sync GitHub (${project.name})`,
      description: error instanceof Error ? error.message : 'Erreur GitHub API.',
      color: 'error',
    })
  }
}

async function handleProjectSyncCron(project: ProjectSummaryDto) {
  try {
    await $fetch(`/api/projects/${project.slug}/sync-cron`, { method: 'POST' })
    await refresh()
    toast.add({ title: `Crons synchronisés (${project.name})`, color: 'success' })
  } catch (error) {
    toast.add({
      title: `Échec sync Crons (${project.name})`,
      description: error instanceof Error ? error.message : 'Erreur SSH.',
      color: 'error',
    })
  }
}
</script>

<template>
  <div class="space-y-5">
    <!-- Compact Unified Page Header -->
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <div class="flex items-center gap-2.5">
          <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
            Cockpit VPS
          </h1>
          <UBadge
            v-if="attentionCount === 0 && allProjects.length > 0"
            color="success"
            variant="subtle"
            size="sm"
          >
            Tout est au vert
          </UBadge>
          <UBadge v-else-if="attentionCount > 0" color="warning" variant="subtle" size="sm">
            {{ attentionCount }} à traiter
          </UBadge>
        </div>
        <p class="mt-0.5 text-sm text-muted">
          Les projets nécessitant une action remontent automatiquement en tête.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <UButton
          color="neutral"
          variant="soft"
          size="sm"
          icon="i-lucide-git-branch"
          :loading="syncingGithub"
          @click="handleSyncAllGithub"
        >
          Sync GitHub
        </UButton>
        <UButton
          color="primary"
          variant="solid"
          size="sm"
          icon="i-lucide-radar"
          :loading="scanning"
          @click="handleScanVps"
        >
          Scanner le VPS
        </UButton>
      </div>
    </div>

    <!-- Interactive KPI Filter Strip (Clickable!) -->
    <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-5">
      <button
        type="button"
        class="flex items-center justify-between rounded-xl border px-3.5 py-3 text-left transition-colors"
        :class="
          statusFilter === 'all'
            ? 'border-primary/60 bg-primary/8'
            : 'border-default bg-default hover:border-primary/35 hover:bg-elevated/40'
        "
        :aria-pressed="statusFilter === 'all'"
        @click="statusFilter = 'all'"
      >
        <div>
          <span class="block text-xs text-muted">Projets VPS</span>
          <span class="mt-0.5 block text-xl font-bold tabular-nums">
            {{ data?.kpis.totalProjects ?? 0 }}
          </span>
        </div>
        <UIcon name="i-lucide-boxes" class="size-5 text-primary" aria-hidden="true" />
      </button>

      <button
        type="button"
        class="flex items-center justify-between rounded-xl border px-3.5 py-3 text-left transition-colors"
        :class="
          statusFilter === 'attention'
            ? 'border-warning/70 bg-warning/10'
            : 'border-default bg-default hover:border-warning/40 hover:bg-elevated/40'
        "
        :aria-pressed="statusFilter === 'attention'"
        @click="toggleStatusFilter('attention')"
      >
        <div>
          <span class="block text-xs text-muted">À traiter</span>
          <span
            class="mt-0.5 block text-xl font-bold tabular-nums"
            :class="attentionCount > 0 ? 'text-warning' : ''"
          >
            {{ attentionCount }}
          </span>
        </div>
        <UIcon
          name="i-lucide-bell-ring"
          class="size-5"
          :class="attentionCount > 0 ? 'text-warning' : 'text-muted'"
          aria-hidden="true"
        />
      </button>

      <button
        type="button"
        class="flex items-center justify-between rounded-xl border px-3.5 py-3 text-left transition-colors"
        :class="
          statusFilter === 'deploy'
            ? 'border-warning/70 bg-warning/10'
            : 'border-default bg-default hover:border-warning/40 hover:bg-elevated/40'
        "
        :aria-pressed="statusFilter === 'deploy'"
        @click="toggleStatusFilter('deploy')"
      >
        <div>
          <span class="block text-xs text-muted">À déployer</span>
          <span
            class="mt-0.5 block text-xl font-bold tabular-nums"
            :class="(data?.kpis.deployPendingCount ?? 0) > 0 ? 'text-warning' : ''"
          >
            {{ data?.kpis.deployPendingCount ?? 0 }}
          </span>
        </div>
        <UIcon
          name="i-lucide-rocket"
          class="size-5"
          :class="(data?.kpis.deployPendingCount ?? 0) > 0 ? 'text-warning' : 'text-muted'"
          aria-hidden="true"
        />
      </button>

      <button
        type="button"
        class="flex items-center justify-between rounded-xl border px-3.5 py-3 text-left transition-colors"
        :class="
          statusFilter === 'cron'
            ? 'border-error/70 bg-error/10'
            : 'border-default bg-default hover:border-error/40 hover:bg-elevated/40'
        "
        :aria-pressed="statusFilter === 'cron'"
        @click="toggleStatusFilter('cron')"
      >
        <div>
          <span class="block text-xs text-muted">Alertes Crons</span>
          <span
            class="mt-0.5 block text-xl font-bold tabular-nums"
            :class="(data?.kpis.cronAlertsCount ?? 0) > 0 ? 'text-error' : 'text-success'"
          >
            {{ data?.kpis.cronAlertsCount ?? 0 }}
          </span>
        </div>
        <UIcon
          name="i-lucide-clock-alert"
          class="size-5"
          :class="(data?.kpis.cronAlertsCount ?? 0) > 0 ? 'text-error' : 'text-success'"
          aria-hidden="true"
        />
      </button>

      <button
        type="button"
        class="col-span-2 flex items-center justify-between rounded-xl border border-default bg-default px-3.5 py-3 text-left transition-colors hover:border-secondary/50 hover:bg-elevated/40 sm:col-span-1"
        @click="renovateDrawerOpen = true"
      >
        <div>
          <span class="block text-xs text-muted">PRs ouvertes</span>
          <span class="mt-0.5 flex items-baseline gap-1.5 text-xl font-bold tabular-nums">
            <span>{{ data?.openPullRequests.length ?? 0 }}</span>
            <span
              v-if="(data?.kpis.openRenovatePrsCount ?? 0) > 0"
              class="text-xs font-medium text-secondary"
            >
              ({{ data?.kpis.openRenovatePrsCount }} Renovate)
            </span>
          </span>
        </div>
        <UIcon
          name="i-lucide-git-pull-request"
          class="size-5"
          :class="(data?.openPullRequests.length ?? 0) > 0 ? 'text-secondary' : 'text-muted'"
          aria-hidden="true"
        />
      </button>
    </div>

    <!-- Single-row Search, Kind Filters & View Switcher -->
    <div class="flex flex-col gap-2.5 sm:flex-row sm:items-center sm:justify-between">
      <div class="flex flex-1 flex-wrap items-center gap-2">
        <UInput
          v-model="search"
          icon="i-lucide-search"
          placeholder="Rechercher un projet, domaine ou dépôt…"
          aria-label="Rechercher un projet"
          class="w-full sm:max-w-xs"
        />

        <UButton
          v-if="stagingAheadCount > 0"
          size="xs"
          :color="statusFilter === 'staging' ? 'info' : 'neutral'"
          :variant="statusFilter === 'staging' ? 'solid' : 'soft'"
          icon="i-lucide-git-branch"
          @click="toggleStatusFilter('staging')"
        >
          Staging ({{ stagingAheadCount }})
        </UButton>

        <UButton
          v-if="statusFilter !== 'all' || kindFilter !== 'all' || search.trim()"
          size="xs"
          color="neutral"
          variant="ghost"
          icon="i-lucide-x"
          @click="
            statusFilter = 'all';
            kindFilter = 'all';
            search = '';
          "
        >
          Réinitialiser
        </UButton>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2 sm:justify-end">
        <div class="flex items-center gap-1">
          <UButton
            v-for="tab in [
              { value: 'all', label: 'Tous' },
              { value: 'app', label: 'Apps' },
              { value: 'service', label: 'Services' },
              { value: 'cron', label: 'Crons' },
            ] as const"
            :key="tab.value"
            size="xs"
            :color="kindFilter === tab.value ? 'primary' : 'neutral'"
            :variant="kindFilter === tab.value ? 'solid' : 'soft'"
            @click="kindFilter = tab.value"
          >
            {{ tab.label }}
          </UButton>
        </div>

        <div class="flex items-center rounded-lg border border-default p-0.5">
          <UButton
            size="xs"
            :color="viewMode === 'list' ? 'primary' : 'neutral'"
            :variant="viewMode === 'list' ? 'soft' : 'ghost'"
            icon="i-lucide-list"
            aria-label="Vue liste"
            @click="setViewMode('list')"
          />
          <UButton
            size="xs"
            :color="viewMode === 'grid' ? 'primary' : 'neutral'"
            :variant="viewMode === 'grid' ? 'soft' : 'ghost'"
            icon="i-lucide-layout-grid"
            aria-label="Vue grille"
            @click="setViewMode('grid')"
          />
        </div>
      </div>
    </div>

    <!-- Projects List (Netlify style) or Grid -->
    <div v-if="pending" class="space-y-2.5">
      <UCard v-for="i in 4" :key="i" class="h-20 animate-pulse" />
    </div>

    <div
      v-else-if="filteredProjects.length > 0 && viewMode === 'list'"
      class="divide-y divide-default overflow-hidden rounded-xl border border-default bg-default"
    >
      <DashboardProjectRow
        v-for="(project, index) in filteredProjects"
        :key="project.slug"
        :project="project"
        :priority="index < 3"
        :deploying="deployingSlug === project.slug"
        @deploy="handleDirectDeploy"
        @sync-github="handleProjectSyncGithub"
        @sync-cron="handleProjectSyncCron"
      />
    </div>

    <div
      v-else-if="filteredProjects.length > 0 && viewMode === 'grid'"
      class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3"
    >
      <DashboardProjectCard
        v-for="(project, index) in filteredProjects"
        :key="project.slug"
        :project="project"
        :priority="index < 3"
        :deploying="deployingSlug === project.slug"
        @deploy="handleDirectDeploy"
        @sync-github="handleProjectSyncGithub"
        @sync-cron="handleProjectSyncCron"
      />
    </div>

    <UCard v-else class="py-12 text-center">
      <UIcon
        :name="allProjects.length === 0 ? 'i-lucide-radar' : 'i-lucide-check-circle-2'"
        class="mx-auto size-10 text-muted"
        aria-hidden="true"
      />
      <h2 class="mt-3 text-base font-semibold">
        {{
          allProjects.length === 0
            ? 'Aucun projet dans le catalogue'
            : 'Aucun projet ne correspond à ce filtre'
        }}
      </h2>
      <p class="mx-auto mt-1 max-w-md text-sm text-muted">
        {{
          allProjects.length === 0
            ? 'Cliquez sur « Scanner le VPS » pour découvrir automatiquement vos projets sous /srv/apps/*.'
            : 'Tout est calme sur ce filtre, ou essayez une autre recherche.'
        }}
      </p>
      <UButton
        v-if="allProjects.length === 0"
        class="mt-4"
        icon="i-lucide-radar"
        :loading="scanning"
        @click="handleScanVps"
      >
        Lancer la découverte VPS
      </UButton>
      <UButton
        v-else
        class="mt-4"
        color="neutral"
        variant="soft"
        @click="
          statusFilter = 'all';
          kindFilter = 'all';
          search = '';
        "
      >
        Afficher tous les projets
      </UButton>
    </UCard>

    <!-- Secondary On-Demand Drawers -->
    <USlideover
      v-model:open="renovateDrawerOpen"
      title="Pull Requests ouvertes"
      description="File consolidée GitHub & Renovate sur l'ensemble de tes dépôts."
    >
      <template #body>
        <DashboardRenovateQueue :pull-requests="data?.openPullRequests ?? []" />
      </template>
    </USlideover>

    <DashboardLiveDeploySlideover
      v-model:open="liveDeploy.open"
      :deployment-id="liveDeploy.deploymentId"
      :project-name="liveDeploy.projectName"
      :project-slug="liveDeploy.projectSlug"
      @finished="refresh()"
    />
  </div>
</template>
