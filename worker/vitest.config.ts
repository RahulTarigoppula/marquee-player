import { defineConfig } from 'vitest/config'

// test/worker.test.ts runs in plain Node: it imports the Worker's default export and calls
// fetch(req, env) directly, with global fetch stubbed by the fixtures and caches.default
// replaced by an in-memory Cache (test/setup.ts). No upstream is ever contacted.
export default defineConfig({
  test: {
    include: ['test/worker.test.ts'],
    environment: 'node',
    setupFiles: ['test/setup.ts'],
  },
})
