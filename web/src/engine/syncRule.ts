// The sync rule (IMPLEMENTATION-PROMPT §6.8). Positive means the subtitles appear later.

import { signed } from './timecode'
import type { MovieHash, StoredOffset } from './types'

export const DETENT = 0.05 // seconds
export const RANGE = 2 // ± seconds
export const STEP = 0.05
export const SHIFT_STEP = 0.5

/** Round half away from zero, like Dart's num.round(), so both tiers agree on ±x.x25 values. */
const roundAway = (x: number): number => Math.sign(x) * Math.round(Math.abs(x))

/** Nearest 50 ms detent (ROUND, not floor), clamped to ±2.00, free of float dust. */
export function snap(v: number): number {
  // Settle float dust first (0.375 / 0.05 = 7.4999…) so exact halves really are halves.
  const detents = roundAway(Math.round((v / DETENT) * 1e6) / 1e6)
  const clamped = Math.min(RANGE, Math.max(-RANGE, detents * DETENT))
  return Math.round(clamped * 100) / 100 + 0 // + 0 turns -0 into 0
}

export interface StepKey {
  isK: boolean // K steps later, J steps earlier
  shift: boolean // Shift steps 500 ms
}

export function step(v: number, k: StepKey): number {
  return snap(v + (k.shift ? SHIFT_STEP : STEP) * (k.isK ? 1 : -1))
}

export const reset = (): number => 0

/** The readout beside the gate: `SYNC +0.35`. */
export const readout = (v: number): string => `SYNC ${signed(v)}`

/** aria-valuetext for the slider: "plus 0.35 seconds"; zero reads "plus 0.00 seconds". */
export function ariaValueText(v: number): string {
  const s = snap(v)
  return `${s < 0 ? 'minus' : 'plus'} ${Math.abs(s).toFixed(2)} seconds`
}

export const toMs = (v: number): number => Math.round(snap(v) * 1000)

/** Offsets remembered per moviehash: restored on the next open of the SAME file. */
export class OffsetBook {
  readonly #byHash = new Map<string, number>()

  constructor(stored: StoredOffset[] = []) {
    for (const o of stored) this.#byHash.set(o.hash, snap(o.delayMs / 1000))
  }

  recall(hash: MovieHash | null): number {
    return hash === null ? 0 : (this.#byHash.get(hash) ?? 0)
  }

  remember(hash: MovieHash, v: number): StoredOffset {
    const s = snap(v)
    if (s === 0) this.#byHash.delete(hash)
    else this.#byHash.set(hash, s)
    return { hash, delayMs: toMs(s) }
  }
}
