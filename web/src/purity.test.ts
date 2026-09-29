import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'

const SRC = dirname(fileURLToPath(import.meta.url))
const files = (dir: string, re: RegExp): string[] =>
  readdirSync(join(SRC, dir), { recursive: true, encoding: 'utf8' })
    .filter((f) => re.test(f))
    .map((f) => join(dir, f))
const read = (f: string) => readFileSync(join(SRC, f), 'utf8')
const code = (f: string) =>
  read(f)
    .replace(/\/\/.*$/gm, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')

describe('structural laws', () => {
  test('keeps the engine free of DOM, window and fetch', () => {
    const engine = files('engine', /^[^.]+\.ts$/).filter((f) => !f.endsWith('api.ts'))
    expect(engine.length).toBeGreaterThan(8)
    for (const f of engine)
      expect(code(f), f).not.toMatch(/\b(document|window|fetch|localStorage)\b/)
    expect(code('engine/api.ts')).not.toMatch(/\b(document|window)\b|[^.]\bfetch\(/)
  })

  test('never writes markup through innerHTML', () => {
    for (const f of files('.', /\.ts$/).filter((x) => !x.endsWith('.test.ts'))) {
      expect(code(f), f).not.toMatch(/innerHTML|outerHTML|insertAdjacentHTML/)
    }
  })

  test('uses token variables instead of hard-coded hex colours in CSS', () => {
    expect(read('styles/app.css')).not.toMatch(/#[0-9a-fA-F]{3,8}\b/)
  })

  test('drives the lighting with one --house tween', () => {
    const css = read('styles/app.css')
    expect(css.match(/transition:\s*--house/g)).toHaveLength(1)
  })
})
