<script setup lang="ts">
import type { DeploymentDto, ProjectDetailDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectDetailDto
}>()

const emit = defineEmits<{
  refreshed: []
}>()

const toast = useToast()
const triggering = ref(false)
const activeDeployId = ref<number | null>(null)
const liveLog = ref('')
const liveStatus = ref<'idle' | 'running' | 'success' | 'failed'>('idle')
const selectedLogDeploy = ref<DeploymentDto | null>(null)
const logModalOpen = ref(false)
const logContainer = ref<HTMLElement | null>(null)

let eventSource: EventSource | null = null

function closeStream() {
  if (eventSource) {
    eventSource.close()
    eventSource = null
  }
}

function attachStream(deployId: number) {
  closeStream()
  activeDeployId.value = deployId
  liveLog.value = ''
  liveStatus.value = 'running'

  if (!import.meta.client) {
    return
  }

  const es = new EventSource(`/api/deploys/${deployId}/stream`)
  eventSource = es

  es.addEventListener('chunk', (ev) => {
    try {
      const payload = JSON.parse((ev as MessageEvent).data) as { text?: string }
      if (payload.text) {
        liveLog.value += payload.text
        nextTick(() => {
          if (logContainer.value) {
            logContainer.value.scrollTop = logContainer.value.scrollHeight
          }
        })
      }
    } catch {
      // Ignore malformed SSE chunk
    }
  })

  es.addEventListener('done', (ev) => {
    try {
      const payload = JSON.parse((ev as MessageEvent).data) as {
        status?: 'success' | 'failed'
        durationSeconds?: number
      }
      liveStatus.value = payload.status ?? 'failed'
      toast.add({
        title: liveStatus.value === 'success' ? 'Déploiement réussi' : 'Déploiement en échec',
        description: `Terminé en ${formatDuration(payload.durationSeconds)}.`,
        color: liveStatus.value === 'success' ? 'success' : 'error',
      })
    } finally {
      closeStream()
      emit('refreshed')
    }
  })

  es.onerror = () => {
    closeStream()
    emit('refreshed')
  }
}

watch(
  () => props.project.runningDeployment?.id,
  (runningId) => {
    if (runningId && runningId !== activeDeployId.value) {
      attachStream(runningId)
    }
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  closeStream()
})

async function handleDeploy() {
  triggering.value = true
  try {
    const created = await $fetch<DeploymentDto>(`/api/projects/${props.project.slug}/deploy`, {
      method: 'POST',
    })
    toast.add({
      title: 'Déploiement démarré',
      description: `Exécution de deploy.sh pour ${props.project.name}…`,
      color: 'info',
    })
    attachStream(created.id)
    emit('refreshed')
  } catch (error) {
    toast.add({
      title: 'Déploiement impossible',
      description: error instanceof Error ? error.message : 'Erreur SSH ou verrou actif.',
      color: 'error',
    })
  } finally {
    triggering.value = false
  }
}

async function copyLog(text: string) {
  if (!import.meta.client || !navigator.clipboard) {
    return
  }
  await navigator.clipboard.writeText(text)
  toast.add({ title: 'Log copié dans le presse-papiers', color: 'neutral' })
}

function openDeployLog(deploy: DeploymentDto) {
  selectedLogDeploy.value = deploy
  logModalOpen.value = true
}

