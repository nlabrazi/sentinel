<script setup lang="ts">
import type { ProjectSummaryDto } from '#shared/types/api'
import { PROJECT_KINDS } from '#shared/types/sentinel'

const props = defineProps<{
  project: ProjectSummaryDto
}>()

const open = defineModel<boolean>('open', { default: false })
const emit = defineEmits<{
  saved: []
  deleted: []
}>()

const toast = useToast()
const saving = ref(false)
const deleting = ref(false)
const confirmDeleteOpen = ref(false)

const draft = ref({
  name: '',
  kind: 'app' as ProjectSummaryDto['kind'],
  repoUrl: '',
  productionBranch: 'master',
  stagingBranch: 'staging',
  productionUrl: '',
  grafanaAppValue: '',
  umamiWebsiteId: '',
  cronMonitoringEnabled: false,
})

watch(
  () => [open.value, props.project] as const,
  ([isOpen, project]) => {
    if (!isOpen || !project) {
      return
    }
    draft.value = {
      name: project.name,
      kind: project.kind,
      repoUrl: project.repoUrl ?? '',
      productionBranch: project.productionBranch,
      stagingBranch: project.stagingBranch ?? '',
      productionUrl: project.productionUrl ?? '',
      grafanaAppValue: project.grafanaAppValue ?? '',
      umamiWebsiteId: project.umamiWebsiteId ?? '',
      cronMonitoringEnabled: project.cronMonitoringEnabled,
    }
  },
  { immediate: true },
)

async function handleSave() {
  saving.value = true
  try {
    await $fetch(`/api/projects/${props.project.slug}`, {
      method: 'PATCH',
      body: {
        name: draft.value.name,
        kind: draft.value.kind,
        repoUrl: draft.value.repoUrl || null,
        productionBranch: draft.value.productionBranch,
        stagingBranch: draft.value.stagingBranch || null,
        productionUrl: draft.value.productionUrl || null,
        grafanaAppValue: draft.value.grafanaAppValue || null,
        umamiWebsiteId: draft.value.umamiWebsiteId || null,
        cronMonitoringEnabled: draft.value.cronMonitoringEnabled,
      },
    })
    toast.add({
      title: 'Projet mis à jour',
      description: `Les métadonnées de ${draft.value.name} ont été enregistrées.`,
      color: 'success',
    })
    open.value = false
    emit('saved')
  } catch (error) {
    toast.add({
      title: 'Erreur de mise à jour',
      description: error instanceof Error ? error.message : 'Vérifiez les champs saisis.',
      color: 'error',
    })
  } finally {
    saving.value = false
  }
}

async function handleDelete() {
  deleting.value = true
  try {
    await $fetch(`/api/projects/${props.project.slug}`, { method: 'DELETE' })
    toast.add({
      title: 'Projet retiré de Sentinel',
      description: `${props.project.name} a été supprimé du catalogue (les fichiers VPS restent intacts).`,
      color: 'neutral',
    })
    confirmDeleteOpen.value = false
    open.value = false
    emit('deleted')
  } catch (error) {
    toast.add({
      title: 'Suppression impossible',
      description: error instanceof Error ? error.message : 'Erreur inattendue.',
      color: 'error',
    })
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <USlideover
    v-model:open="open"
    :title="`Configurer ${project.name}`"
    :description="project.vpsPath"
  >
    <template #body>
      <form id="project-edit-form" class="space-y-4" @submit.prevent="handleSave">
        <UFormField label="Nom d'affichage" name="name" required>
          <UInput v-model="draft.name" class="w-full" required />
        </UFormField>

        <UFormField label="Type de workload" name="kind">
          <USelect
            v-model="draft.kind"
            :items="PROJECT_KINDS.map((k) => ({ label: k.toUpperCase(), value: k }))"
            class="w-full"
          />
        </UFormField>

        <UFormField label="URL Production" name="productionUrl" hint="Optionnel">
          <UInput
            v-model="draft.productionUrl"
            type="url"
            placeholder="https://app.nabster.dev"
            class="w-full"
          />
        </UFormField>

        <UFormField label="Dépôt GitHub (HTTPS)" name="repoUrl">
          <UInput
            v-model="draft.repoUrl"
            type="url"
            placeholder="https://github.com/nlabrazi/mon-app.git"
            class="w-full"
          />
        </UFormField>

        <div class="grid grid-cols-2 gap-3">
          <UFormField label="Branche prod" name="productionBranch" required>
            <UInput v-model="draft.productionBranch" class="w-full" required />
          </UFormField>
          <UFormField label="Branche staging" name="stagingBranch">
            <UInput v-model="draft.stagingBranch" placeholder="staging" class="w-full" />
          </UFormField>
        </div>

        <UFormField
          label="Filtre Grafana (var-app)"
          name="grafanaAppValue"
          hint="Valeur du label Grafana pour ce projet"
        >
          <UInput
            v-model="draft.grafanaAppValue"
            placeholder="https://app.nabster.dev"
            class="w-full"
          />
        </UFormField>

        <UFormField label="Umami Website ID" name="umamiWebsiteId" hint="Optionnel (auto-détecté)">
          <UInput v-model="draft.umamiWebsiteId" placeholder="UUID Umami" class="w-full" />
        </UFormField>

        <div class="flex items-center justify-between rounded-lg border border-default p-3">
          <div>
            <p class="text-sm font-medium">Supervision des crons</p>
            <p class="text-xs text-muted">
              Interroge ./status.sh et expose les métriques sur /metrics
            </p>
          </div>
          <USwitch v-model="draft.cronMonitoringEnabled" aria-label="Activer le monitoring cron" />
        </div>
      </form>
    </template>

    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <UButton
          color="error"
          variant="soft"
          icon="i-lucide-trash-2"
          @click="confirmDeleteOpen = true"
        >
          Retirer
        </UButton>
        <div class="flex items-center gap-2">
          <UButton color="neutral" variant="ghost" @click="open = false">Annuler</UButton>
          <UButton type="submit" form="project-edit-form" :loading="saving" icon="i-lucide-save">
            Enregistrer
          </UButton>
        </div>
      </div>
    </template>
  </USlideover>

  <UModal
    v-model:open="confirmDeleteOpen"
    title="Retirer du catalogue Sentinel ?"
    :description="`Le projet ${project.name} sera retiré de la base Sentinel. Rien ne sera supprimé sur le VPS.`"
  >
    <template #footer>
      <div class="flex w-full justify-end gap-2">
        <UButton color="neutral" variant="ghost" @click="confirmDeleteOpen = false">
          Annuler
        </UButton>
        <UButton color="error" :loading="deleting" @click="handleDelete">
          Confirmer la suppression
        </UButton>
      </div>
    </template>
  </UModal>
</template>
