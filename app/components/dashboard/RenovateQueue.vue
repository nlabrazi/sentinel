<script setup lang="ts">
import type { PullRequestDto } from '#shared/types/api'

const props = defineProps<{
  pullRequests: PullRequestDto[]
}>()

const onlyRenovate = ref(true)

const renovateCount = computed(() => props.pullRequests.filter((pr) => pr.isRenovate).length)

const visiblePrs = computed(() => {
  if (!onlyRenovate.value) {
    return props.pullRequests
  }
  return props.pullRequests.filter((pr) => pr.isRenovate)
})
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-2">
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

    <div v-if="visiblePrs.length > 0" class="divide-y divide-default rounded-lg border border-default">
      <div
        v-for="pr in visiblePrs"
        :key="`${pr.projectId}-${pr.number}`"
        class="flex items-start justify-between gap-3 p-3 text-sm transition-colors hover:bg-elevated/50"
      >
        <div class="min-w-0 space-y-1">
          <div class="flex flex-wrap items-center gap-1.5">
            <NuxtLink
              v-if="pr.projectSlug"
              :to="`/projects/${pr.projectSlug}`"
              class="text-xs font-semibold text-primary hover:underline"
            >
              {{ pr.projectName || pr.projectSlug }}
            </NuxtLink>
            <UBadge v-if="pr.isRenovate" color="secondary" variant="subtle" size="xs">
              Renovate
            </UBadge>
            <UBadge v-if="pr.draft" color="neutral" variant="outline" size="xs">Draft</UBadge>
          </div>
          <p class="font-medium leading-snug">
            <span class="font-mono text-xs text-muted">#{{ pr.number }}</span>
            {{ pr.title }}
          </p>
          <p class="font-mono text-xs text-muted">
            {{ pr.headRef || '?' }} → {{ pr.baseRef || '?' }} ·
            {{ formatRelativeTime(pr.githubUpdatedAt) }}
          </p>
        </div>

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
      </div>
    </div>

    <p v-else class="py-8 text-center text-sm text-muted">
      Aucune PR {{ onlyRenovate ? 'Renovate ' : '' }}ouverte actuellement.
    </p>
  </div>
</template>
