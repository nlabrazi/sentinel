<script setup lang="ts">
import type { ProjectDetailDto } from '#shared/types/api'

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

const editOpen = ref(false)
const maintenanceModalOpen = ref(false)
const togglingMaintenance = ref(false)
const capturingScreenshot = ref(false)
const toast = useToast()

async function handleCaptureScreenshot() {
  if (!project.value) {
    return
  }
  capturingScreenshot.value = true
  try {
    await $fetch(`/api/projects/${project.value.slug}/screenshot`, {
      method: 'POST',
    })
    await refresh()
    toast.add({
      title: 'Aperçu mis à jour',
      description: `Capture ApiFlash enregistrée pour ${project.value.name}.`,
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Échec de capture',
      description: error instanceof Error ? error.message : 'Vérifiez APIFLASH_ACCESS_KEY et URL.',
      color: 'error',
    })
  } finally {
    capturingScreenshot.value = false
  }
}

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
  } catch (error) {
    toast.add({
      title: 'Erreur mode maintenance',
      description: error instanceof Error ? error.message : 'Erreur SSH.',
      color: 'error',
    })
  } finally {
    togglingMaintenance.value = false
  }
}
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

  <div v-else-if="project" class="space-y-6">
    <!-- Breadcrumbs & Actions -->
    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <nav aria-label="Fil d'Ariane" class="mb-2 flex items-center gap-1.5 text-xs text-muted">
          <NuxtLink to="/" class="hover:text-default">Cockpit</NuxtLink>
          <span>/</span>
          <span class="font-medium text-default">{{ project.slug }}</span>
        </nav>

        <div class="flex flex-wrap items-center gap-2.5">
          <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
            {{ project.name }}
          </h1>
          <UBadge color="primary" variant="soft">{{ project.kind }}</UBadge>
          <UBadge v-if="project.maintenanceMode" color="warning" variant="subtle">
            Mode maintenance actif
          </UBadge>
        </div>

        <p class="mt-1 font-mono text-xs text-muted">
          {{ project.vpsPath }}
          <span v-if="project.githubRepo"> · {{ project.githubRepo }}</span>
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <UButton
          v-if="project.productionUrl"
          :to="project.productionUrl"
          target="_blank"
          color="neutral"
          variant="soft"
          icon="i-lucide-external-link"
        >
          Production
        </UButton>
        <UButton
          :color="project.maintenanceMode ? 'warning' : 'neutral'"
          variant="soft"
          icon="i-lucide-wrench"
          @click="maintenanceModalOpen = true"
        >
          {{ project.maintenanceMode ? 'Désactiver maintenance' : 'Maintenance' }}
        </UButton>
        <UButton
          color="neutral"
          variant="soft"
          icon="i-lucide-settings-2"
          @click="editOpen = true"
        >
          Configurer
        </UButton>
      </div>
    </div>

    <!-- Overview screenshot preview & metadata strip -->
    <div class="grid grid-cols-1 gap-4 lg:grid-cols-12">
      <UCard class="lg:col-span-5">
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
            class="flex aspect-video w-full flex-col items-center justify-center gap-2 px-4 text-center text-xs text-muted"
          >
            <UIcon
              :name="project.productionUrl ? 'i-lucide-camera' : 'i-lucide-terminal'"
              class="size-8 opacity-50"
              aria-hidden="true"
            />
            <span>
              {{
                project.productionUrl
                  ? 'Aucun aperçu capturé pour ce projet'
                  : 'Aucune URL de production configurée'
              }}
            </span>
          </div>
        </div>

        <div class="mt-3 flex items-center justify-between gap-2">
          <span class="text-xs text-muted">
            {{
              project.screenshotUpdatedAt
                ? `Capturé ${formatRelativeTime(project.screenshotUpdatedAt)}`
                : 'Jamais capturé'
            }}
          </span>
          <UButton
            size="xs"
            color="neutral"
            variant="soft"
            icon="i-lucide-camera"
            :loading="capturingScreenshot"
            :disabled="!project.productionUrl"
            @click="handleCaptureScreenshot"
          >
            Rafraîchir l'aperçu
          </UButton>
        </div>
      </UCard>

      <div class="grid grid-cols-2 gap-4 lg:col-span-7">
        <UCard>
          <p class="text-xs text-muted">Commit déployé (VPS)</p>
          <p class="mt-1 font-mono text-lg font-semibold">
            {{ shortSha(project.lastCommitDeployed) }}
          </p>
          <p class="mt-0.5 text-xs text-muted">
            Scan VPS : {{ formatRelativeTime(project.vpsSyncedAt) }}
          </p>
        </UCard>

        <UCard>
          <p class="text-xs text-muted">Branche prod / staging</p>
          <p class="mt-1 font-mono text-lg font-semibold">
            {{ project.productionBranch }}
            <span v-if="project.stagingBranch" class="text-sm font-normal text-muted">
              / {{ project.stagingBranch }}
            </span>
          </p>
          <p class="mt-0.5 text-xs text-muted">
            {{ project.commitsBehind > 0 ? `${project.commitsBehind} commit(s) en attente` : 'À jour' }}
          </p>
        </UCard>

        <UCard>
          <p class="text-xs text-muted">Scripts VPS détectés</p>
          <div class="mt-1.5 flex items-center gap-2">
            <UBadge :color="project.hasDeployScript ? 'success' : 'neutral'" variant="subtle" size="sm">
              deploy.sh
            </UBadge>
            <UBadge :color="project.hasStatusScript ? 'success' : 'neutral'" variant="subtle" size="sm">
              status.sh
            </UBadge>
          </div>
        </UCard>

        <UCard>
          <p class="text-xs text-muted">Pull Requests ouvertes</p>
          <p class="mt-1 text-lg font-semibold">
            {{ project.openPrsCount }}
            <span v-if="project.openRenovatePrsCount > 0" class="text-xs font-normal text-secondary">
              ({{ project.openRenovatePrsCount }} Renovate)
            </span>
          </p>
        </UCard>
      </div>
    </div>

    <ProjectsDeployPanel :project="project" @refreshed="refresh()" />

    <ProjectsCronPanel :project="project" @refreshed="refresh()" />

    <ProjectsQuickTerminal :project="project" />

    <ProjectsGithubPanel :project="project" @refreshed="refresh()" />

    <ProjectsUmamiPanel :project="project" @refreshed="refresh()" />

    <ProjectsGrafanaPanel :project="project" />

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
