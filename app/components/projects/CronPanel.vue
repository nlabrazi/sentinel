<script setup lang="ts">
import type { CronJobDto, JobExecutionDto, ProjectDetailDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectDetailDto
}>()

const emit = defineEmits<{
  refreshed: []
}>()

const toast = useToast()
const syncing = ref(false)
const selectedExecution = ref<{ jobName: string; execution: JobExecutionDto } | null>(null)
const logOpen = ref(false)

function cronStatusColor(
  status: CronJobDto['displayStatus'] | ProjectDetailDto['cronSummaryStatus'],
) {
  switch (status) {
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
}

async function handleSyncCron() {
  syncing.value = true
  try {
    const res = await $fetch<{ synced: boolean; jobsCount: number }>(
      `/api/projects/${props.project.slug}/sync-cron`,
      { method: 'POST' },
    )
    emit('refreshed')
    toast.add({
      title: 'Statuts cron synchronisés',
      description: `${res.jobsCount} tâche(s) synchronisée(s) depuis le VPS.`,
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Échec de synchro cron',
      description: error instanceof Error ? error.message : 'Vérifiez ./status.sh sur le VPS.',
      color: 'error',
    })
  } finally {
    syncing.value = false
  }
}

function openExecutionLog(jobName: string, execution: JobExecutionDto) {
  selectedExecution.value = { jobName, execution }
  logOpen.value = true
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-clock" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">Supervision Crons &amp; Prometheus</h2>
          <UBadge :color="cronStatusColor(project.cronSummaryStatus)" variant="subtle" size="sm">
            {{ project.cronSummaryStatus }}
          </UBadge>
          <span v-if="project.cronSyncedAt" class="text-xs text-muted">
            (sync {{ formatRelativeTime(project.cronSyncedAt) }})
          </span>
        </div>

        <UButton
          v-if="project.cronMonitoringEnabled"
          size="xs"
          color="neutral"
          variant="soft"
          icon="i-lucide-refresh-cw"
          :loading="syncing"
          @click="handleSyncCron"
        >
          Sync Crons
        </UButton>
      </div>
    </template>

    <div v-if="!project.cronMonitoringEnabled" class="py-3 text-sm text-muted">
      Le monitoring cron est désactivé pour ce projet. Activez-le via « Configurer » (ou via
      <code>sentinel.json</code>) pour exposer les métriques sur <code>/metrics</code>.
    </div>

    <div v-else-if="project.cronJobs.length === 0" class="py-4 text-sm text-muted">
      Aucune tâche cron remontée pour l'instant. Vérifiez <code>./status.sh</code> ou
      <code>sentinel/cron-status.json</code> puis cliquez sur « Sync Crons ».
    </div>

    <div v-else class="space-y-4">
      <div
        v-for="job in project.cronJobs"
        :key="job.id"
        class="rounded-lg border border-default p-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div>
            <div class="flex items-center gap-2">
              <h3 class="font-semibold">{{ job.name }}</h3>
              <UBadge :color="cronStatusColor(job.displayStatus)" variant="subtle" size="xs">
                {{ job.displayStatus }}
              </UBadge>
            </div>
            <p class="mt-1 font-mono text-xs text-muted">
              {{ job.schedule }} (UTC) · {{ job.command }}
            </p>
          </div>

          <div class="text-right text-xs text-muted">
            <p>Dernier run : {{ formatRelativeTime(job.lastExecutionAt) }}</p>
            <p>Durée : {{ formatDuration(job.lastDuration) }}</p>
          </div>
        </div>

        <div v-if="job.executions.length > 0" class="mt-3 border-t border-default pt-3">
          <p class="mb-2 text-xs font-medium text-muted">Dernières exécutions</p>
          <div class="flex flex-wrap gap-1.5">
            <UButton
              v-for="exec in job.executions.slice(0, 8)"
              :key="exec.id"
              size="xs"
              :color="
                exec.status === 'success'
                  ? 'success'
                  : exec.status === 'failed'
                    ? 'error'
                    : 'neutral'
              "
              variant="soft"
              @click="openExecutionLog(job.name, exec)"
            >
              {{ formatRelativeTime(exec.executedAt) }} ({{ formatDuration(exec.duration) }})
            </UButton>
          </div>
        </div>
      </div>
    </div>

    <UModal
      v-model:open="logOpen"
      :title="`Exécution ${selectedExecution?.jobName ?? ''}`"
      :description="selectedExecution ? `${selectedExecution.execution.status} · ${formatDuration(selectedExecution.execution.duration)}` : undefined"
    >
      <template #body>
        <pre
          class="max-h-96 overflow-auto rounded-lg bg-zinc-950 p-3 font-mono text-xs leading-relaxed text-zinc-100"
          style="color-scheme: dark"
        >{{ selectedExecution?.execution.log || '(Aucun log)' }}</pre>
      </template>
      <template #footer>
        <div class="flex w-full justify-end">
          <UButton color="neutral" variant="ghost" @click="logOpen = false">Fermer</UButton>
        </div>
      </template>
    </UModal>
  </UCard>
</template>
