// Candidate scoring (IMPLEMENTATION-PROMPT §6.4) — the frozen weights.
// eqi is a case-insensitive EXACT token comparison (R4): x264 and H264 are different codecs.
// If you ever normalise them, every golden in §6.4 changes in the same commit.
import { parseName } from './filename'
import type { Candidate, ParsedName, ScoredCandidate } from './types'

const W_HASH = 1000
const W_GROUP = 200
const W_SOURCE = 100
const W_RES = 50
const W_CODEC = 20
const W_FPS = 40 // ± — a release-group match deliberately outweighs an fps mismatch
const W_HI = 30 // ± depending on the hearing-impaired preference
const W_MACHINE = -500
const FPS_TOLERANCE = 0.01

/** Case-insensitive exact equality; false when either side is null. */
export function eqi(a: string | null, b: string | null): boolean {
  return a !== null && b !== null && a.toLowerCase() === b.toLowerCase()
}

export function score(
  c: Candidate,
  n: ParsedName | null,
  containerFps: number | null,
  preferHI: boolean,
): { score: number; reasons: string[] } {
  let s = 0
  const why: string[] = []
  if (c.moviehashMatch) {
    s += W_HASH
    why.push('hash +1000')
  }
  const r = c.release === null ? null : parseName(c.release)
  if (n !== null && r !== null) {
    if (eqi(r.group, n.group)) {
      s += W_GROUP
      why.push('group +200')
    }
    if (eqi(r.source, n.source)) {
      s += W_SOURCE
      why.push('source +100')
    }
    if (eqi(r.resolution, n.resolution)) {
      s += W_RES
      why.push('res +50')
    }
    if (eqi(r.videoCodecToken, n.videoCodecToken)) {
      s += W_CODEC
      why.push('codec +20')
    }
  }
  if (containerFps !== null && c.fps !== null) {
    const same = Math.abs(c.fps - containerFps) <= FPS_TOLERANCE
    s += same ? W_FPS : -W_FPS
    why.push(same ? 'fps +40' : 'fps -40')
  }
  if (c.hearingImpaired) {
    s += preferHI ? W_HI : -W_HI
    why.push(preferHI ? 'HI +30' : 'HI -30')
  }
  if (c.machineTranslated || c.aiTranslated) {
    s += W_MACHINE
    why.push('machine -500')
  }
  s += Math.log10(Math.max(c.downloadCount, 1)) // the tie-breaker
  return { score: s, reasons: why }
}

export interface RankOptions {
  parsed: ParsedName | null
  containerFps: number | null
  preferHI: boolean
  /** ISO 639-1 codes, in preference order. Applied BEFORE scoring. Empty = no filter. */
  languages: string[]
}

/**
 * Order every candidate (the list is ordered, never filtered — except by language, which runs
 * before scoring). Ties break on download count. The auto-pick is the highest-ranked candidate
 * that is not machine- or AI-translated; those are listed but never auto-picked.
 */
export function rank(candidates: Candidate[], o: RankOptions): ScoredCandidate[] {
  const langs = o.languages.map((l) => l.toLowerCase())
  const scored = candidates
    .filter((c) => langs.length === 0 || langs.includes(c.language.toLowerCase()))
    .map((candidate) => ({
      candidate,
      ...score(candidate, o.parsed, o.containerFps, o.preferHI),
      autoPick: false,
    }))
    .sort((a, b) => b.score - a.score || b.candidate.downloadCount - a.candidate.downloadCount)
  const pick = scored.find((s) => !s.candidate.machineTranslated && !s.candidate.aiTranslated)
  if (pick) pick.autoPick = true
  return scored
}

/** Subdl has no hash search: its candidates can never light the MATCH bulb. */
export function subdlCandidate(r: {
  release_name: string
  language: string
  url: string
  hi: boolean
}): Candidate {
  return {
    provider: 'subdl',
    id: r.url,
    language: r.language.toLowerCase(),
    release: r.release_name,
    downloadCount: 0,
    hearingImpaired: r.hi,
    moviehashMatch: false,
    machineTranslated: false,
    aiTranslated: false,
    fps: null,
    feature: null,
  }
}
