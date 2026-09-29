import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

// IMPLEMENTATION-PROMPT §11.3. JASSUB (WASM + worker + default font) is a lazy chunk: never on
// the landing page, never precached — fetched on the first .ass, then CacheFirst for 30 days.
const LAZY = /(jassub|worker-|fonts-|default-).*\.(js|wasm|woff2)$/
const THIRTY_DAYS = 60 * 60 * 24 * 30

export default defineConfig({
  base: process.env.VITE_BASE_PATH ?? '/',
  build: { target: 'es2022', sourcemap: true },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['jassub'] },
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'script', // an external registerSW.js — the CSP allows no inline script
      includeAssets: ['icons/*.png'],
      manifest: {
        name: 'Marquee Lite',
        short_name: 'Marquee',
        description: 'Drop a film. The lights go down. The subtitles are already there.',
        theme_color: '#07060A',
        background_color: '#07060A',
        display: 'standalone',
        orientation: 'any',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          {
            src: 'icons/icon-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // The app shell and fonts precache. NEVER precache media, JASSUB, or /api/**.
        globPatterns: ['**/*.{js,css,html,woff2,png,svg,frag}'],
        globIgnores: [
          '**/ass-*.js',
          '**/jassub*',
          '**/worker-*.js',
          '**/fonts-*.js',
          '**/default-*.woff2',
        ],
        navigateFallback: 'index.html',
        navigateFallbackDenylist: [/\/api\//],
        runtimeCaching: [
          { urlPattern: /\/api\//, handler: 'NetworkOnly' },
          {
            urlPattern: ({ url }) =>
              LAZY.test(url.pathname) || /\/ass-[^/]*\.js$/.test(url.pathname),
            handler: 'CacheFirst',
            options: {
              cacheName: 'marquee-lazy',
              expiration: { maxAgeSeconds: THIRTY_DAYS, maxEntries: 16 },
            },
          },
        ],
      },
    }),
  ],
})
