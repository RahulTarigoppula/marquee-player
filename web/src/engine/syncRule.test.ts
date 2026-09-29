import { describe, expect, test } from 'vitest'
import { ariaValueText, OffsetBook, readout, reset, snap, step, toMs } from './syncRule'
import { withSuffixes } from './timecode'
import type { MovieHash } from './types'

const H = '8e245d9679d31e12' as MovieHash
const OTHER = '0000000000020000' as MovieHash

describe('sync rule', () => {
  test('snaps a drag to the nearest 50 ms detent', () => {
    expect(snap(0.37)).toBe(0.35)
    expect(withSuffixes('x', { subDelay: snap(0.37) })).toBe('x · SUB +0.35')
  })

  test('rounds to the nearest detent instead of flooring', () => {
    expect(snap(0.376)).toBe(0.4)
    expect(withSuffixes('x', { subDelay: snap(0.376) })).toBe('x · SUB +0.40')
  })

  test('clamps a drag past the range to plus or minus two seconds', () => {
    expect(snap(2.4)).toBe(2)
    expect(snap(-9)).toBe(-2)
  })

  test('rounds half away from zero on both sides', () => {
    expect(snap(0.025)).toBe(0.05)
    expect(snap(-0.025)).toBe(-0.05)
    expect(Object.is(snap(-0.01), 0)).toBe(true)
  })

  test('steps later by 50 ms on K', () => {
    expect(step(0.35, { isK: true, shift: false })).toBe(0.4)
  })

  test('steps earlier by 50 ms on J', () => {
    expect(step(0.35, { isK: false, shift: false })).toBe(0.3)
  })

  test('steps 500 ms with Shift', () => {
    expect(step(0.35, { isK: true, shift: true })).toBe(0.85)
    expect(step(-1.8, { isK: false, shift: true })).toBe(-2)
  })

  test('resets to zero and drops the folio suffix', () => {
    const v = reset()
    expect(v).toBe(0)
    expect(readout(v)).toBe('SYNC +0.00')
    expect(withSuffixes('x', { subDelay: v })).toBe('x')
  })

  test('remembers the offset for the same moviehash', () => {
    const book = new OffsetBook()
    expect(book.remember(H, 0.35)).toEqual({ hash: H, delayMs: 350 })
    expect(book.recall(H)).toBe(0.35)
    expect(new OffsetBook([{ hash: H, delayMs: 350 }]).recall(H)).toBe(0.35)
  })

  test('starts a different moviehash at zero', () => {
    const book = new OffsetBook([{ hash: H, delayMs: 350 }])
    expect(book.recall(OTHER)).toBe(0)
    expect(book.recall(null)).toBe(0)
    book.remember(H, 0)
    expect(book.recall(H)).toBe(0)
  })

  test('announces the value as plus or minus seconds', () => {
    expect(ariaValueText(0.35)).toBe('plus 0.35 seconds')
    expect(ariaValueText(-1)).toBe('minus 1.00 seconds')
    expect(ariaValueText(0)).toBe('plus 0.00 seconds')
    expect(readout(-0.5)).toBe('SYNC −0.50')
    expect(toMs(-0.35)).toBe(-350)
  })
})
