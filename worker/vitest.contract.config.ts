import { defineConfig } from 'vitest/config'

// The live contract test (IMPLEMENTATION-PROMPT §10.8) runs in plain Node, not workerd.
export default defineConfig({
  test: {
    include: ['test/contract.test.ts'],
    environment: 'node',
    testTimeout: 30_000,
  },
})
