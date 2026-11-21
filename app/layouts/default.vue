<script setup lang="ts">
interface AuthMeResponse {
  user: {
    username: string
    name: string
    email: string
    devBypass?: boolean
  } | null
  authMode: 'dev-bypass' | 'authentik-oidc'
  grafanaBaseUrl: string | null
}

const route = useRoute()
const mobileOpen = ref(false)
const { data: authData } = await useFetch<AuthMeResponse>('/api/auth/me')

const navItems = [
  { label: 'Cockpit', to: '/', icon: 'i-lucide-layout-dashboard' },
  { label: 'Déploiements', to: '/deploys', icon: 'i-lucide-rocket' },
  { label: 'Ops Center', to: '/settings', icon: 'i-lucide-sliders-horizontal' },
]

function isActive(to: string): boolean {
  if (to === '/') {
    return route.path === '/' || route.path.startsWith('/projects/')
  }
  return route.path.startsWith(to)
}
</script>

<template>
  <div class="min-h-screen bg-default text-default flex flex-col lg:flex-row">
    <a
      href="#main-content"
      class="visually-hidden fixed top-2 left-2 z-50 rounded-md bg-primary px-3 py-2 text-sm font-medium text-inverted"
    >
      Aller au contenu principal
    </a>

    <!-- Desktop Sidebar -->
    <aside
      class="hidden lg:flex lg:w-64 lg:shrink-0 lg:flex-col border-r border-default bg-elevated/40"
    >
      <div class="flex h-16 items-center gap-3 border-b border-default px-5">
        <div
          class="flex size-9 items-center justify-center rounded-lg bg-primary/15 text-primary ring-1 ring-primary/30"
        >
          <UIcon name="i-lucide-shield-check" class="size-5" aria-hidden="true" />
        </div>
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold tracking-tight">Sentinel</p>
          <p class="truncate text-xs text-muted">VPS Control Plane</p>
        </div>
      </div>

      <nav aria-label="Navigation principale" class="flex-1 space-y-1 p-3">
        <NuxtLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors"
          :class="
            isActive(item.to)
              ? 'bg-primary/12 text-primary'
              : 'text-muted hover:bg-elevated hover:text-default'
          "
        >
          <UIcon :name="item.icon" class="size-4 shrink-0" aria-hidden="true" />
          <span>{{ item.label }}</span>
        </NuxtLink>

        <USeparator class="my-3" />

        <a
          v-if="authData?.grafanaBaseUrl"
          :href="authData.grafanaBaseUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="flex items-center justify-between gap-2 rounded-lg px-3 py-2 text-sm font-medium text-muted transition-colors hover:bg-elevated hover:text-default"
        >
          <span class="flex items-center gap-3">
            <UIcon name="i-lucide-activity" class="size-4 shrink-0" aria-hidden="true" />
            <span>Grafana SSO</span>
          </span>
          <UIcon name="i-lucide-external-link" class="size-3.5 opacity-70" aria-hidden="true" />
        </a>
      </nav>

      <div class="border-t border-default p-4">
        <div class="flex items-center justify-between gap-2">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium">
              {{ authData?.user?.name || 'Admin' }}
            </p>
            <p class="truncate text-xs text-muted">
              {{
                authData?.authMode === 'dev-bypass'
                  ? 'Mode dev local'
                  : authData?.user?.email || 'Authentik SSO'
              }}
            </p>
          </div>
          <div class="flex items-center gap-1">
            <UColorModeButton size="sm" />
            <UButton
              v-if="authData?.authMode === 'authentik-oidc'"
              to="/auth/logout"
              external
              icon="i-lucide-log-out"
              color="neutral"
              variant="ghost"
              size="sm"
              aria-label="Se déconnecter"
            />
          </div>
        </div>
      </div>
    </aside>

    <!-- Mobile Header -->
    <header
      class="flex h-14 items-center justify-between border-b border-default bg-elevated/40 px-4 lg:hidden"
    >
      <div class="flex items-center gap-2.5">
        <UButton
          icon="i-lucide-menu"
          color="neutral"
          variant="ghost"
          size="sm"
          aria-label="Ouvrir le menu"
          @click="mobileOpen = true"
        />
        <NuxtLink to="/" class="flex items-center gap-2 font-semibold">
          <UIcon name="i-lucide-shield-check" class="size-5 text-primary" aria-hidden="true" />
          <span>Sentinel</span>
        </NuxtLink>
      </div>
      <div class="flex items-center gap-1">
        <UButton
          v-if="authData?.grafanaBaseUrl"
          :to="authData.grafanaBaseUrl"
          target="_blank"
          icon="i-lucide-activity"
          color="neutral"
          variant="ghost"
          size="sm"
          aria-label="Ouvrir Grafana"
        />
        <UColorModeButton size="sm" />
      </div>
    </header>

    <USlideover v-model:open="mobileOpen" side="left" title="Navigation Sentinel">
      <template #body>
        <nav aria-label="Navigation mobile" class="space-y-1">
          <NuxtLink
            v-for="item in navItems"
            :key="item.to"
            :to="item.to"
            class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium"
            :class="
              isActive(item.to)
                ? 'bg-primary/12 text-primary'
                : 'text-muted hover:bg-elevated hover:text-default'
            "
            @click="mobileOpen = false"
          >
            <UIcon :name="item.icon" class="size-4" aria-hidden="true" />
            <span>{{ item.label }}</span>
          </NuxtLink>
        </nav>
      </template>
    </USlideover>

    <!-- Main workspace -->
    <main class="flex-1 min-w-0">
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <slot />
      </div>
    </main>
  </div>
</template>
