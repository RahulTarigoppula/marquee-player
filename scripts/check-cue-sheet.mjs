#!/usr/bin/env node
// Cue sheet in sync (G10). design/cue-sheet.json is the ONE keyboard map: it feeds the `?` overlay
// at runtime and the README "Keyboard (Windows)" table, which is generated from it.
//
//   node scripts/check-cue-sheet.mjs          validate the JSON and fail if the README block is stale
//   node scripts/check-cue-sheet.mjs --write  validate, then regenerate the README block in place
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const SHEET = join(root, 'design', 'cue-sheet.json')
const README = join(root, 'README.md')
const START = '<!-- cue-sheet:start -->'
const END = '<!-- cue-sheet:end -->'
const write = process.argv.includes('--write')

const errors = []

function validate(sheet) {
  if (sheet === null || typeof sheet !== 'object' || Array.isArray(sheet)) {
    errors.push('the root must be an object')
    return []
  }
  if (sheet.format !== 'marquee.cue-sheet.v1') {
    errors.push(`format must be "marquee.cue-sheet.v1", got ${JSON.stringify(sheet.format)}`)
  }
  if (!Array.isArray(sheet.cues) || sheet.cues.length === 0) {
    errors.push('cues must be a non-empty array')
    return []
  }
  const ids = new Map()
  const keys = new Map()
  sheet.cues.forEach((cue, i) => {
    const at = `cues[${i}]`
    if (cue === null || typeof cue !== 'object') {
      errors.push(`${at} must be an object`)
      return
    }
    const extra = Object.keys(cue).filter((k) => !['id', 'keys', 'action'].includes(k))
    if (extra.length) errors.push(`${at} has unknown field(s): ${extra.join(', ')}`)
    if (typeof cue.id !== 'string' || !/^[a-z][A-Za-z0-9]*$/.test(cue.id)) {
      errors.push(`${at}.id must be a camelCase string, got ${JSON.stringify(cue.id)}`)
    } else if (ids.has(cue.id)) {
      errors.push(`${at}.id "${cue.id}" duplicates cues[${ids.get(cue.id)}]`)
    } else {
      ids.set(cue.id, i)
    }
    if (typeof cue.action !== 'string' || cue.action.trim() === '') {
      errors.push(`${at}.action must be a non-empty string`)
    }
    if (!Array.isArray(cue.keys) || cue.keys.length === 0) {
      errors.push(`${at}.keys must be a non-empty array`)
      return
    }
    for (const k of cue.keys) {
      if (typeof k !== 'string' || k.trim() === '' || k !== k.trim()) {
        errors.push(`${at}.keys has an invalid key ${JSON.stringify(k)}`)
        continue
      }
      const norm = k.toLowerCase()
      if (keys.has(norm)) {
        errors.push(`${at} key "${k}" is already bound by "${keys.get(norm)}"`)
      } else {
        keys.set(norm, cue.id ?? at)
      }
    }
  })
  return sheet.cues
}

const GLYPH = {
  ArrowLeft: '←',
  ArrowRight: '→',
  ArrowUp: '↑',
  ArrowDown: '↓',
  Escape: 'Esc',
}

function keyLabel(key) {
  return key
    .split('+')
    .map((part) => GLYPH[part] ?? part)
    .join('+')
}

export function renderTable(cues) {
  const cell = (s) => s.replace(/\|/g, '\\|')
  const lines = [
    START,
    '<!-- Generated from design/cue-sheet.json by `node scripts/check-cue-sheet.mjs --write`. Do not edit by hand. -->',
    '',
    '| Key | Action |',
    '|---|---|',
    ...cues.map(
      (c) => `| ${c.keys.map((k) => `\`${cell(keyLabel(k))}\``).join(' / ')} | ${cell(c.action)} |`,
    ),
    '',
    END,
  ]
  return lines.join('\n')
}

let sheet
try {
  sheet = JSON.parse(readFileSync(SHEET, 'utf8'))
} catch (e) {
  console.error(`cue sheet: cannot read ${SHEET}: ${e.message}`)
  process.exit(1)
}
const cues = validate(sheet)
if (errors.length) {
  console.error('cue sheet: design/cue-sheet.json is invalid:')
  for (const e of errors) console.error(`  - ${e}`)
  process.exit(1)
}

const readme = readFileSync(README, 'utf8').replace(/\r\n/g, '\n')
const start = readme.indexOf(START)
const end = readme.indexOf(END)
if (start === -1 || end === -1 || end < start) {
  console.error(`cue sheet: README.md must contain ${START} … ${END} markers.`)
  process.exit(1)
}
const current = readme.slice(start, end + END.length)
const wanted = renderTable(cues)

if (current === wanted) {
  console.log(`cue sheet: ${cues.length} cues, README table in sync.`)
} else if (write) {
  writeFileSync(README, readme.slice(0, start) + wanted + readme.slice(end + END.length))
  console.log(`cue sheet: ${cues.length} cues, README table regenerated.`)
} else {
  console.error(
    'cue sheet: the README "Keyboard (Windows)" table differs from design/cue-sheet.json.\n' +
      '  Run `node scripts/check-cue-sheet.mjs --write` and commit the result.',
  )
  process.exit(1)
}
