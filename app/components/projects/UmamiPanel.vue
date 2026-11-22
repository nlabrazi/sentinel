<script setup lang="ts">
import type { ProjectDetailDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectDetailDto
}>()

const emit = defineEmits<{
  refreshed: []
}>()

const toast = useToast()
const syncing = ref(false)

async function handleSyncUmami() {
  syncing.value = true
  try {
    const res = await $fetch<{ success: boolean; message: string }>(
      `/api/projects/${props.project.slug}/sync-umami`,
      { method: 'POST' },
    )
    emit('refreshed')
    toast.add({
      title: res.success ? 'Analytics Umami synchronisés' : 'Synchronisation Umami incomplète',
      description: res.message,
      color: res.success ? 'success' : 'warning',
    })
  } catch (error) {
    toast.add({
      title: 'Erreur Umami',
      description: error instanceof Error ? error.message : 'Vérifiez la configuration Umami.',
      color: 'error',
    })
  } finally {
    syncing.value = false
  }
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-bar-chart-3" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">Analytics Umami (24h)</h2>
          <span v-if="project.umamiSyncedAt" class="text-xs text-muted">
            (sync {{ formatRelativeTime(project.umamiSyncedAt) }})
          </span>
        </div>

        <UButton
          size="xs"
          color="neutral"
          variant="soft"
          icon="i-lucide-refresh-cw"
          :loading="syncing"
          @click="handleSyncUmami"
        >
          Sync Umami
        </UButton>
      </div>
    </template>

    <UAlert
      v-if="project.umamiSyncError"
      color="warning"
      variant="subtle"
      class="mb-4"
      title="Dernière synchro Umami"
      :description="project.umamiSyncError"
    />

    <div class="grid grid-cols-3 gap-4">
      <div class="rounded-lg border border-default p-3">
        <p class="text-xs text-muted">Visiteurs (24h)</p>
        <p class="mt-1 text-2xl font-bold tabular-nums">{{ project.umamiVisitors24h }}</p>
      </div>
      <div class="rounded-lg border border-default p-3">
        <p class="text-xs text-muted">Pages vues (24h)</p>
        <p class="mt-1 text-2xl font-bold tabular-nums">{{ project.umamiPageviews24h }}</p>
      </div>
      <div class="rounded-lg border border-default p-3">
        <p class="text-xs text-muted">Taux de rebond</p>
        <p class="mt-1 text-2xl font-bold tabular-nums">{{ project.umamiBounceRate }}%</p>
      </div>
    </div>
  </UCard>
</template>
