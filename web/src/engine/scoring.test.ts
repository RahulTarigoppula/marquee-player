import { describe, expect, test } from 'vitest'
import { parseName } from './filename'
import { eqi, rank, score, subdlCandidate } from './scoring'
import type { Candidate, ParsedName } from './types'

const FILE = parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv') as ParsedName
const FPS = 23.976

const cand = (id: string, over: Partial<Candidate>): Candidate => ({
  provider: 'opensubtitles',
  id,
  language: 'en',
  release: null,
  downloadCount: 1,
  hearingImpaired: false,
  moviehashMatch: false,
  machineTranslated: false,
  aiTranslated: false,
  fps: FPS,
  feature: null,
  ...over,
})

const A = cand('A', {
  release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
  moviehashMatch: true,
  downloadCount: 12431,
})
const D = cand('D', {
  release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
  downloadCount: 51000,
})
const C = cand('C', {
  release: 'The.Third.Man.1949.BluRay-AMIABLE',
  downloadCount: 902,
  hearingImpaired: true,
  fps: 25,
})
const B = cand('B', {
  release: 'The.Third.Man.1949.1080p.WEB-DL.H264-NTb',
  downloadCount: 4102,
  hearingImpaired: true,
})
const E = cand('E', {
  release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
  moviehashMatch: true,
  machineTranslated: true,
  downloadCount: 99999,
})

const s = (c: Candidate, preferHI = false) => score(c, FILE, FPS, preferHI).score
const opts = { parsed: FILE, containerFps: FPS, preferHI: false, languages: ['en'] }

describe('scoring', () => {
  test('scores the hash-matched house release at 1414.09', () => {
    expect(s(A)).toBeCloseTo(1414.09, 2)
    expect(score(A, FILE, FPS, false).reasons).toEqual([
      'hash +1000',
      'group +200',
      'source +100',
      'res +50',
      'codec +20',
      'fps +40',
      'downloads +4.09',
    ])
  })

  test('scores the same release without a hash match at 414.71', () => {
    expect(s(D)).toBeCloseTo(414.71, 2)
  })

  test('lets a release-group match beat an fps mismatch at 232.96', () => {
    expect(s(C)).toBeCloseTo(232.96, 2)
  })

  test('treats H264 and x264 as different codecs at 63.61', () => {
    expect(s(B)).toBeCloseTo(63.61, 2)
    expect(score(B, FILE, FPS, false).reasons).not.toContain('codec +20')
  })

  test('ranks A, D, C, B and auto-picks A', () => {
    const ranked = rank([B, C, D, A], opts)
    expect(ranked.map((r) => r.candidate.id)).toEqual(['A', 'D', 'C', 'B'])
    expect(ranked.map((r) => r.autoPick)).toEqual([true, false, false, false])
  })

  test('lists a machine-translated candidate below A but never auto-picks it', () => {
    expect(s(E)).toBeLessThan(1414)
    const ranked = rank([E, A, D], opts)
    expect(ranked[0]?.candidate.id).toBe('A')
    expect(ranked.find((r) => r.candidate.id === 'E')?.autoPick).toBe(false)
    expect(score(E, FILE, FPS, false).reasons).toContain('machine -500')
    const ai = cand('AI', { aiTranslated: true, downloadCount: 10 })
    expect(rank([ai], opts)[0]?.autoPick).toBe(false)
  })

  test('auto-picks the best human translation when rank 1 is machine-translated', () => {
    const ranked = rank([E, D], opts)
    expect(ranked[0]?.candidate.id).toBe('E')
    expect(ranked.find((r) => r.autoPick)?.candidate.id).toBe('D')
    expect(rank([E], opts).some((r) => r.autoPick)).toBe(false)
  })

  test('breaks ties on download count', () => {
    const lo = cand('lo', { release: null, fps: null, downloadCount: 10 })
    const hi = cand('hi', { release: null, fps: null, downloadCount: 10 })
    hi.downloadCount = 10
    const ranked = rank([lo, hi], { ...opts, parsed: null, containerFps: null })
    expect(ranked.map((r) => r.score)).toEqual([1, 1])
    const more = cand('more', { release: null, fps: null, downloadCount: 1 })
    const fewer = cand('fewer', { release: null, fps: null, downloadCount: 0 })
    expect(rank([fewer, more], { ...opts, containerFps: null }).map((r) => r.candidate.id)).toEqual(
      ['more', 'fewer'],
    )
  })

  test('keeps every candidate in the ranked list', () => {
    expect(rank([A, B, C, D, E], opts)).toHaveLength(5)
  })

  test('applies the language filter before scoring', () => {
    const hi = cand('HI', { language: 'hi', moviehashMatch: true, downloadCount: 999999 })
    const ranked = rank([hi, B], opts)
    expect(ranked.map((r) => r.candidate.id)).toEqual(['B'])
    expect(rank([hi, B], { ...opts, languages: [] })).toHaveLength(2)
    expect(rank([hi], { ...opts, languages: ['HI'] })).toHaveLength(1)
  })

  test('adds 60 to hearing-impaired candidates when HI is preferred without moving A', () => {
    expect(s(C, true) - s(C)).toBeCloseTo(60, 6)
    expect(s(B, true) - s(B)).toBeCloseTo(60, 6)
    expect(s(A, true)).toBeCloseTo(s(A), 6)
    expect(score(C, FILE, FPS, true).reasons).toContain('HI +30')
    expect(score(C, FILE, FPS, false).reasons).toContain('HI -30')
    const ranked = rank([B, C, D, A], { ...opts, preferHI: true })
    expect(ranked[0]?.candidate.id).toBe('A')
    expect(ranked[0]?.autoPick).toBe(true)
  })

  test('never lights the match bulb for a Subdl candidate', () => {
    const sd = subdlCandidate({
      release_name: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
      language: 'EN',
      url: '/subtitle/1234-5678.zip',
      hi: false,
    })
    expect(sd.moviehashMatch).toBe(false)
    expect(sd.provider).toBe('subdl')
    expect(score(sd, FILE, FPS, false).reasons).not.toContain('hash +1000')
  })

  test('compares tokens case-insensitively and never matches null', () => {
    expect(eqi('BluRay', 'bluray')).toBe(true)
    expect(eqi('x264', 'H264')).toBe(false)
    expect(eqi(null, null)).toBe(false)
    expect(eqi(null, 'x264')).toBe(false)
    expect(eqi('x264', null)).toBe(false)
  })

  test('skips release comparisons when either name is unknown', () => {
    expect(score(A, null, null, false).reasons).toEqual(['hash +1000', 'downloads +4.09'])
    expect(score(cand('n', { release: null }), FILE, null, false).score).toBe(0)
  })
})
