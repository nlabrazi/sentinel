<script setup lang="ts">
import type { ScheduledTaskStatus } from '#server/services/scheduler'
import type { EnvStatusItem } from '#server/utils/env'

useHead({ title: 'Ops Control Center | Sentinel' })

interface OpsStatusResponse {
  runtime: {
    nodeVersion: string
    nodeEnv: string
    uptimeSeconds: number
    authMode: string
    vpsHost: string | null
    vpsAppsRoot: string
    databaseConnected: boolean
    counts: {
      projects: number
      deployments: number
      cronJobs: number
      openPrs: number
    }
  }
  envStatus: EnvStatusItem[]
  schedulerTasks: ScheduledTaskStatus[]
}

const toast = useToast()
const { data, refresh } = await useFetch<OpsStatusResponse>('/api/ops/status')

const busyAction = ref<string | null>(null)

async function triggerGlobal(key: string, endpoint: string, label: string) {
  busyAction.value = key
  try {
    await $fetch(endpoint, { method: 'POST' })
    await refresh()
    toast.add({
      title: `${label} terminé`,
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: `Échec : ${label}`,
      description: error instanceof Error ? error.message : 'Erreur serveur.',
      color: 'error',
    })
  } finally {
    busyAction.value = null
  }
}
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 id="main-content" tabindex="-1" class="text-2xl font-bold tracking-tight">
          Ops Control Center
        </h1>
        <p class="mt-1 text-sm text-muted">
          Déclencheurs globaux, tâches planifiées, santé PostgreSQL et variables d'environnement.
        </p>
      </div>

      <UButton color="neutral" variant="soft" icon="i-lucide-refresh-cw" @click="refresh()">
        Actualiser
      </UButton>
    </div>

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
      <!-- 1. Global Triggers -->
      <UCard>
        <template #header>
          <div class="flex items-center gap-2">
            <UIcon name="i-lucide-zap" class="size-5 text-primary" aria-hidden="true" />
            <h2 class="text-base font-semibold">Déclencheurs globaux</h2>
          </div>
        </template>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <UButton
            color="primary"
            variant="soft"
            icon="i-lucide-radar"
            block
            :loading="busyAction === 'vps'"
            @click="triggerGlobal('vps', '/api/ops/scan-vps', 'Scan VPS')"
          >
            Scanner le VPS
          </UButton>

          <UButton
            color="neutral"
            variant="soft"
            icon="i-lucide-git-branch"
            block
            :loading="busyAction === 'github'"
            @click="triggerGlobal('github', '/api/ops/sync-github', 'Sync GitHub')"
          >
            Sync GitHub
          </UButton>

          <UButton
            color="neutral"
            variant="soft"
            icon="i-lucide-clock"
            block
            :loading="busyAction === 'cron'"
            @click="triggerGlobal('cron', '/api/ops/sync-cron', 'Sync Crons')"
          >
            Sync Crons
          </UButton>

          <UButton
            color="neutral"
            variant="soft"
            icon="i-lucide-bar-chart-3"
            block
            :loading="busyAction === 'umami'"
            @click="triggerGlobal('umami', '/api/ops/sync-umami', 'Sync Umami')"
          >
            Sync Umami
          </UButton>

          <UButton
            color="neutral"
            variant="soft"
            icon="i-lucide-camera"
            block
            :loading="busyAction === 'screenshots'"
            @click="triggerGlobal('screenshots', '/api/ops/sync-screenshots', 'Capture des aperçus')"
          >
            Capturer les aperçus
          </UButton>

          <UButton
            color="neutral"
            variant="soft"
            icon="i-lucide-refresh-cw"
            block
            :loading="busyAction === 'screenshots-force'"
            @click="
              triggerGlobal(
                'screenshots-force',
                '/api/ops/sync-screenshots?force=true',
                'Rafraîchissement complet des aperçus',
              )
            "
          >
            Rafraîchir tous les aperçus
          </UButton>
        </div>
      </UCard>

      <!-- 2. Runtime & DB -->
      <UCard>
        <template #header>
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <UIcon name="i-lucide-server" class="size-5 text-primary" aria-hidden="true" />
              <h2 class="text-base font-semibold">Runtime &amp; PostgreSQL</h2>
            </div>
            <UBadge
              :color="data?.runtime.databaseConnected ? 'success' : 'error'"
              variant="subtle"
              size="sm"
            >
              {{ data?.runtime.databaseConnected ? 'PostgreSQL OK' : 'DB hors ligne' }}
            </UBadge>
          </div>
        </template>

        <dl class="grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt class="text-xs text-muted">Node.js / Env</dt>
            <dd class="font-mono font-medium">
              {{ data?.runtime.nodeVersion }} ({{ data?.runtime.nodeEnv }})
            </dd>
          </div>
          <div>
            <dt class="text-xs text-muted">Authentification</dt>
            <dd class="font-mono font-medium">{{ data?.runtime.authMode }}</dd>
          </div>
          <div>
            <dt class="text-xs text-muted">Racine VPS</dt>
            <dd class="font-mono font-medium">{{ data?.runtime.vpsAppsRoot }}</dd>
          </div>
          <div>
            <dt class="text-xs text-muted">Uptime serveur</dt>
            <dd class="font-mono font-medium">
              {{ formatDuration(data?.runtime.uptimeSeconds) }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-muted">Projets / Déploiements</dt>
            <dd class="font-medium">
              {{ data?.runtime.counts.projects ?? 0 }} / {{ data?.runtime.counts.deployments ?? 0 }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-muted">Crons / PRs ouvertes</dt>
            <dd class="font-medium">
              {{ data?.runtime.counts.cronJobs ?? 0 }} / {{ data?.runtime.counts.openPrs ?? 0 }}
            </dd>
          </div>
        </dl>
      </UCard>

      <!-- 3. Background Scheduler -->
      <UCard>
        <template #header>
          <div class="flex items-center gap-2">
            <UIcon name="i-lucide-timer" class="size-5 text-primary" aria-hidden="true" />
            <h2 class="text-base font-semibold">Tâches planifiées (croner)</h2>
          </div>
        </template>

        <div v-if="(data?.schedulerTasks.length ?? 0) > 0" class="space-y-2.5">
          <div
            v-for="task in data?.schedulerTasks ?? []"
            :key="task.name"
            class="flex items-center justify-between gap-2 rounded-lg border border-default p-3 text-sm"
          >
            <div>
              <p class="font-mono font-medium">{{ task.name }}</p>
              <p class="text-xs text-muted">
                Schedule UTC : <code>{{ task.schedule }}</code> · Runs : {{ task.runCount }}
              </p>
              <p v-if="task.lastError" class="mt-1 text-xs text-error">{{ task.lastError }}</p>
            </div>
            <div class="text-right text-xs">
              <UBadge
                :color="task.lastError ? 'error' : task.running ? 'info' : 'success'"
                variant="subtle"
                size="xs"
              >
                {{ task.running ? 'running' : task.lastError ? 'error' : 'ready' }}
              </UBadge>
              <p class="mt-1 text-muted">Dernier : {{ formatRelativeTime(task.lastRunAt) }}</p>
            </div>
          </div>
        </div>
        <p v-else class="text-sm text-muted">Scheduler inactif dans cet environnement.</p>
      </UCard>

      <!-- 4. Environment Variables Status -->
      <UCard>
        <template #header>
          <div class="flex items-center gap-2">
            <UIcon name="i-lucide-key-round" class="size-5 text-primary" aria-hidden="true" />
            <h2 class="text-base font-semibold">Variables d'environnement</h2>
          </div>
        </template>

        <div
          tabindex="0"
          role="region"
          aria-labelledby="env-status-caption"
          class="table-wrapper max-h-80"
        >
          <table class="w-full border-collapse text-left text-xs">
            <caption id="env-status-caption" class="visually-hidden">
              Statut de configuration des variables d'environnement Sentinel
            </caption>
            <thead class="border-b border-default uppercase text-muted">
              <tr>
                <th scope="col" class="py-1.5 pr-3 font-medium">Catégorie</th>
                <th scope="col" class="py-1.5 pr-3 font-medium">Variable</th>
                <th scope="col" class="py-1.5 text-right font-medium">Statut</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-default">
              <tr v-for="item in data?.envStatus ?? []" :key="`${item.category}-${item.key}`">
                <td class="py-2 pr-3 text-muted">{{ item.category }}</td>
                <td class="py-2 pr-3 font-mono">{{ item.key }}</td>
                <td class="py-2 text-right">
                  <UBadge
                    :color="item.configured ? 'success' : item.required ? 'error' : 'neutral'"
                    variant="subtle"
                    size="xs"
                  >
                    {{ item.configured ? 'Configuré' : 'Manquant' }}
                  </UBadge>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </UCard>
    </div>
  </div>
</template>
