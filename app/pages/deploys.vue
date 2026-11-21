<script setup lang="ts">
import type { DeploymentDto } from '#shared/types/api'

useHead({ title: 'Déploiements | Sentinel' })

interface DeploysHubResponse {
  deployments: DeploymentDto[]
  runningDeployments: DeploymentDto[]
  projects: Array<{ slug: string; name: string }>
  kpis: {
    total: number
    successRate: number
    failed: number
    avgDurationSeconds: number
  }
}

const toast = useToast()
const selectedProject = ref('')
const selectedStatus = ref('')
const search = ref('')
const selectedDeploy = ref<DeploymentDto | null>(null)
const drawerOpen = ref(false)

const queryParams = computed(() => ({
  ...(selectedProject.value ? { project: selectedProject.value } : {}),
  ...(selectedStatus.value ? { status: selectedStatus.value } : {}),
  ...(search.value.trim() ? { q: search.value.trim() } : {}),
}))

const { data, pending, refresh } = await useFetch<DeploysHubResponse>('/api/deploys', {
  query: queryParams,
})

function badgeColor(status: DeploymentDto['status']) {
  if (status === 'success') {
    return 'success' as const
  }
  if (status === 'failed') {
    return 'error' as const
  }
  return 'info' as const
}

function inspectDeploy(deploy: DeploymentDto) {
  selectedDeploy.value = deploy
  drawerOpen.value = true
}

