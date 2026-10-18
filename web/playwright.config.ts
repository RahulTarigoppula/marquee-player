import { existsSync } from 'node:fs'
import { defineConfig, devices, firefox } from '@playwright/test'

// Determinism (§10.2): TZ pinned, the Worker is always mocked with page.route('**/api/**').
process.env.TZ = 'Asia/Kolkata'

// Two builds of the same site, each served by its own preview on its own port:
//   - "worker": VITE_API_BASE points at the local wrangler origin (allowed by the CSP's
//     connect-src); every /api/** request is fulfilled by page.route, so nothing leaves.
//   - "lite": no VITE_API_BASE — the production state while no Worker is deployed.
// Each builds into its own outDir, and a server is never reused: a stale preview from another
// build (or another branch) would otherwise answer for this one.
const WORKER_PORT = 4273
const LITE_PORT = 4274
const API = 'http://localhost:8787/api'

const server = (port: number, outDir: string, apiBase: string) => ({
  command: `npx vite build --outDir ${outDir} --emptyOutDir && npx vite preview --outDir ${outDir} --port ${port} --strictPort`,
  url: `http://localhost:${port}`,
  reuseExistingServer: false,
  timeout: 180_000,
  env: { VITE_API_BASE: apiBase, VITE_BASE_PATH: '/' },
})

const LITE_SPECS = /\.lite\.spec\.ts$/

// CI always installs Firefox (ci.yml); a machine without it still runs the Chromium projects.
const withFirefox = !!process.env.CI || existsSync(firefox.executablePath())
const firefoxProject = {
  name: 'firefox',
  testIgnore: LITE_SPECS,
  use: { ...devices['Desktop Firefox'], baseURL: `http://localhost:${WORKER_PORT}` },
}

export default defineConfig({
  workers: process.env.CI ? 2 : '50%',
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    timezoneId: 'Asia/Kolkata',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      testIgnore: LITE_SPECS,
      use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${WORKER_PORT}` },
    },
    ...(withFirefox ? [firefoxProject] : []),
    {
      name: 'pixel-7',
      testIgnore: LITE_SPECS,
      use: { ...devices['Pixel 7'], baseURL: `http://localhost:${WORKER_PORT}` },
    },
    {
      name: 'lite-chromium',
      testMatch: LITE_SPECS,
      use: { ...devices['Desktop Chrome'], baseURL: `http://localhost:${LITE_PORT}` },
    },
    {
      name: 'lite-pixel-7',
      testMatch: LITE_SPECS,
      use: { ...devices['Pixel 7'], baseURL: `http://localhost:${LITE_PORT}` },
    },
  ],
  webServer: [server(WORKER_PORT, 'dist-e2e-worker', API), server(LITE_PORT, 'dist-e2e-lite', '')],
})
