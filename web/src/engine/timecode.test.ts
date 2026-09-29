import { describe, expect, test } from 'vitest'
import {
  auditoriumFolio,
  condenseTitle,
  fmt,
  folio,
  signed,
  THREADING_FOLIO,
  withSuffixes,
} from './timecode'

describe('folio timecodes', () => {
  test('floors the position and ceils the remaining time', () => {
    expect(folio(4364.4, 9663)).toBe('01:12:44 · −01:28:19')
  })

  test('prints the full duration as remaining at the start', () => {
    expect(folio(0, 9663)).toBe('00:00:00 · −02:41:03')
  })

  test('prints zero remaining at the end', () => {
    expect(folio(9663, 9663)).toBe('02:41:03 · −00:00:00')
  })

  test('never shows an off-by-one just before a whole second', () => {
    expect(folio(59.999, 61)).toBe('00:00:59 · −00:00:02')
    expect(folio(3599.2, 3600)).toBe('00:59:59 · −00:00:01')
  })

  test('never wraps at 24 hours', () => {
    expect(folio(45000, 45000)).toBe('12:30:00 · −00:00:00')
    expect(fmt(108000)).toBe('30:00:00')
  })

  test('prints an em dash for an unknown duration', () => {
    expect(folio(45, null)).toBe('00:00:45 · —')
    expect(folio(45, Number.POSITIVE_INFINITY)).toBe('00:00:45 · —')
    expect(folio(45, Number.NaN)).toBe('00:00:45 · —')
    expect(folio(45, 0)).toBe('00:00:45 · —')
    expect(folio(Number.POSITIVE_INFINITY, 10)).toBe('00:00:00 · −00:00:10')
  })

  test('uses the minus sign U+2212, not a hyphen', () => {
    expect(folio(0, 10)).toContain('−')
    expect(folio(0, 10)).not.toContain('-')
  })

  test('clamps a position past the end to zero remaining', () => {
    expect(folio(100, 90)).toBe('00:01:40 · −00:00:00')
    expect(fmt(-3)).toBe('00:00:00')
  })

  test('clamps a negative position to zero', () => {
    expect(folio(-3, 10)).toBe('00:00:00 · −00:00:10')
    expect(fmt(-5)).toBe('00:00:00')
  })

  test('appends suffixes without replacing the timecode', () => {
    const base = folio(4364.4, 9663)
    expect(withSuffixes(base, { speed: 2 })).toBe(`${base} · 2.0×`)
    expect(withSuffixes(base, { looping: true })).toBe(`${base} · A–B`)
    expect(withSuffixes(base, { subDelay: 0.35 })).toBe(`${base} · SUB +0.35`)
    expect(withSuffixes(base, { subDelay: -0.35 })).toBe(`${base} · SUB −0.35`)
    expect(withSuffixes(base, { speed: 1, looping: false, subDelay: 0 })).toBe(base)
  })

  test('prints the threading folio', () => {
    expect(THREADING_FOLIO).toBe('REEL 01 · THREADING')
  })

  test('uppercases the title and condenses it to 40 characters', () => {
    expect(auditoriumFolio('The Third Man', 4364.4, 9663)).toBe(
      'REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19',
    )
    const long = condenseTitle('a'.repeat(60))
    expect(long).toHaveLength(40)
    expect(long.endsWith('…')).toBe(true)
    expect(auditoriumFolio(null, 0, null)).toBe('REEL 01 · 00:00:00 · —')
  })

  test('signs values with plus or the minus sign', () => {
    expect(signed(0)).toBe('+0.00')
    expect(signed(0.35)).toBe('+0.35')
    expect(signed(-2)).toBe('−2.00')
  })
})
