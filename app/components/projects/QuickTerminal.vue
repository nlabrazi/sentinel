<script setup lang="ts">
import type { ProjectDetailDto } from '#shared/types/api'

interface TerminalEntry {
  id: number
  command: string
  success: boolean
  exitCode: number
  stdout: string
  stderr: string
  durationSeconds: number
}

const props = defineProps<{
  project: ProjectDetailDto
}>()

const toast = useToast()
const commandInput = ref('')
const running = ref(false)
const entries = ref<TerminalEntry[]>([])
const commandHistory = ref<string[]>([])
const historyIndex = ref(-1)
let nextId = 1

const suggestions = [
  'docker compose ps',
  'docker compose logs --tail=50',
  'git status -sb',
  'git log -n 5 --oneline',
  'df -h',
  'uptime',
]

async function runCommand(cmd?: string) {
  const toRun = (cmd ?? commandInput.value).trim()
  if (!toRun || running.value) {
    return
  }

  running.value = true
  commandHistory.value.unshift(toRun)
  historyIndex.value = -1

  try {
    const result = await $fetch<{
      success: boolean
      command: string
      exitCode: number
      stdout: string
      stderr: string
      durationSeconds: number
    }>(`/api/projects/${props.project.slug}/quick-command`, {
      method: 'POST',
      body: { command: toRun },
    })

    entries.value.unshift({
      id: nextId++,
      ...result,
    })
    commandInput.value = ''
  } catch (error) {
    toast.add({
      title: 'Erreur Quick Terminal',
      description: error instanceof Error ? error.message : 'Exécution impossible.',
      color: 'error',
    })
  } finally {
    running.value = false
  }
}

function handleKeydown(event: KeyboardEvent) {
  if (event.key === 'ArrowUp' && commandHistory.value.length > 0) {
    event.preventDefault()
    const nextIdx = Math.min(historyIndex.value + 1, commandHistory.value.length - 1)
    historyIndex.value = nextIdx
    commandInput.value = commandHistory.value[nextIdx] ?? ''
  } else if (event.key === 'ArrowDown') {
    event.preventDefault()
    if (historyIndex.value <= 0) {
      historyIndex.value = -1
      commandInput.value = ''
    } else {
      historyIndex.value -= 1
      commandInput.value = commandHistory.value[historyIndex.value] ?? ''
    }
  }
}

async function copyOutput(entry: TerminalEntry) {
  if (!import.meta.client || !navigator.clipboard) {
    return
  }
  const combined = [entry.stdout, entry.stderr].filter(Boolean).join('\n')
  await navigator.clipboard.writeText(combined)
  toast.add({ title: 'Sortie copiée', color: 'neutral' })
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <UIcon name="i-lucide-terminal" class="size-5 text-primary" aria-hidden="true" />
          <h2 class="text-base font-semibold">Quick Terminal (diagnostic sécurisé)</h2>
        </div>
        <span class="font-mono text-xs text-muted">{{ project.vpsPath }}</span>
      </div>
    </template>

    <div class="space-y-3">
      <!-- Suggestion chips -->
      <div class="flex flex-wrap gap-1.5">
        <UButton
          v-for="chip in suggestions"
          :key="chip"
          size="xs"
          color="neutral"
          variant="soft"
          :disabled="running"
          class="font-mono"
          @click="runCommand(chip)"
        >
          {{ chip }}
        </UButton>
      </div>

      <!-- Command input -->
      <form class="flex gap-2" @submit.prevent="runCommand()">
        <UInput
          v-model="commandInput"
          icon="i-lucide-chevron-right"
          placeholder="Ex: docker compose ps | head -n 20"
          aria-label="Commande diagnostic VPS"
          class="flex-1 font-mono"
          :disabled="running"
          @keydown="handleKeydown"
        />
        <UButton type="submit" :loading="running" icon="i-lucide-play">Exécuter</UButton>
      </form>

      <!-- Results -->
      <div v-if="entries.length > 0" class="space-y-3">
        <div
          v-for="entry in entries"
          :key="entry.id"
          class="overflow-hidden rounded-lg border border-default bg-zinc-950 text-zinc-100"
          style="color-scheme: dark"
        >
          <div class="flex items-center justify-between border-b border-zinc-800 px-3 py-1.5 text-xs">
            <span class="font-mono text-zinc-300">$ {{ entry.command }}</span>
            <div class="flex items-center gap-2">
              <UBadge :color="entry.success ? 'success' : 'error'" variant="subtle" size="xs">
                exit {{ entry.exitCode }} · {{ entry.durationSeconds }}s
              </UBadge>
              <UButton
                size="xs"
                color="neutral"
                variant="ghost"
                icon="i-lucide-copy"
                aria-label="Copier la sortie"
                @click="copyOutput(entry)"
              />
            </div>
          </div>
          <pre
            v-if="entry.stdout"
            class="max-h-64 overflow-auto p-3 font-mono text-xs leading-relaxed text-zinc-100"
          >{{ entry.stdout }}</pre>
          <pre
            v-if="entry.stderr"
            class="max-h-48 overflow-auto border-t border-zinc-800 p-3 font-mono text-xs leading-relaxed text-red-400"
          >{{ entry.stderr }}</pre>
          <p v-if="!entry.stdout && !entry.stderr" class="p-3 font-mono text-xs text-zinc-500">
            (Aucune sortie)
          </p>
        </div>
      </div>
    </div>
  </UCard>
</template>
