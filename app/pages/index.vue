<script setup lang="ts">
import type { ProjectsDashboardResponse, VpsScanResponseDto } from '#shared/types/api'

useHead({ title: 'Cockpit | Sentinel' })

const toast = useToast()
const { data, pending, refresh } = await useFetch<ProjectsDashboardResponse>('/api/projects')

const search = ref('')
const kindFilter = ref<'all' | 'app' | 'service' | 'cron'>('all')
const scanning = ref(false)

const filteredProjects = computed(() => {
  const list = data.value?.projects ?? []
  const q = search.value.trim().toLowerCase()

  return list.filter((project) => {
    if (kindFilter.value !== 'all' && project.kind !== kindFilter.value) {
      return false
    }
    if (!q) {
      return true
    }
    return (
      project.name.toLowerCase().includes(q) ||
      project.slug.toLowerCase().includes(q) ||
      (project.githubRepo ?? '').toLowerCase().includes(q)
    )
  })
})

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

const kpis = computed(() => [
  {
    label: 'Projets VPS',
    value: data.value?.kpis.totalProjects ?? 0,
    icon: 'i-lucide-boxes',
    tone: 'text-primary',
  },
  {
    label: 'À déployer',
    value: data.value?.kpis.deployPendingCount ?? 0,
    icon: 'i-lucide-rocket',
    tone: (data.value?.kpis.deployPendingCount ?? 0) > 0 ? 'text-warning' : 'text-muted',
  },
  {
    label: 'PRs Renovate',
    value: data.value?.kpis.openRenovatePrsCount ?? 0,
    icon: 'i-lucide-git-pull-request',
    tone: (data.value?.kpis.openRenovatePrsCount ?? 0) > 0 ? 'text-secondary' : 'text-muted',
  },
  {
    label: 'Alertes Crons',
    value: data.value?.kpis.cronAlertsCount ?? 0,
    icon: 'i-lucide-clock-alert',
    tone: (data.value?.kpis.cronAlertsCount ?? 0) > 0 ? 'text-error' : 'text-success',
  },
])
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
          Cockpit VPS
        </h1>
        <p class="mt-1 text-sm text-muted">
          Découverte automatique <code>/srv/apps/*</code>, déploiements SSH et supervision.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <UButton
          icon="i-lucide-radar"
          :loading="scanning"
          @click="handleScanVps"
        >
          Scanner le VPS
        </UButton>
      </div>
    </div>

    <!-- KPI Row -->
    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <UCard v-for="kpi in kpis" :key="kpi.label">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs font-medium text-muted">{{ kpi.label }}</p>
            <p class="mt-1 text-2xl font-bold tabular-nums">{{ kpi.value }}</p>
          </div>
          <UIcon :name="kpi.icon" class="size-6" :class="kpi.tone" aria-hidden="true" />
        </div>
      </UCard>
    </div>

    <!-- Search & Kind Filters -->
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <UInput
        v-model="search"
        icon="i-lucide-search"
        placeholder="Rechercher un projet, slug ou dépôt GitHub…"
        aria-label="Rechercher un projet"
        class="w-full sm:max-w-sm"
      />

      <div class="flex items-center gap-1.5">
        <UButton
          v-for="tab in [
            { value: 'all', label: 'Tous' },
            { value: 'app', label: 'Apps' },
            { value: 'service', label: 'Services' },
            { value: 'cron', label: 'Crons' },
          ] as const"
          :key="tab.value"
          size="sm"
          :color="kindFilter === tab.value ? 'primary' : 'neutral'"
          :variant="kindFilter === tab.value ? 'solid' : 'soft'"
          @click="kindFilter = tab.value"
        >
          {{ tab.label }}
        </UButton>
      </div>
    </div>

    <!-- Projects Grid -->
    <div v-if="pending" class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
      <UCard v-for="i in 3" :key="i" class="h-44 animate-pulse" />
    </div>

    <div
      v-else-if="filteredProjects.length > 0"
      class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3"
    >
      <DashboardProjectCard
        v-for="project in filteredProjects"
        :key="project.slug"
        :project="project"
      />
    </div>

    <UCard v-else class="py-12 text-center">
      <UIcon name="i-lucide-radar" class="mx-auto size-10 text-muted" aria-hidden="true" />
      <h2 class="mt-3 text-base font-semibold">Aucun projet dans le catalogue</h2>
      <p class="mx-auto mt-1 max-w-md text-sm text-muted">
        Cliquez sur « Scanner le VPS » pour découvrir automatiquement vos projets déployés sous
        <code>/srv/apps/*</code> via SSH.
      </p>
      <UButton class="mt-4" icon="i-lucide-radar" :loading="scanning" @click="handleScanVps">
        Lancer la découverte VPS
      </UButton>
    </UCard>
  </div>
</template>
