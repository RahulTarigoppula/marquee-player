import { defineConfig } from 'vitest/config'

// Determinism (IMPLEMENTATION-PROMPT §10.2): the house fixture is 21:14 IST — night.
process.env.TZ = 'Asia/Kolkata'

export default defineConfig({
  test: {
    environment: 'happy-dom',
    include: ['src/**/*.test.ts'],
    env: { TZ: 'Asia/Kolkata' },
    coverage: {
      provider: 'v8',
      include: ['src/engine/**/*.ts'],
      exclude: ['src/engine/**/*.test.ts', 'src/engine/types.ts'],
      thresholds: {
        'src/engine/osHash.ts': { lines: 100 },
        'src/engine/scoring.ts': { lines: 100 },
        'src/engine/timecode.ts': { lines: 100 },
        'src/engine/syncRule.ts': { lines: 100 },
        'src/engine/tickets.ts': { lines: 100 },
      },
    },
  },
})
