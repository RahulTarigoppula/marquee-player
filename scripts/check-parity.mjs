#!/usr/bin/env node
// Engine test parity (IMPLEMENTATION-PROMPT §10.7). The Dart engine (test/engine/*_test.dart) and
// the TS engine (web/src/engine/*.test.ts) are ports of each other and should prove the same
// behaviours. The two suites are authored independently, so names are compared after
// normalisation and differences are REPORTED; only `--strict` turns a difference into a failure.
//
//   node scripts/check-parity.mjs            report, exit 0
//   node scripts/check-parity.mjs --strict   report, exit 1 on any difference
//   node scripts/check-parity.mjs --verbose  also list every unmatched test name
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const strict = process.argv.includes('--strict')
const verbose = process.argv.includes('--verbose') || strict

// Dart module (test/engine/<name>_test.dart) ↔ TS module (web/src/engine/<name>.test.ts)
const PAIRS = [
  ['hash', 'osHash'],
  ['filename', 'filename'],
  ['scoring', 'scoring'],
  ['tickets', 'tickets'],
  ['timecode', 'timecode'],
  ['sync_rule', 'syncRule'],
  ['srt', 'srt2vtt'],
  ['threading', 'threading'],
]

// test('…') / test("…") / it('…') / test(`…`) — the first string argument, escapes honoured.
const TEST_CALL = /\b(?:test|it)\s*\(\s*r?(['"`])((?:\\.|(?!\1)[^\\])*)\1/g

export function testNames(source) {
  const names = []
  for (const m of source.matchAll(TEST_CALL)) names.push(m[2].replace(/\\(.)/g, '$1'))
  return names
}

export function normalise(name) {
  return name
    .toLowerCase()
    .replace(/\$\{[^}]*\}|\$\w+/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function load(path) {
  return existsSync(path) ? testNames(readFileSync(path, 'utf8')) : null
}

const rows = []
let differences = 0
const details = []

for (const [dart, ts] of PAIRS) {
  const dartPath = join(root, 'test', 'engine', `${dart}_test.dart`)
  const tsPath = join(root, 'web', 'src', 'engine', `${ts}.test.ts`)
  const d = load(dartPath)
  const t = load(tsPath)
  if (!d || !t) {
    rows.push([`${dart} ↔ ${ts}`, d ? d.length : '—', t ? t.length : '—', '—', 'skipped (missing)'])
    continue
  }
  const dn = new Set(d.map(normalise))
  const tn = new Set(t.map(normalise))
  const onlyDart = d.filter((n) => !tn.has(normalise(n)))
  const onlyTs = t.filter((n) => !dn.has(normalise(n)))
  const matched = d.length - onlyDart.length
  const ok = onlyDart.length === 0 && onlyTs.length === 0
  if (!ok) differences++
  rows.push([
    `${dart} ↔ ${ts}`,
    d.length,
    t.length,
    matched,
    ok ? 'in parity' : `${onlyDart.length} Dart-only, ${onlyTs.length} TS-only`,
  ])
  if (!ok) details.push({ pair: `${dart} ↔ ${ts}`, onlyDart, onlyTs })
}

const header = ['module (Dart ↔ TS)', 'Dart', 'TS', 'same name', 'status']
const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)))
const line = (cells) => `| ${cells.map((c, i) => String(c).padEnd(widths[i])).join(' | ')} |`
console.log(line(header))
console.log(`|${widths.map((w) => '-'.repeat(w + 2)).join('|')}|`)
for (const r of rows) console.log(line(r))

if (verbose) {
  for (const { pair, onlyDart, onlyTs } of details) {
    console.log(`\n${pair}`)
    for (const n of onlyDart) console.log(`  Dart only: ${n}`)
    for (const n of onlyTs) console.log(`  TS only:   ${n}`)
  }
}

if (differences === 0) {
  console.log('\nparity: every paired module proves the same named behaviours.')
} else if (strict) {
  console.error(`\nparity: ${differences} module pair(s) differ (--strict).`)
  process.exit(1)
} else {
  console.log(
    `\nparity: ${differences} module pair(s) differ — reported only; run with --strict (or --verbose) for the names.`,
  )
}
