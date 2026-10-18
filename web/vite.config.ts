import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

// IMPLEMENTATION-PROMPT §11.3. JASSUB (WASM + worker + default font) is a lazy chunk: never on
// the landing page, never precached — fetched on the first .ass, then CacheFirst for 30 days.
const THIRTY_DAYS = 60 * 60 * 24 * 30

// What an installed Lite offers to open from the OS ("Open with…"). Read by launchQueue in
// main.ts. Subtitle files are listed too, so a film and its .srt can be opened together.
const FILE_TYPES: Record<string, string[]> = {
  'video/mp4': ['.mp4', '.m4v'],
  'video/webm': ['.webm'],
  'video/x-matroska': ['.mkv', '.mk3d'],
  'video/quicktime': ['.mov'],
  'video/ogg': ['.ogv'],
  'audio/*': ['.mp3', '.m4a', '.aac', '.ogg', '.opus', '.flac', '.wav', '.mka'],
  'text/plain': ['.srt', '.ass', '.ssa'],
  'text/vtt': ['.vtt'],
}

export default defineConfig({
  base: process.env.VITE_BASE_PATH ?? '/',
  build: { target: 'es2022', sourcemap: true },
  worker: { format: 'es' },
  optimizeDeps: { exclude: ['jassub'] },
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'script', // an external registerSW.js — the CSP allows no inline script
      // public/icons/*.png are already matched by globPatterns below; listing them again (or
      // letting the manifest icons be added) precached every icon twice.
      includeManifestIcons: false,
      manifest: {
        id: './',
        name: 'Marquee Lite',
        short_name: 'Marquee',
        description: 'Drop a film. The lights go down. The subtitles are already there.',
        start_url: './',
        scope: './',
        theme_color: '#07060A',
        background_color: '#07060A',
        display: 'standalone',
        orientation: 'any',
        categories: ['entertainment'],
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
        file_handlers: [{ action: './', accept: FILE_TYPES }],
        launch_handler: { client_mode: 'focus-existing' },
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
            // Workbox serialises this function into sw.js on its own, so it must not close over
            // anything in this file: the pattern is written out inline.
            urlPattern: ({ url }) =>
              /(jassub|worker-|fonts-|default-).*\.(js|wasm|woff2)$/.test(url.pathname) ||
              /\/ass-[^/]*\.js$/.test(url.pathname),
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
