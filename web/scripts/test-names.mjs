// Lists every test('…') name in src/engine/*.test.ts, grouped by file, into
// src/engine/TEST_NAMES.txt — the TypeScript side of the Dart ↔ TS parity check.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'engine')
const NAME = /\btest(?:\.skipIf\([^)]*\))?\(\s*(['"])((?:\\.|(?!\1).)*)\1/g
const out = []
for (const f of readdirSync(DIR)
  .filter((x) => x.endsWith('.test.ts'))
  .sort()) {
  const src = readFileSync(join(DIR, f), 'utf8')
  const names = [...src.matchAll(NAME)].map((m) => m[2].replace(/\\(.)/g, '$1'))
  out.push(`## ${f} (${names.length})`, ...names, '')
}
writeFileSync(join(DIR, 'TEST_NAMES.txt'), out.join('\n'))