async function copyLog(log: string) {
  if (!import.meta.client || !navigator.clipboard) {
    return
  }
  await navigator.clipboard.writeText(log)
  toast.add({ title: 'Log copié', color: 'neutral' })
}
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
          Hub Déploiements
        </h1>
        <p class="mt-1 text-sm text-muted">
          Historique global, métriques de fiabilité et journaux SSH.
        </p>
      </div>

      <UButton color="neutral" variant="soft" icon="i-lucide-refresh-cw" @click="refresh()">
        Actualiser
      </UButton>
    </div>

    <!-- Running banner -->
    <UAlert
      v-if="(data?.runningDeployments.length ?? 0) > 0"
      color="info"
      icon="i-lucide-loader-circle"
      title="Déploiement en cours"
      :description="`${data?.runningDeployments.map((d) => d.projectName || d.projectSlug).join(', ')}`"
    />

    <!-- KPI Cards -->
    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <UCard>
        <p class="text-xs text-muted">Total déploiements</p>
        <p class="mt-1 text-2xl font-bold tabular-nums">{{ data?.kpis.total ?? 0 }}</p>
      </UCard>
      <UCard>
        <p class="text-xs text-muted">Taux de succès</p>
        <p class="mt-1 text-2xl font-bold tabular-nums text-success">
          {{ data?.kpis.successRate ?? 0 }}%
        </p>
      </UCard>
      <UCard>
        <p class="text-xs text-muted">Échecs</p>
        <p
          class="mt-1 text-2xl font-bold tabular-nums"
          :class="(data?.kpis.failed ?? 0) > 0 ? 'text-error' : ''"
        >
          {{ data?.kpis.failed ?? 0 }}
        </p>
      </UCard>
      <UCard>
        <p class="text-xs text-muted">Durée moyenne</p>
        <p class="mt-1 text-2xl font-bold tabular-nums">
          {{ formatDuration(data?.kpis.avgDurationSeconds) }}
        </p>
      </UCard>
    </div>

    <!-- Filters -->
    <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
      <div class="flex flex-1 flex-wrap items-center gap-2">
        <UInput
          v-model="search"
          icon="i-lucide-search"
          placeholder="Rechercher par projet ou SHA…"
          aria-label="Rechercher un déploiement"
          class="w-full sm:max-w-xs"
        />

        <USelect
          v-model="selectedProject"
          :items="[
            { label: 'Tous les projets', value: '' },
            ...(data?.projects ?? []).map((p) => ({ label: p.name, value: p.slug })),
          ]"
          class="w-48"
          aria-label="Filtrer par projet"
        />
      </div>

      <div class="flex items-center gap-1.5">
        <UButton
          v-for="item in [
            { value: '', label: 'Tous' },
            { value: 'running', label: 'En cours' },
            { value: 'success', label: 'Succès' },
            { value: 'failed', label: 'Échecs' },
          ]"
          :key="item.value"
          size="xs"
          :color="selectedStatus === item.value ? 'primary' : 'neutral'"
          :variant="selectedStatus === item.value ? 'solid' : 'soft'"
          @click="selectedStatus = item.value"
        >
          {{ item.label }}
        </UButton>
      </div>
    </div>

    <!-- Table -->
    <UCard>
      <div v-if="pending" class="py-8 text-center text-sm text-muted">Chargement…</div>

      <div
        v-else-if="(data?.deployments.length ?? 0) > 0"
        tabindex="0"
        role="region"
        aria-labelledby="global-deploys-caption"
        class="table-wrapper"
      >
        <table class="w-full border-collapse text-left text-sm">
          <caption id="global-deploys-caption" class="visually-hidden">
            Liste globale des déploiements Sentinel
          </caption>
          <thead class="border-b border-default text-xs uppercase text-muted">
            <tr>
              <th scope="col" class="py-2 pr-3 font-medium">Projet</th>
              <th scope="col" class="py-2 pr-3 font-medium">Statut</th>
              <th scope="col" class="py-2 pr-3 font-medium">Commit</th>
              <th scope="col" class="py-2 pr-3 font-medium">Durée</th>
              <th scope="col" class="py-2 pr-3 font-medium">Date</th>
              <th scope="col" class="py-2 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-default">
            <tr v-for="deploy in data?.deployments ?? []" :key="deploy.id">
              <td class="whitespace-nowrap py-2.5 pr-3">
                <NuxtLink
                  v-if="deploy.projectSlug"
                  :to="`/projects/${deploy.projectSlug}`"
                  class="font-medium hover:text-primary"
                >
                  {{ deploy.projectName || deploy.projectSlug }}
                </NuxtLink>
                <span v-else class="text-muted">—</span>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3">
                <UBadge :color="badgeColor(deploy.status)" variant="subtle" size="xs">
                  {{ deploy.status }}
                </UBadge>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 font-mono text-xs">
                {{ shortSha(deploy.commitSha) }}
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-muted">
                {{ formatDuration(deploy.durationSeconds) }}
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-muted">
                {{ formatRelativeTime(deploy.createdAt) }}
              </td>
              <td class="whitespace-nowrap py-2.5 text-right">
                <UButton
                  size="xs"
                  color="neutral"
                  variant="ghost"
                  icon="i-lucide-terminal"
                  @click="inspectDeploy(deploy)"
                >
                  Log
                </UButton>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p v-else class="py-8 text-center text-sm text-muted">
        Aucun déploiement ne correspond aux filtres sélectionnés.
      </p>
    </UCard>

    <USlideover
      v-model:open="drawerOpen"
      :title="`Déploiement #${selectedDeploy?.id ?? ''} — ${selectedDeploy?.projectName ?? ''}`"
      :description="selectedDeploy?.commitSha ? `Commit ${shortSha(selectedDeploy.commitSha)}` : undefined"
    >
      <template #body>
        <pre
          class="max-h-[70vh] overflow-auto rounded-lg bg-zinc-950 p-3 font-mono text-xs leading-relaxed text-zinc-100"
          style="color-scheme: dark"
        >{{ selectedDeploy?.log || '(Aucun log enregistré)' }}</pre>
      </template>
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            v-if="selectedDeploy?.log"
            color="neutral"
            variant="soft"
            icon="i-lucide-copy"
            @click="copyLog(selectedDeploy.log)"
          >
            Copier
          </UButton>
          <UButton color="neutral" variant="ghost" @click="drawerOpen = false">Fermer</UButton>
        </div>
      </template>
    </USlideover>
  </div>
</template>
