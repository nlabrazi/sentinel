<script setup lang="ts">
import type { PullRequestDto } from '#shared/types/api'

const props = defineProps<{
  pullRequests: PullRequestDto[]
}>()

const onlyRenovate = ref(true)

const visiblePrs = computed(() => {
  if (!onlyRenovate.value) {
    return props.pullRequests
  }
  return props.pullRequests.filter((pr) => pr.isRenovate)
})

const renovateCount = computed(() => props.pullRequests.filter((pr) => pr.isRenovate).length)
</script>

<template>
  <UCard v-if="pullRequests.length > 0">
    <template #header>
      <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-git-pull-request" class="size-5 text-secondary" aria-hidden="true" />
          <h2 class="text-base font-semibold">File des Pull Requests ouvertes</h2>
          <UBadge color="secondary" variant="subtle" size="sm">
            {{ renovateCount }} Renovate
          </UBadge>
        </div>

        <div class="flex items-center gap-1.5">
          <UButton
            size="xs"
            :color="onlyRenovate ? 'secondary' : 'neutral'"
            :variant="onlyRenovate ? 'solid' : 'soft'"
            @click="onlyRenovate = true"
          >
            Renovate ({{ renovateCount }})
          </UButton>
          <UButton
            size="xs"
            :color="!onlyRenovate ? 'primary' : 'neutral'"
            :variant="!onlyRenovate ? 'solid' : 'soft'"
            @click="onlyRenovate = false"
          >
            Toutes ({{ pullRequests.length }})
          </UButton>
        </div>
      </div>
    </template>

    <div
      v-if="visiblePrs.length > 0"
      tabindex="0"
      role="region"
      aria-labelledby="renovate-queue-caption"
      class="table-wrapper"
    >
      <table class="w-full border-collapse text-left text-sm">
        <caption id="renovate-queue-caption" class="visually-hidden">
          Pull requests ouvertes sur les projets Sentinel
        </caption>
        <thead class="border-b border-default text-xs uppercase text-muted">
          <tr>
            <th scope="col" class="py-2 pr-3 font-medium">Projet</th>
            <th scope="col" class="py-2 pr-3 font-medium">Pull Request</th>
            <th scope="col" class="py-2 pr-3 font-medium">Branches</th>
            <th scope="col" class="py-2 pr-3 font-medium">Mise à jour</th>
            <th scope="col" class="py-2 text-right font-medium">Lien</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-default">
          <tr v-for="pr in visiblePrs" :key="`${pr.projectId}-${pr.number}`">
            <td class="whitespace-nowrap py-2.5 pr-3">
              <NuxtLink
                v-if="pr.projectSlug"
                :to="`/projects/${pr.projectSlug}`"
                class="font-medium hover:text-primary"
              >
                {{ pr.projectName || pr.projectSlug }}
              </NuxtLink>
              <span v-else class="text-muted">—</span>
            </td>
            <td class="py-2.5 pr-3">
              <div class="flex flex-wrap items-center gap-1.5">
                <UBadge v-if="pr.isRenovate" color="secondary" variant="subtle" size="xs">
                  Renovate
                </UBadge>
                <UBadge v-if="pr.draft" color="neutral" variant="outline" size="xs">Draft</UBadge>
                <span class="font-mono text-xs text-muted">#{{ pr.number }}</span>
                <span class="font-medium">{{ pr.title }}</span>
              </div>
            </td>
            <td class="whitespace-nowrap py-2.5 pr-3 font-mono text-xs text-muted">
              {{ pr.headRef || '?' }} → {{ pr.baseRef || '?' }}
            </td>
            <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-muted">
              {{ formatRelativeTime(pr.githubUpdatedAt) }}
            </td>
            <td class="whitespace-nowrap py-2.5 text-right">
              <UButton
                v-if="pr.htmlUrl"
                :to="pr.htmlUrl"
                target="_blank"
                size="xs"
                color="neutral"
                variant="ghost"
                icon="i-lucide-external-link"
                :aria-label="`Ouvrir la PR #${pr.number} sur GitHub`"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-else class="py-4 text-center text-sm text-muted">
      Aucune PR Renovate ouverte actuellement.
    </p>
  </UCard>
</template>
