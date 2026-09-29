#!/usr/bin/env node
// Engine test parity (IMPLEMENTATION-PROMPT §10.7). The Dart engine (test/engine/*_test.dart) and
// the TS engine (web/src/engine/*.test.ts) are ports of each other and must prove the same
// behaviours under the same test names (compared after normalising case and punctuation).
// A test that genuinely exists on one side only is listed, with a one-line reason, in
// scripts/parity-allow.json.
//
//   node scripts/check-parity.mjs            report, exit 0
//   node scripts/check-parity.mjs --strict   report, exit 1 on any unlisted difference or on an
//                                            allow-list entry that is no longer needed
//   node scripts/check-parity.mjs --verbose  also list every one-sided test name
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const strict = process.argv.includes('--strict')
const verbose = process.argv.includes('--verbose') || strict
const ALLOW_PATH = join(root, 'scripts', 'parity-allow.json')

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

// test('…') / it("…") / test(`…`) and the modifier forms test.skipIf(cond)('…'),
// test.skip('…'), test.only('…'): the first string argument, escapes honoured.
const TEST_CALL =
  /\b(?:test|it)(?:\.\w+(?:\([^()]*\))?)?\s*\(\s*r?(['"`])((?:\\.|(?!\1)[^\\])*)\1/g

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

function loadAllow() {
  if (!existsSync(ALLOW_PATH)) return {}
  const raw = JSON.parse(readFileSync(ALLOW_PATH, 'utf8'))
  const out = {}
  for (const [mod, sides] of Object.entries(raw)) {
    if (mod.startsWith('$')) continue
    const norm = (o) => new Map(Object.entries(o ?? {}).map(([k, v]) => [normalise(k), [k, v]]))
    out[mod] = { dart: norm(sides.dart), ts: norm(sides.ts) }
  }
  return out
}

const allow = loadAllow()
const rows = []
const details = []
const stale = []
let failing = 0

for (const [dart, ts] of PAIRS) {
  const d = load(join(root, 'test', 'engine', `${dart}_test.dart`))
  const t = load(join(root, 'web', 'src', 'engine', `${ts}.test.ts`))
  const pair = `${dart} ↔ ${ts}`
  if (!d || !t) {
    rows.push([pair, d ? d.length : '—', t ? t.length : '—', '—', '—', 'skipped (missing)'])
    continue
  }
  const a = allow[dart] ?? { dart: new Map(), ts: new Map() }
  const dn = new Set(d.map(normalise))
  const tn = new Set(t.map(normalise))
  const onlyDart = d.filter((n) => !tn.has(normalise(n)))
  const onlyTs = t.filter((n) => !dn.has(normalise(n)))
  const unlistedDart = onlyDart.filter((n) => !a.dart.has(normalise(n)))
  const unlistedTs = onlyTs.filter((n) => !a.ts.has(normalise(n)))
  // An allow-list entry is stale when the test is gone or now has a same-named partner.
  for (const [side, map, own, other] of [
    ['Dart', a.dart, dn, tn],
    ['TS', a.ts, tn, dn],
  ]) {
    for (const [key, [name]] of map) {
      if (!own.has(key)) stale.push(`${pair}: ${side} allow-list entry has no such test: ${name}`)
      else if (other.has(key)) stale.push(`${pair}: ${side} allow-list entry now matches: ${name}`)
    }
  }
  const matched = d.length - onlyDart.length
  const allowed = onlyDart.length - unlistedDart.length + (onlyTs.length - unlistedTs.length)
  const ok = unlistedDart.length === 0 && unlistedTs.length === 0
  if (!ok) failing++
  rows.push([
    pair,
    d.length,
    t.length,
    matched,
    allowed,
    ok ? 'ok' : `${unlistedDart.length} Dart-only, ${unlistedTs.length} TS-only unlisted`,
  ])
  details.push({ pair, onlyDart, onlyTs, a })
}

const header = ['module (Dart ↔ TS)', 'Dart', 'TS', 'same name', 'allow-listed', 'status']
const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => String(r[i]).length)))
const line = (cells) => `| ${cells.map((c, i) => String(c).padEnd(widths[i])).join(' | ')} |`
console.log(line(header))
console.log(`|${widths.map((w) => '-'.repeat(w + 2)).join('|')}|`)
for (const r of rows) console.log(line(r))

if (verbose) {
  for (const { pair, onlyDart, onlyTs, a } of details) {
    if (onlyDart.length === 0 && onlyTs.length === 0) continue
    console.log(`\n${pair}`)
    const mark = (map, n) => (map.has(normalise(n)) ? 'allowed ' : 'UNLISTED')
    for (const n of onlyDart) console.log(`  ${mark(a.dart, n)} Dart only: ${n}`)
    for (const n of onlyTs) console.log(`  ${mark(a.ts, n)} TS only:   ${n}`)
  }
}
for (const s of stale) console.log(`\nstale: ${s}`)

const bad = failing > 0 || stale.length > 0
if (!bad) {
  console.log('\nparity: every paired module proves the same named behaviours (one-sided tests allow-listed).')
} else if (strict) {
  console.error(
    `\nparity: ${failing} module pair(s) with unlisted differences, ${stale.length} stale allow-list entr${stale.length === 1 ? 'y' : 'ies'} (--strict).`,
  )
  process.exit(1)
} else {
  console.log(
    `\nparity: ${failing} module pair(s) with unlisted differences, ${stale.length} stale allow-list entries — reported only; --strict fails on them.`,
  )
}
