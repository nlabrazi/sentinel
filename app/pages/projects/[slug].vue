<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { ProjectDetailDto } from '#shared/types/api'

type ProjectTabId = 'deploys' | 'github' | 'crons' | 'observability' | 'terminal'

const route = useRoute()
const router = useRouter()
const slug = computed(() => String(route.params.slug || ''))

const {
  data: project,
  refresh,
  error,
} = await useFetch<ProjectDetailDto>(() => `/api/projects/${slug.value}`)

useHead(() => ({
  title: project.value ? `${project.value.name} | Sentinel` : 'Projet | Sentinel',
}))

const toast = useToast()
const editOpen = ref(false)
const maintenanceModalOpen = ref(false)
const togglingMaintenance = ref(false)
const busyAction = ref<string | null>(null)
const deployRunning = ref(false)
const deployPanelRef = ref<{ triggerDeploy: () => Promise<void> } | null>(null)
const tabButtonsRef = ref<HTMLButtonElement[]>([])

const activeTab = ref<ProjectTabId>('deploys')

const attention = computed(() => (project.value ? getProjectAttentionState(project.value) : null))

const canDeploy = computed(
  () => Boolean(project.value?.hasDeployScript) && project.value?.kind !== 'service',
)

const displayDomain = computed(() => {
  if (!project.value?.productionUrl) {
    return null
  }
  return project.value.productionUrl.replace(/^https?:\/\//, '').replace(/\/$/, '')
})

const tabs = computed(() => {
  const p = project.value
  if (!p) {
    return []
  }

  return [
    {
      id: 'deploys' as const,
      label: 'Déploiements',
      icon: 'i-lucide-rocket',
      badge: p.commitsBehind > 0 ? `+${p.commitsBehind}` : undefined,
      badgeColor: 'warning' as const,
    },
    {
      id: 'github' as const,
      label: 'GitHub & PRs',
      icon: 'i-lucide-git-branch',
      badge: p.openPrsCount > 0 ? String(p.openPrsCount) : undefined,
      badgeColor: (p.openRenovatePrsCount > 0 ? 'secondary' : 'neutral') as 'secondary' | 'neutral',
    },
    {
      id: 'crons' as const,
      label: 'Crons',
      icon: 'i-lucide-clock',
      badge: hasCronAlert(p)
        ? 'Alerte'
        : p.cronMonitoringEnabled && p.cronJobs.length > 0
          ? String(p.cronJobs.length)
          : undefined,
      badgeColor: (hasCronAlert(p) ? 'error' : 'neutral') as 'error' | 'neutral',
    },
    {
      id: 'observability' as const,
      label: 'Observabilité',
      icon: 'i-lucide-activity',
      badge: undefined,
      badgeColor: 'neutral' as const,
    },
    {
      id: 'terminal' as const,
      label: 'Terminal',
      icon: 'i-lucide-terminal',
      badge: undefined,
      badgeColor: 'neutral' as const,
    },
  ]
})

function selectTab(id: ProjectTabId, focusIndex?: number) {
  activeTab.value = id
  nextTick(() => {
    const idx = focusIndex ?? tabs.value.findIndex((t) => t.id === id)
    const el = tabButtonsRef.value[idx]
    if (el) {
      el.scrollIntoView({ block: 'nearest', inline: 'nearest' })
      if (focusIndex !== undefined) {
        el.focus()
      }
    }
  })
}

function handleTabKeydown(event: KeyboardEvent, index: number) {
  const count = tabs.value.length
  if (count === 0) {
    return
  }
  let nextIndex: number | null = null
  if (event.key === 'ArrowRight') {
    nextIndex = (index + 1) % count
  } else if (event.key === 'ArrowLeft') {
    nextIndex = (index - 1 + count) % count
  } else if (event.key === 'Home') {
    nextIndex = 0
  } else if (event.key === 'End') {
    nextIndex = count - 1
  }
  if (nextIndex === null) {
    return
  }
  event.preventDefault()
  const target = tabs.value[nextIndex]
  if (target) {
    // Manual activation on focus move so heavy Observability/Grafana iframe is opt-in
    const el = tabButtonsRef.value[nextIndex]
    el?.focus()
    el?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }
}

async function handleHeroDeploy() {
  activeTab.value = 'deploys'
  await nextTick()
  await deployPanelRef.value?.triggerDeploy()
}

async function runProjectSync(key: string, endpoint: string, title: string) {
  busyAction.value = key
  try {
    await $fetch(endpoint, { method: 'POST' })
    await refresh()
    toast.add({ title, color: 'success' })
  } catch (err) {
    toast.add({
      title: `Échec : ${title}`,
      description: err instanceof Error ? err.message : 'Erreur serveur.',
      color: 'error',
    })
  } finally {
    busyAction.value = null
  }
}

const actionMenuItems = computed<DropdownMenuItem[][]>(() => {
  const p = project.value
  if (!p) {
    return []
  }

  const syncItems: DropdownMenuItem[] = []
  if (p.repoUrl) {
    syncItems.push({
      label: 'Sync GitHub',
      icon: 'i-lucide-git-branch',
      onSelect: () =>
        runProjectSync('github', `/api/projects/${p.slug}/sync-github`, 'GitHub synchronisé'),
    })
  }
  if (p.cronMonitoringEnabled) {
    syncItems.push({
      label: 'Sync Crons',
      icon: 'i-lucide-clock',
      onSelect: () =>
        runProjectSync('cron', `/api/projects/${p.slug}/sync-cron`, 'Crons synchronisés'),
    })
  }
  if (p.umamiWebsiteId) {
    syncItems.push({
      label: 'Sync Umami',
      icon: 'i-lucide-bar-chart-3',
      onSelect: () =>
        runProjectSync(
          'umami',
          `/api/projects/${p.slug}/sync-umami`,
          'Analytics Umami synchronisés',
        ),
    })
  }
  if (p.productionUrl) {
    syncItems.push({
      label: "Rafraîchir l'aperçu",
      icon: 'i-lucide-camera',
      onSelect: () =>
        runProjectSync('screenshot', `/api/projects/${p.slug}/screenshot`, 'Aperçu mis à jour'),
    })
  }

  const manageItems: DropdownMenuItem[] = [
    {
      label: p.maintenanceMode ? 'Désactiver la maintenance' : 'Activer la maintenance (503)',
      icon: 'i-lucide-wrench',
      color: 'warning',
      onSelect: () => {
        maintenanceModalOpen.value = true
      },
    },
    {
      label: 'Configurer le projet',
      icon: 'i-lucide-settings-2',
      onSelect: () => {
        editOpen.value = true
      },
    },
  ]

  return syncItems.length > 0 ? [syncItems, manageItems] : [manageItems]
})

async function handleToggleMaintenance() {
  if (!project.value) {
    return
  }
  togglingMaintenance.value = true
  try {
    const nextState = !project.value.maintenanceMode
    await $fetch(`/api/projects/${project.value.slug}/maintenance`, {
      method: 'PATCH',
      body: { enabled: nextState },
    })
    maintenanceModalOpen.value = false
    await refresh()
    toast.add({
      title: nextState ? 'Mode maintenance activé' : 'Mode maintenance désactivé',
      description: `Flag maintenance.on ${nextState ? 'créé' : 'supprimé'} sur le VPS.`,
      color: nextState ? 'warning' : 'success',
    })
  } catch (err) {
    toast.add({
      title: 'Erreur mode maintenance',
      description: err instanceof Error ? err.message : 'Erreur SSH.',
      color: 'error',
    })
  } finally {
    togglingMaintenance.value = false
  }
}

const latestDeployment = computed(() => project.value?.deployments[0] ?? null)
</script>

<template>
  <div v-if="error" class="space-y-4">
    <UAlert
      color="error"
      title="Projet introuvable"
      :description="error.message || 'Ce projet ne figure pas dans Sentinel.'"
    />
    <UButton to="/" icon="i-lucide-arrow-left" variant="soft">Retour au cockpit</UButton>
  </div>

  <div v-else-if="project" class="space-y-5">
    <!-- Breadcrumbs -->
    <nav aria-label="Fil d'Ariane" class="flex items-center gap-1.5 text-xs text-muted">
      <NuxtLink to="/" class="hover:text-default">Cockpit</NuxtLink>
      <span>/</span>
      <span class="font-medium text-default">{{ project.name }}</span>
    </nav>

    <!-- Unified Netlify-style Project Hero Card -->
    <UCard>
      <div class="grid grid-cols-1 gap-5 xl:grid-cols-[16rem_minmax(0,1fr)] xl:items-start">
        <!-- Reserved-size Preview -->
        <div class="overflow-hidden rounded-lg border border-default bg-elevated/60">
          <img
            v-if="project.screenshotUrl"
            :src="project.screenshotUrl"
            :alt="`Aperçu en production de ${project.name}`"
            width="1280"
            height="720"
            fetchpriority="high"
            decoding="async"
            class="aspect-video w-full object-cover object-top"
          />
          <div
            v-else
            class="flex aspect-video w-full flex-col items-center justify-center gap-1.5 px-4 text-center text-xs text-muted"
          >
            <UIcon
              :name="project.productionUrl ? 'i-lucide-camera' : 'i-lucide-server'"
              class="size-7 opacity-50"
              aria-hidden="true"
            />
            <span>{{ project.productionUrl ? 'Aucun aperçu' : project.kind }}</span>
          </div>
        </div>

        <!-- Identity + Unified Action Bar + Compact Metric Strip -->
        <div class="min-w-0 space-y-4">
          <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
                  {{ project.name }}
                </h1>
                <UBadge v-if="attention" :color="attention.color" variant="subtle" size="sm">
                  <UIcon
                    :name="attention.icon"
                    class="size-3.5"
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

              <div class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm">
                <a
                  v-if="project.productionUrl && displayDomain"
                  :href="project.productionUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-medium text-primary hover:underline"
                >
                  {{ displayDomain }}
                </a>
                <span class="font-mono text-xs text-muted">{{ project.vpsPath }}</span>
                <span v-if="project.githubRepo" class="font-mono text-xs text-muted">
                  · {{ project.githubRepo }} ({{ project.productionBranch }})
                </span>
              </div>
            </div>

            <!-- Single Consistent Action Bar -->
            <div class="flex shrink-0 flex-wrap items-center gap-2">
              <UButton
                v-if="canDeploy"
                color="primary"
                variant="solid"
                size="sm"
                icon="i-lucide-rocket"
                :loading="deployRunning || Boolean(project.runningDeployment)"
                @click="handleHeroDeploy"
              >
                Déployer
              </UButton>

              <UButton
                v-if="project.productionUrl"
                :to="project.productionUrl"
                target="_blank"
                color="neutral"
                variant="soft"
                size="sm"
                icon="i-lucide-external-link"
              >
                Ouvrir le site
              </UButton>

              <UDropdownMenu :items="actionMenuItems" :content="{ align: 'end' }">
                <UButton
                  color="neutral"
                  variant="soft"
                  size="sm"
                  trailing-icon="i-lucide-chevron-down"
                  :loading="busyAction !== null"
                >
                  Actions
                </UButton>
              </UDropdownMenu>
            </div>
          </div>

          <!-- Compact 4-Metric Strip -->
          <div class="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
            <div class="rounded-lg border border-default bg-elevated/40 px-3 py-2.5">
              <p class="text-xs text-muted">Version prod</p>
              <div class="mt-1 flex items-center justify-between gap-1">
                <span
                  class="truncate text-sm font-semibold"
                  :class="project.commitsBehind > 0 ? 'text-warning' : 'text-success'"
                >
                  {{
                    project.commitsBehind > 0
                      ? `+${project.commitsBehind} en attente`
                      : 'À jour'
                  }}
                </span>
                <a
                  v-if="project.commitsBehind > 0 && project.githubCompareDeployUrl"
                  :href="project.githubCompareDeployUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-primary hover:underline"
                >
                  Diff
                </a>
              </div>
              <p class="mt-0.5 font-mono text-xs text-muted">
                {{ shortSha(project.lastCommitDeployed) }}
              </p>
            </div>

            <button
              type="button"
              class="rounded-lg border border-default bg-elevated/40 px-3 py-2.5 text-left transition-colors hover:border-primary/40"
              @click="selectTab('github')"
            >
              <p class="text-xs text-muted">Staging / PRs</p>
              <p class="mt-1 truncate text-sm font-semibold">
                {{
                  project.stagingSyncStatus === 'ahead'
                    ? `Staging +${project.stagingCommitsAhead}`
                    : project.stagingSyncStatus === 'diverged'
                      ? 'Staging divergé'
                      : project.stagingBranch
                        ? 'Synchronisé'
                        : '—'
                }}
              </p>
              <p class="mt-0.5 text-xs text-muted">
                {{
                  project.openPrsCount > 0
                    ? `${project.openPrsCount} PR ouverte(s)`
                    : 'Aucune PR ouverte'
                }}
              </p>
            </button>

            <button
              type="button"
              class="rounded-lg border border-default bg-elevated/40 px-3 py-2.5 text-left transition-colors hover:border-primary/40"
              @click="selectTab('crons')"
            >
              <p class="text-xs text-muted">Crons</p>
              <p
                class="mt-1 truncate text-sm font-semibold"
                :class="
                  hasCronAlert(project)
                    ? 'text-error'
                    : project.cronMonitoringEnabled
                      ? 'text-success'
                      : 'text-muted'
                "
              >
                {{
                  !project.cronMonitoringEnabled
                    ? 'Désactivé'
                    : hasCronAlert(project)
                      ? project.cronSummaryStatus
                      : 'OK'
                }}
              </p>
              <p class="mt-0.5 text-xs text-muted">
                {{
                  project.cronMonitoringEnabled
                    ? `${project.cronJobs.length} tâche(s)`
                    : 'Non configuré'
                }}
              </p>
            </button>

            <button
              type="button"
              class="rounded-lg border border-default bg-elevated/40 px-3 py-2.5 text-left transition-colors hover:border-primary/40"
              @click="selectTab(project.umamiWebsiteId ? 'observability' : 'deploys')"
            >
              <p class="text-xs text-muted">
                {{ project.umamiWebsiteId ? 'Visiteurs (24h)' : 'Dernier deploy' }}
              </p>
              <p class="mt-1 truncate text-sm font-semibold tabular-nums">
                {{
                  project.umamiWebsiteId
                    ? project.umamiSyncedAt
                      ? project.umamiVisitors24h
                      : '—'
                    : latestDeployment
                      ? formatRelativeTime(latestDeployment.createdAt)
                      : 'Jamais'
                }}
              </p>
              <p class="mt-0.5 text-xs text-muted">
                {{
                  project.umamiWebsiteId
                    ? `${project.umamiPageviews24h} pages vues`
                    : latestDeployment
                      ? latestDeployment.status
                      : '—'
                }}
              </p>
            </button>
          </div>
        </div>
      </div>
    </UCard>

    <!-- Single-row Accessible Tabs (Secondary details tucked cleanly by topic) -->
    <div>
      <div class="border-b border-default">
        <div role="tablist" aria-label="Sections du projet" class="sentinel-tablist">
          <button
            v-for="(tab, index) in tabs"
            :id="`project-tab-${tab.id}`"
            :key="tab.id"
            :ref="(el) => { if (el) tabButtonsRef[index] = el as HTMLButtonElement }"
            type="button"
            role="tab"
            :aria-selected="activeTab === tab.id"
            :tabindex="activeTab === tab.id ? 0 : -1"
            class="sentinel-tab inline-flex items-center gap-2 px-3.5 py-2.5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-primary"
            :class="
              activeTab === tab.id
                ? 'text-primary'
                : 'text-muted hover:text-default'
            "
            @click="selectTab(tab.id)"
            @keydown="handleTabKeydown($event, index)"
          >
            <UIcon :name="tab.icon" class="size-4 shrink-0" aria-hidden="true" />
            <span>{{ tab.label }}</span>
            <UBadge v-if="tab.badge" :color="tab.badgeColor" variant="subtle" size="xs">
              {{ tab.badge }}
            </UBadge>
          </button>
        </div>
      </div>

      <!-- Tab Panels -->
      <div class="pt-5">
        <div
          role="tabpanel"
          aria-labelledby="project-tab-deploys"
          :hidden="activeTab !== 'deploys'"
        >
          <div v-show="activeTab === 'deploys'" class="space-y-4">
            <UAlert
              v-if="hasCronAlert(project)"
              color="error"
              variant="subtle"
              icon="i-lucide-clock-alert"
              title="Une tâche cron nécessite votre attention"
              :description="`Statut actuel : ${project.cronSummaryStatus}.`"
              :actions="[
                {
                  label: 'Voir les crons',
                  color: 'error',
                  variant: 'soft',
                  onClick: () => selectTab('crons'),
                },
              ]"
            />

            <ProjectsDeployPanel
              ref="deployPanelRef"
              :project="project"
              :hide-header-deploy-button="canDeploy"
              @refreshed="refresh()"
              @state-change="deployRunning = $event"
            />
          </div>
        </div>

        <div
          role="tabpanel"
          aria-labelledby="project-tab-github"
          :hidden="activeTab !== 'github'"
        >
          <div v-if="activeTab === 'github'">
            <ProjectsGithubPanel :project="project" @refreshed="refresh()" />
          </div>
        </div>

        <div
          role="tabpanel"
          aria-labelledby="project-tab-crons"
          :hidden="activeTab !== 'crons'"
        >
          <div v-if="activeTab === 'crons'">
            <ProjectsCronPanel :project="project" @refreshed="refresh()" />
          </div>
        </div>

        <div
          role="tabpanel"
          aria-labelledby="project-tab-observability"
          :hidden="activeTab !== 'observability'"
        >
          <!-- Mounted on demand so Grafana iframe only loads when requested -->
          <div v-if="activeTab === 'observability'" class="space-y-5">
            <ProjectsUmamiPanel :project="project" @refreshed="refresh()" />
            <ProjectsGrafanaPanel :project="project" />
          </div>
        </div>

        <div
          role="tabpanel"
          aria-labelledby="project-tab-terminal"
          :hidden="activeTab !== 'terminal'"
        >
          <div v-if="activeTab === 'terminal'">
            <ProjectsQuickTerminal :project="project" />
          </div>
        </div>
      </div>
    </div>

    <ProjectsProjectEditSlideover
      v-model:open="editOpen"
      :project="project"
      @saved="refresh()"
      @deleted="router.push('/')"
    />

    <UModal
      v-model:open="maintenanceModalOpen"
      :title="
        project.maintenanceMode
          ? `Désactiver la maintenance pour ${project.name} ?`
          : `Activer la maintenance pour ${project.name} ?`
      "
      :description="
        project.maintenanceMode
          ? `Supprime ${project.vpsPath}/maintenance.on sans recharger Nginx.`
          : `Crée ${project.vpsPath}/maintenance.on pour afficher la page 503 instantanément.`
      "
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton color="neutral" variant="ghost" @click="maintenanceModalOpen = false">
            Annuler
          </UButton>
          <UButton
            :color="project.maintenanceMode ? 'success' : 'warning'"
            :loading="togglingMaintenance"
            @click="handleToggleMaintenance"
          >
            {{ project.maintenanceMode ? 'Désactiver' : 'Activer' }}
          </UButton>
        </div>
      </template>
    </UModal>
  </div>
</template>
