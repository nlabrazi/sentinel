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

const driftLabel = computed(() => {
  switch (props.project.stagingSyncStatus) {
    case 'synced':
      return `Synchronisé avec ${props.project.productionBranch}`
    case 'ahead':
      return `+${props.project.stagingCommitsAhead} commit(s) sur ${props.project.stagingBranch}`
    case 'behind':
      return `-${props.project.stagingCommitsBehind} commit(s) en retard`
    case 'diverged':
      return `+${props.project.stagingCommitsAhead} / -${props.project.stagingCommitsBehind} (divergé)`
    default:
      return 'Branche staging non configurée'
  }
})

const driftColor = computed(() => {
  switch (props.project.stagingSyncStatus) {
    case 'synced':
      return 'success' as const
    case 'ahead':
      return 'info' as const
    case 'behind':
    case 'diverged':
      return 'warning' as const
    default:
      return 'neutral' as const
  }
})

async function handleSyncGithub() {
  syncing.value = true
  try {
    const result = await $fetch<{
      synced: boolean
      pullRequestsSynced: number
      renovateOpenCount: number
    }>(`/api/projects/${props.project.slug}/sync-github`, { method: 'POST' })
    emit('refreshed')
    toast.add({
      title: 'GitHub synchronisé',
      description: `${result.pullRequestsSynced} PR(s) synchronisée(s), dont ${result.renovateOpenCount} Renovate ouverte(s).`,
      color: 'success',
    })
  } catch (error) {
    toast.add({
      title: 'Erreur de synchro GitHub',
      description: error instanceof Error ? error.message : 'Vérifiez GITHUB_TOKEN.',
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
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-git-branch" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">GitHub, Drift &amp; Pull Requests</h2>
          <span v-if="project.githubSyncedAt" class="text-xs text-muted">
            (sync {{ formatRelativeTime(project.githubSyncedAt) }})
          </span>
        </div>

        <UButton
          v-if="project.repoUrl"
          size="xs"
          color="neutral"
          variant="soft"
          icon="i-lucide-refresh-cw"
          :loading="syncing"
          @click="handleSyncGithub"
        >
          Sync GitHub
        </UButton>
      </div>
    </template>

    <div v-if="!project.repoUrl" class="py-4 text-sm text-muted">
      Aucun dépôt GitHub associé à ce projet. Configurez l'URL du dépôt pour suivre le drift et les
      PRs Renovate.
    </div>

    <div v-else class="space-y-4">
      <!-- Drift summary -->
      <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
        <div class="flex items-center justify-between rounded-lg border border-default p-3">
          <div>
            <p class="text-xs text-muted">Staging vs {{ project.productionBranch }}</p>
            <div class="mt-1 flex items-center gap-2">
              <UBadge :color="driftColor" variant="subtle" size="sm">{{ driftLabel }}</UBadge>
            </div>
          </div>
          <UButton
            v-if="project.githubCompareStagingUrl"
            :to="project.githubCompareStagingUrl"
            target="_blank"
            size="xs"
            color="neutral"
            variant="ghost"
            icon="i-lucide-git-compare"
            aria-label="Comparer staging et production sur GitHub"
          >
            Diff
          </UButton>
        </div>

        <div class="flex items-center justify-between rounded-lg border border-default p-3">
          <div>
            <p class="text-xs text-muted">VPS déployé vs HEAD {{ project.productionBranch }}</p>
            <div class="mt-1 flex flex-wrap items-center gap-2 font-mono text-xs">
              <span>{{ shortSha(project.lastCommitDeployed) }}</span>
              <span class="text-muted">→</span>
              <span>{{ shortSha(project.latestCommitAvailable) }}</span>
              <UBadge
                v-if="project.commitsBehind > 0 && project.productionCiStatus === 'failed'"
                color="error"
                variant="subtle"
                size="xs"
              >
                CI en échec (+{{ project.commitsBehind }})
              </UBadge>
              <UBadge
                v-else-if="project.commitsBehind > 0 && project.productionCiStatus === 'pending'"
                color="info"
                variant="subtle"
                size="xs"
              >
                CI en cours (+{{ project.commitsBehind }})
              </UBadge>
              <UBadge v-else-if="project.commitsBehind > 0" color="warning" variant="subtle" size="xs">
                +{{ project.commitsBehind }} en attente
              </UBadge>
              <UBadge v-else color="success" variant="subtle" size="xs">À jour</UBadge>
              <UBadge
                v-if="project.productionCiStatus === 'success'"
                color="success"
                variant="outline"
                size="xs"
              >
                CI OK
              </UBadge>
            </div>
          </div>
          <div class="flex items-center gap-1">
            <UButton
              v-if="project.productionCiUrl && project.productionCiStatus !== 'unknown'"
              :to="project.productionCiUrl"
              target="_blank"
              size="xs"
              color="neutral"
              variant="ghost"
              icon="i-lucide-external-link"
              aria-label="Ouvrir le build CI de la branche de production"
            >
              CI
            </UButton>
            <UButton
              v-if="project.githubCompareDeployUrl"
              :to="project.githubCompareDeployUrl"
              target="_blank"
              size="xs"
              color="neutral"
              variant="ghost"
              icon="i-lucide-git-compare"
              aria-label="Comparer le commit déployé et la branche de production"
            >
              Diff
            </UButton>
          </div>
        </div>
      </div>

      <!-- Recent Pull Requests Table -->
      <div
        v-if="project.pullRequests.length > 0"
        tabindex="0"
        role="region"
        aria-labelledby="project-prs-caption"
        class="table-wrapper"
      >
        <table class="w-full border-collapse text-left text-sm">
          <caption id="project-prs-caption" class="visually-hidden">
            Pull requests récentes pour {{ project.name }}
          </caption>
          <thead class="border-b border-default text-xs uppercase text-muted">
            <tr>
              <th scope="col" class="py-2 pr-3 font-medium">PR</th>
              <th scope="col" class="py-2 pr-3 font-medium">Statut</th>
              <th scope="col" class="py-2 pr-3 font-medium">Auteur / Branche</th>
              <th scope="col" class="py-2 text-right font-medium">MAJ</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-default">
            <tr v-for="pr in project.pullRequests" :key="pr.id">
              <td class="py-2.5 pr-3">
                <div class="flex flex-wrap items-center gap-1.5">
                  <UBadge v-if="pr.isRenovate" color="secondary" variant="subtle" size="xs">
                    Renovate
                  </UBadge>
                  <a
                    v-if="pr.htmlUrl"
                    :href="pr.htmlUrl"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-medium hover:text-primary"
                  >
                    #{{ pr.number }} {{ pr.title }}
                  </a>
                  <span v-else>#{{ pr.number }} {{ pr.title }}</span>
                </div>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3">
                <UBadge
                  :color="
                    pr.state === 'open'
                      ? 'success'
                      : pr.state === 'merged'
                        ? 'secondary'
                        : 'neutral'
                  "
                  variant="subtle"
                  size="xs"
                >
                  {{ pr.state }}
                </UBadge>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-muted">
                <span>{{ pr.authorLogin || '—' }}</span>
                <span v-if="pr.headRef" class="ml-1.5 font-mono">({{ pr.headRef }})</span>
              </td>
              <td class="whitespace-nowrap py-2.5 text-right text-xs text-muted">
                {{ formatRelativeTime(pr.githubUpdatedAt) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="text-xs text-muted">Aucune pull request synchronisée pour ce dépôt.</p>
    </div>
  </UCard>
</template>
