export default defineNuxtConfig({
  extends: ['@nlabrazi/nuxt-layer'],
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },

  runtimeConfig: {
    health: {
      service: 'sentinel',
    },
    public: {
      umami: {
        websiteId: 'b207c955-ba25-4ba2-a228-fc70e8a67e34',
        domains: 'sentinel.nabster.dev',
      },
      site: {
        name: 'Sentinel',
        url: 'https://sentinel.nabster.dev',
        description:
          'Panneau de contrôle DevOps auto-hébergé pour opérations VPS, déploiements SSH et supervision.',
      },
    },
  },

  modules: ['@nuxt/ui'],

  css: ['~/assets/css/main.css'],

  app: {
    head: {
      title: 'Sentinel — VPS Operations Control Plane',
      meta: [
        { name: 'color-scheme', content: 'light dark' },
        {
          name: 'description',
          content:
            'Panneau de contrôle DevOps auto-hébergé pour opérations VPS, déploiements SSH et supervision.',
        },
        { name: 'robots', content: 'noindex, nofollow' },
        { name: 'application-name', content: 'Sentinel' },
        { name: 'apple-mobile-web-app-title', content: 'Sentinel' },
        { name: 'theme-color', content: '#ffffff', media: '(prefers-color-scheme: light)' },
        { name: 'theme-color', content: '#09090b', media: '(prefers-color-scheme: dark)' },
      ],
      link: [
        { rel: 'icon', type: 'image/x-icon', href: '/favicon.ico', sizes: 'any' },
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
        { rel: 'manifest', href: '/site.webmanifest' },
      ],
    },
  },
})
