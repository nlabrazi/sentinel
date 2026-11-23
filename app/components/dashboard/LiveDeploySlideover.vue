<script setup lang="ts">
import type { DeploymentDto } from '#shared/types/api'

const open = defineModel<boolean>('open', { default: false })

const props = defineProps<{
  deploymentId: number | null
  projectName: string
  projectSlug: string
}>()

const emit = defineEmits<{
  finished: []
}>()

const toast = useToast()
const liveLog = ref('')
const liveStatus = ref<'idle' | 'running' | 'success' | 'failed'>('idle')
const durationSeconds = ref<number | null>(null)
const logContainer = ref<HTMLElement | null>(null)

let eventSource: EventSource | null = null
let pollTimer: ReturnType<typeof setTimeout> | null = null

function clearPollTimer() {
  if (pollTimer) {
    clearTimeout(pollTimer)
    pollTimer = null
  }
}

function closeStream() {
  clearPollTimer()
  if (eventSource) {
    eventSource.close()
    eventSource = null
  }
}

function scrollLogToBottom() {
  nextTick(() => {
    if (logContainer.value) {
      logContainer.value.scrollTop = logContainer.value.scrollHeight
    }
  })
}

function finishDeploy(status: 'success' | 'failed', duration?: number | null) {
  liveStatus.value = status
  durationSeconds.value = duration ?? null
  toast.add({
    title:
      status === 'success'
        ? `${props.projectName} déployé`
        : `Déploiement en échec (${props.projectName})`,
    description: `Terminé en ${formatDuration(duration)}.`,
    color: status === 'success' ? 'success' : 'error',
  })
  closeStream()
  emit('finished')
}

function pollUntilSettled(deployId: number, attempt = 0) {
  if (props.deploymentId !== deployId || liveStatus.value !== 'running') {
    return
  }
  if (attempt >= 30) {
    liveLog.value +=
      '\n[sentinel] Délai de reconnexion dépassé. Actualisez pour vérifier le statut.\n'
    scrollLogToBottom()
    clearPollTimer()
    emit('finished')
    return
  }

  pollTimer = setTimeout(async () => {
    if (props.deploymentId !== deployId || liveStatus.value !== 'running') {
      return
    }
    try {
      const deploy = await $fetch<DeploymentDto>(`/api/deploys/${deployId}`)
      if (deploy.status === 'success' || deploy.status === 'failed') {
        if (deploy.log) {
          liveLog.value = deploy.log
          scrollLogToBottom()
        }
        finishDeploy(deploy.status, deploy.durationSeconds)
        return
      }
    } catch {
      // Transient error during Sentinel self-restart
    }
    pollUntilSettled(deployId, attempt + 1)
  }, 2000)
}

function attachStream(deployId: number) {
  closeStream()
  liveLog.value = ''
  liveStatus.value = 'running'
  durationSeconds.value = null

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
        scrollLogToBottom()
      }
    } catch {
      // Ignore malformed SSE payload
    }
  })

  es.addEventListener('done', (ev) => {
    try {
      const payload = JSON.parse((ev as MessageEvent).data) as {
        status?: 'success' | 'failed'
        durationSeconds?: number
      }
      finishDeploy(payload.status ?? 'failed', payload.durationSeconds)
    } catch {
      closeStream()
      emit('finished')
    }
  })

  es.onerror = () => {
    if (eventSource === es) {
      eventSource.close()
      eventSource = null
    }
    if (props.deploymentId === deployId && liveStatus.value === 'running') {
      liveLog.value +=
        '\n[sentinel] Connexion interrompue (redémarrage en cours ?), reconnexion automatique…\n'
      scrollLogToBottom()
      pollUntilSettled(deployId)
    }
  }
}

watch(
  () => [open.value, props.deploymentId] as const,
  ([isOpen, deployId]) => {
    if (isOpen && deployId) {
      attachStream(deployId)
    } else if (!isOpen) {
      closeStream()
    }
  },
  { immediate: true },
)

onBeforeUnmount(() => {
  closeStream()
})

async function copyLog() {
  if (!import.meta.client || !navigator.clipboard || !liveLog.value) {
    return
  }
  await navigator.clipboard.writeText(liveLog.value)
  toast.add({ title: 'Log copié', color: 'neutral' })
}
</script>

<template>
  <USlideover
    v-model:open="open"
    :title="`Déploiement — ${projectName}`"
    :description="deploymentId ? `Exécution #${deploymentId} via deploy.sh` : undefined"
  >
    <template #body>
      <div class="space-y-3">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <UBadge
              :color="
                liveStatus === 'success'
                  ? 'success'
                  : liveStatus === 'failed'
                    ? 'error'
                    : 'info'
              "
              variant="subtle"
              size="sm"
            >
              <UIcon
                v-if="liveStatus === 'running'"
                name="i-lucide-loader-circle"
                class="size-3.5 animate-spin"
                aria-hidden="true"
              />
              {{
                liveStatus === 'success'
                  ? 'Déployé'
                  : liveStatus === 'failed'
                    ? 'En échec'
                    : 'En cours…'
              }}
            </UBadge>
            <span v-if="durationSeconds !== null" class="text-xs text-muted">
              {{ formatDuration(durationSeconds) }}
            </span>
          </div>

          <UButton
            v-if="liveLog"
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-copy"
            @click="copyLog"
          >
            Copier
          </UButton>
        </div>

        <pre
          ref="logContainer"
          role="log"
          aria-live="polite"
          class="max-h-[72vh] overflow-auto rounded-lg border border-default bg-zinc-950 p-3.5 font-mono text-xs leading-relaxed text-zinc-100"
          style="color-scheme: dark"
        >{{ liveLog || 'Connexion SSH et lancement de deploy.sh…' }}</pre>
      </div>
    </template>

    <template #footer>
      <div class="flex w-full items-center justify-between gap-2">
        <UButton
          v-if="projectSlug"
          :to="`/projects/${projectSlug}`"
          color="neutral"
          variant="soft"
          size="sm"
          icon="i-lucide-arrow-right"
          @click="open = false"
        >
          Ouvrir la fiche projet
        </UButton>
        <UButton color="neutral" variant="ghost" size="sm" @click="open = false">Fermer</UButton>
      </div>
    </template>
  </USlideover>
</template>