function statusBadgeColor(status: DeploymentDto['status']) {
  if (status === 'success') {
    return 'success' as const
  }
  if (status === 'failed') {
    return 'error' as const
  }
  return 'info' as const
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-rocket" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">Déploiements SSH</h2>
          <UBadge v-if="liveStatus === 'running'" color="info" variant="subtle" size="sm">
            En cours…
          </UBadge>
        </div>

        <UButton
          icon="i-lucide-play"
          :loading="triggering || liveStatus === 'running'"
          :disabled="!project.hasDeployScript"
          @click="handleDeploy"
        >
          Déployer
        </UButton>
      </div>
    </template>

    <div class="space-y-4">
      <UAlert
        v-if="!project.hasDeployScript"
        color="neutral"
        variant="subtle"
        title="Aucun script deploy.sh exécutable détecté"
        :description="`Ajoutez ${project.vpsPath}/deploy.sh (chmod +x) puis relancez un scan VPS.`"
      />

      <!-- Live SSE Console -->
      <div v-if="activeDeployId !== null" class="space-y-2">
        <div class="flex items-center justify-between text-xs">
          <div class="flex items-center gap-2">
            <span class="font-medium">Console en direct (déploiement #{{ activeDeployId }})</span>
            <UBadge
              :color="
                liveStatus === 'success'
                  ? 'success'
                  : liveStatus === 'failed'
                    ? 'error'
                    : 'info'
              "
              variant="subtle"
              size="xs"
            >
              {{ liveStatus }}
            </UBadge>
          </div>
          <UButton
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-copy"
            @click="copyLog(liveLog)"
          >
            Copier
          </UButton>
        </div>

        <pre
          ref="logContainer"
          role="log"
          aria-live="polite"
          class="max-h-72 overflow-auto rounded-lg border border-default bg-zinc-950 p-3 font-mono text-xs leading-relaxed text-zinc-100"
          style="color-scheme: dark"
        >{{ liveLog || 'En attente de sortie SSH…' }}</pre>
      </div>

      <!-- Deployment History -->
      <div
        v-if="project.deployments.length > 0"
        tabindex="0"
        role="region"
        aria-labelledby="project-deploys-caption"
        class="table-wrapper"
      >
        <table class="w-full border-collapse text-left text-sm">
          <caption id="project-deploys-caption" class="visually-hidden">
            Historique des déploiements pour {{ project.name }}
          </caption>
          <thead class="border-b border-default text-xs uppercase text-muted">
            <tr>
              <th scope="col" class="py-2 pr-3 font-medium">Statut</th>
              <th scope="col" class="py-2 pr-3 font-medium">Commit</th>
              <th scope="col" class="py-2 pr-3 font-medium">Déclenché par</th>
              <th scope="col" class="py-2 pr-3 font-medium">Durée</th>
              <th scope="col" class="py-2 pr-3 font-medium">Date</th>
              <th scope="col" class="py-2 text-right font-medium">Log</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-default">
            <tr v-for="deploy in project.deployments" :key="deploy.id">
              <td class="whitespace-nowrap py-2.5 pr-3">
                <UBadge :color="statusBadgeColor(deploy.status)" variant="subtle" size="xs">
                  {{ deploy.status }}
                </UBadge>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 font-mono text-xs">
                {{ shortSha(deploy.commitSha) }}
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-muted">
                {{ deploy.triggeredBy }}
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
                  @click="openDeployLog(deploy)"
                >
                  Voir
                </UButton>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="text-xs text-muted">Aucun déploiement enregistré pour ce projet.</p>
    </div>

    <UModal
      v-model:open="logModalOpen"
      :title="`Log déploiement #${selectedLogDeploy?.id ?? ''}`"
      :description="selectedLogDeploy?.commitSha ? `Commit ${shortSha(selectedLogDeploy.commitSha)}` : undefined"
    >
      <template #body>
        <pre
          class="max-h-96 overflow-auto rounded-lg bg-zinc-950 p-3 font-mono text-xs leading-relaxed text-zinc-100"
          style="color-scheme: dark"
        >{{ selectedLogDeploy?.log || '(Log vide)' }}</pre>
      </template>
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            v-if="selectedLogDeploy?.log"
            color="neutral"
            variant="soft"
            icon="i-lucide-copy"
            @click="copyLog(selectedLogDeploy.log)"
          >
            Copier
          </UButton>
          <UButton color="neutral" variant="ghost" @click="logModalOpen = false">Fermer</UButton>
        </div>
      </template>
    </UModal>
  </UCard>
</template>
