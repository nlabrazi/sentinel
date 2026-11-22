<script setup lang="ts">
definePageMeta({
  layout: 'auth',
})

useHead({
  title: 'Connexion | Sentinel',
})

const route = useRoute()

const returnTo = computed(() => {
  const raw = typeof route.query.returnTo === 'string' ? route.query.returnTo : '/'
  return raw.startsWith('/') && !raw.startsWith('//') ? raw : '/'
})

const loginHref = computed(() => `/auth/login?returnTo=${encodeURIComponent(returnTo.value)}`)

const errorMessage = computed(() => {
  const code = typeof route.query.error === 'string' ? route.query.error : ''
  switch (code) {
    case 'forbidden':
      return "Votre compte Authentik n'est pas autorisé à accéder à Sentinel (groupe ou email administrateur requis)."
    case 'invalid_state':
      return 'La session de connexion OIDC a expiré ou est invalide. Veuillez réessayer.'
    case 'oidc_failed':
      return "Échec de l'échange OIDC avec Authentik. Vérifiez la configuration du provider."
    case 'not_configured':
      return "Authentik SSO n'est pas encore configuré sur cette instance."
    case 'access_denied':
      return 'Connexion annulée ou refusée par Authentik.'
    default:
      return code ? `Erreur d'authentification (${code}).` : null
  }
})

const loggedOut = computed(() => route.query.logged_out === '1')
</script>

<template>
  <main class="w-full max-w-md">
    <div class="mb-8 text-center">
      <h1 id="main-content" tabindex="-1" class="text-3xl font-bold tracking-tight text-white">
        Sentinel
      </h1>
      <p class="mt-2 text-sm text-zinc-400">Accès administrateur</p>
    </div>

    <div class="rounded-lg border border-zinc-800 bg-zinc-900 p-6 shadow-xl">
      <h2 class="mb-6 text-xl font-semibold text-white">Connexion</h2>

      <div
        v-if="errorMessage"
        role="alert"
        class="mb-5 rounded-md border border-red-900/60 bg-red-950/60 px-3.5 py-2.5 text-sm text-red-200"
      >
        {{ errorMessage }}
      </div>

      <div
        v-if="loggedOut"
        role="status"
        class="mb-5 rounded-md border border-emerald-900/60 bg-emerald-950/60 px-3.5 py-2.5 text-sm text-emerald-200"
      >
        Vous avez été déconnecté de Sentinel.
      </div>

      <a
        :href="loginHref"
        class="flex w-full items-center justify-center gap-2.5 rounded-md border border-orange-500/40 bg-gradient-to-r from-orange-600 via-amber-600 to-orange-500 px-4 py-2.5 text-sm font-semibold text-white shadow-lg shadow-orange-950/30 transition-all duration-150 hover:from-orange-500 hover:to-amber-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-500"
      >
        <UIcon name="i-lucide-shield-half" class="size-4 shrink-0" aria-hidden="true" />
        <span>Se connecter avec Authentik</span>
      </a>

      <p class="mt-5 text-center text-xs text-zinc-400">
        Authentification SSO administrateur via Authentik — ouvre également votre session Grafana.
      </p>
    </div>
  </main>
</template>
