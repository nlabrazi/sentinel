<script setup lang="ts">
import type { ProjectDetailDto } from '#shared/types/api'

const props = defineProps<{
  project: ProjectDetailDto
}>()

const colorMode = useColorMode()

const themedEmbedUrl = computed(() => {
  if (!props.project.grafanaEmbedUrl) {
    return null
  }
  try {
    const url = new URL(props.project.grafanaEmbedUrl)
    url.searchParams.set('theme', colorMode.value === 'light' ? 'light' : 'dark')
    return url.toString()
  } catch {
    return props.project.grafanaEmbedUrl
  }
})
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-activity" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">Observabilité Grafana</h2>
        </div>

        <UButton
          v-if="project.grafanaDirectUrl"
          :to="project.grafanaDirectUrl"
          target="_blank"
          size="xs"
          color="neutral"
          variant="soft"
          icon="i-lucide-external-link"
        >
          Ouvrir dans Grafana (SSO)
        </UButton>
      </div>
    </template>

    <div v-if="themedEmbedUrl" class="space-y-2">
      <iframe
        :src="themedEmbedUrl"
        :title="`Dashboard Grafana pour ${project.name}`"
        class="h-80 w-full rounded-lg border border-default"
        loading="lazy"
      />
      <p class="text-xs text-muted">
        Utilise votre session Authentik SSO active sur Grafana (aucun token dans l'URL).
      </p>
    </div>

    <p v-else class="py-3 text-sm text-muted">
      Configurez <code>GRAFANA_BASE_URL</code> / <code>GRAFANA_DASHBOARD_UID</code> et la valeur
      <code>grafanaAppValue</code> du projet pour afficher le panneau Grafana embarqué.
    </p>
  </UCard>
</template>
