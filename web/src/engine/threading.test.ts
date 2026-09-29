import { describe, expect, test } from 'vitest'
import { parseName } from './filename'
import {
  DEADLINE_MS,
  type Effect,
  FLASH_MS,
  initial,
  languageName,
  type Machine,
  numeral,
  phaseLabel,
  reduce,
  SWEEP_HOLD,
  type ThreadingEvent,
} from './threading'
import { ANONYMOUS } from './tickets'
import type { MovieHash, Quota, ScoredCandidate } from './types'

const HASH = '8e245d9679d31e12' as MovieHash
const PARSED = parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv')
const SIGNED_IN: Quota = { ...ANONYMOUS, signedIn: true, remaining: 7, total: 10 }

const sc = (id: string, match: boolean, autoPick: boolean): ScoredCandidate => ({
  candidate: {
    provider: 'opensubtitles',
    id,
    language: 'en',
    release: 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE',
    downloadCount: 100,
    hearingImpaired: false,
    moviehashMatch: match,
    machineTranslated: false,
    aiTranslated: false,
    fps: 23.976,
    feature: null,
  },
  score: match ? 1414 : 414,
  reasons: [],
  autoPick,
})
const A = sc('1234567', true, true)
const D = sc('1234570', false, false)

/** Run a script of events, collecting every effect. */
function run(events: ThreadingEvent[], opts = { subdlEnabled: false, language: 'en' }) {
  let m: Machine = initial(opts, ANONYMOUS)
  const effects: Effect[] = []
  for (const e of events) {
    const step = reduce(m, e)
    m = step.machine
    effects.push(...step.effects)
  }
  return { m, s: m.state, effects }
}

const open = (quota: Quota = SIGNED_IN): ThreadingEvent => ({
  type: 'open',
  at: 0,
  parsed: PARSED,
  quota,
})
const toSearch = (quota: Quota = SIGNED_IN): ThreadingEvent[] => [
  open(quota),
  { type: 'hashed', at: 40, hash: HASH },
]
const kinds = (effects: Effect[]) => effects.map((e) => e.kind)

describe('leader state machine', () => {
  test('starts hashing on open with the numeral 3', () => {
    const { s, effects } = run([open()])
    expect(s.phase).toBe('hashing')
    expect(numeral(s.phase)).toBe('3')
    expect(kinds(effects)).toEqual(['announce', 'hash'])
  })

  test('moves to searching by hash when the hash is ready', () => {
    const { s, effects } = run(toSearch())
    expect(s.phase).toBe('searching')
    expect(s.hash).toBe(HASH)
    expect(numeral(s.phase)).toBe('2')
    expect(effects).toContainEqual({ kind: 'search', rung: 'hash' })
  })

  test('skips silently to a filename search when the file is too small', () => {
    const { s, effects } = run([open(), { type: 'hashed', at: 5, hash: null }])
    expect(s.phase).toBe('searching')
    expect(s.failure).toBeNull()
    expect(s.hash).toBeNull()
    expect(effects).toContainEqual({ kind: 'search', rung: 'filename' })
  })

  test('advances the sweep only while the phase is pending', () => {
    expect(run([open(), { type: 'tick', at: 400 }]).s.sweep).toBeCloseTo(0.4, 6)
    expect(run([open(), { type: 'tick', at: 1900 }]).s.sweep).toBe(SWEEP_HOLD)
    const reported = run([
      open(),
      { type: 'progress', at: 10, value: 0.5 },
      { type: 'tick', at: 20 },
    ])
    expect(reported.s.sweep).toBe(0.5)
  })

  test('freezes the sweep when the search rejects', () => {
    const { s } = run([
      ...toSearch(),
      { type: 'tick', at: 340 },
      { type: 'failed', at: 540, failure: 'offline' },
      { type: 'tick', at: 3000 },
      { type: 'progress', at: 3100, value: 0.9 },
    ])
    expect(s.failure).toBe('offline')
    expect(s.sweep).toBeCloseTo(0.5, 6)
  })

  test('never jumps the sweep to full or resets it to zero on a stall', () => {
    const { s } = run([...toSearch(), { type: 'failed', at: 5040, failure: 'rate-limited' }])
    expect(s.sweep).toBe(SWEEP_HOLD)
    expect(s.sweep).toBeLessThan(1)
    expect(s.sweep).toBeGreaterThan(0)
  })

  test('times out each phase at its deadline', () => {
    const hashing = run([open(), { type: 'tick', at: (DEADLINE_MS.hashing ?? 0) + 1 }])
    expect(hashing.s.failure).toBe('timeout')
    expect(DEADLINE_MS).toEqual({ hashing: 2000, searching: 8000, downloading: 15000 })
    const searching = run([...toSearch(), { type: 'tick', at: 8000 }])
    expect(searching.s.failure).toBeNull()
    const late = run([...toSearch(), { type: 'tick', at: 8041 }])
    expect(late.s.failure).toBe('timeout')
    expect(kinds(late.effects)).toContain('abort')
    const dl = run([
      ...toSearch(),
      { type: 'searched', at: 100, candidates: [A] },
      { type: 'tick', at: 15101 },
    ])
    expect(dl.s.phase).toBe('downloading')
    expect(dl.s.failure).toBe('timeout')
  })

  test('orders the fallback rows filename, subdl, manual, skip', () => {
    const { s } = run([...toSearch(), { type: 'searched', at: 300, candidates: [] }], {
      subdlEnabled: true,
      language: 'en',
    })
    expect(s.failure).toBe('no-results')
    expect(s.next).toEqual(['filename-search', 'subdl', 'manual', 'skip'])
  })

  test('omits subdl when it is not enabled and rungs already tried', () => {
    const { s } = run([
      open(),
      { type: 'hashed', at: 5, hash: null },
      { type: 'searched', at: 300, candidates: [] },
    ])
    expect(s.next).toEqual(['manual', 'skip'])
  })

  test('inserts sign-in first when the download is unauthorized', () => {
    const { s } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'failed', at: 400, failure: 'unauthorized' },
    ])
    expect(s.next[0]).toBe('sign-in')
  })

  test('inserts sign-in first when the quota is exhausted', () => {
    const { s } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      {
        type: 'failed',
        at: 400,
        failure: 'quota-exhausted',
        quota: { ...SIGNED_IN, remaining: 0 },
      },
    ])
    expect(s.next).toEqual(['sign-in', 'filename-search', 'manual', 'skip'])
    expect(s.quota.remaining).toBe(0)
  })

  test('offers a retry after a rate limit or going offline', () => {
    const { s } = run([...toSearch(), { type: 'failed', at: 400, failure: 'rate-limited' }])
    expect(s.next).toEqual(['retry', 'filename-search', 'manual', 'skip'])
  })

  test('publishes the fallback rows within 500 ms of the failure', () => {
    const at = 1234
    const { s, m } = run([...toSearch(), { type: 'failed', at, failure: 'offline' }])
    expect(s.next.length).toBeGreaterThan(0)
    expect(m.phaseStartedAt).toBeLessThanOrEqual(at)
  })

  test('auto-picks rank 1 and downloads when signed in with tickets', () => {
    const { s, effects } = run([...toSearch(), { type: 'searched', at: 300, candidates: [A, D] }])
    expect(s.phase).toBe('downloading')
    expect(numeral(s.phase)).toBe('1')
    expect(s.picked).toBe(A)
    expect(effects.filter((e) => e.kind === 'download')).toEqual([
      { kind: 'download', candidate: A },
    ])
  })

  test('stalls with the sign-in sentence instead of downloading when signed out', () => {
    const { s, effects } = run([
      ...toSearch(ANONYMOUS),
      { type: 'searched', at: 300, candidates: [A] },
    ])
    expect(s.phase).toBe('downloading')
    expect(s.failure).toBe('unauthorized')
    expect(s.next).toEqual(['sign-in', 'filename-search', 'manual', 'skip'])
    expect(kinds(effects)).not.toContain('download')
    expect(effects).toContainEqual({
      kind: 'announce',
      text: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
    })
  })

  test('makes no request when no tickets are left', () => {
    const { s, effects } = run([
      ...toSearch({ ...SIGNED_IN, remaining: 0 }),
      { type: 'searched', at: 300, candidates: [A] },
    ])
    expect(s.failure).toBe('quota-exhausted')
    expect(kinds(effects)).not.toContain('download')
  })

  test('resumes the pending download after sign-in', () => {
    const { s, effects } = run([
      ...toSearch(ANONYMOUS),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'choose', at: 400, action: 'sign-in' },
      { type: 'signed-in', at: 900, quota: SIGNED_IN },
    ])
    expect(kinds(effects)).toContain('show-sign-in')
    expect(s.phase).toBe('downloading')
    expect(s.failure).toBeNull()
    expect(effects.at(-1)).toEqual({ kind: 'download', candidate: A })
    const idle = run([open(), { type: 'signed-in', at: 5, quota: SIGNED_IN }])
    expect(idle.s.phase).toBe('hashing')
    expect(idle.s.quota).toBe(SIGNED_IN)
  })

  test('retries the download exactly once on a 410', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'failed', at: 500, failure: 'link-expired' },
    ])
    expect(s.failure).toBeNull()
    expect(effects.filter((e) => e.kind === 'download')).toHaveLength(2)
    const twice = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'failed', at: 500, failure: 'link-expired' },
      { type: 'failed', at: 700, failure: 'link-expired' },
    ])
    expect(twice.s.failure).toBe('link-expired')
    expect(twice.effects.filter((e) => e.kind === 'download')).toHaveLength(2)
  })

  test('stalls with no results when only machine translations were found', () => {
    const { s } = run([...toSearch(), { type: 'searched', at: 300, candidates: [D] }])
    expect(s.failure).toBe('no-results')
    expect(s.candidates).toEqual([D])
  })

  test('lets a tap override the auto-pick and cancel the download in flight', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A, D] },
      { type: 'pick', at: 350, candidate: D },
    ])
    expect(s.picked).toBe(D)
    expect(kinds(effects).slice(-3)).toEqual(['abort', 'announce', 'download'])
    expect(run([open(), { type: 'pick', at: 5, candidate: D }]).s.picked).toBeNull()
  })

  test('resolves a cancel to done and still starts playback', () => {
    const { s, effects } = run([...toSearch(), { type: 'cancel', at: 200 }])
    expect(s.phase).toBe('done')
    expect(s.picked).toBeNull()
    expect(effects).toContainEqual({ kind: 'play', withSubtitles: false })
    expect(kinds(effects)).toContain('abort')
    expect(run([{ type: 'cancel', at: 0 }]).s.phase).toBe('idle')
  })

  test('resolves skip to done without subtitles', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'failed', at: 400, failure: 'offline' },
      { type: 'choose', at: 500, action: 'skip' },
    ])
    expect(s.phase).toBe('done')
    expect(effects).toContainEqual({ kind: 'play', withSubtitles: false })
    expect(effects.at(-1)).toEqual({ kind: 'announce', text: 'Playing without subtitles' })
    expect(run([{ type: 'choose', at: 0, action: 'skip' }]).s.phase).toBe('idle')
  })

  test('announces each phase once', () => {
    const { effects } = run([
      ...toSearch(),
      { type: 'tick', at: 100 },
      { type: 'tick', at: 200 },
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'tick', at: 400 },
      { type: 'attached', at: 900, inSync: true },
    ])
    const said = effects.flatMap((e) => (e.kind === 'announce' ? [e.text] : []))
    expect(said).toEqual([
      'Reading the print',
      'Searching subtitles',
      'Downloading English subtitles',
      'Subtitles attached, in sync',
    ])
  })

  test('flashes for 66 ms and then plays with subtitles', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'attached', at: 900, inSync: false, quota: { ...SIGNED_IN, remaining: 6 } },
      { type: 'flashed', at: 966 },
    ])
    expect(s.phase).toBe('done')
    expect(s.quota.remaining).toBe(6)
    expect(effects).toContainEqual({ kind: 'flash', ms: FLASH_MS })
    expect(effects).toContainEqual({ kind: 'announce', text: 'Subtitles attached, check sync' })
    expect(effects.at(-1)).toEqual({ kind: 'play', withSubtitles: true })
  })

  test('reattaches from the cache without a search', () => {
    const { s, effects } = run([open(), { type: 'attached', at: 30, inSync: true }])
    expect(s.phase).toBe('flash')
    expect(kinds(effects)).not.toContain('search')
  })

  test('runs a manual search with the typed query and repeats it on retry', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [] },
      { type: 'choose', at: 400, action: 'manual' },
      { type: 'manual-query', at: 900, query: 'the third man' },
      { type: 'failed', at: 1000, failure: 'offline' },
      { type: 'choose', at: 1100, action: 'retry' },
    ])
    expect(kinds(effects)).toContain('show-manual')
    expect(s.phase).toBe('searching')
    expect(effects.at(-1)).toEqual({ kind: 'search', rung: 'manual', query: 'the third man' })
  })

  test('retries a stalled download or a stalled search on the same rung', () => {
    const dl = run([
      ...toSearch(),
      { type: 'searched', at: 300, candidates: [A] },
      { type: 'failed', at: 400, failure: 'offline' },
      { type: 'choose', at: 500, action: 'retry' },
    ])
    expect(dl.effects.at(-1)).toEqual({ kind: 'download', candidate: A })
    const hashStall = run([
      open(),
      { type: 'tick', at: 2100 },
      { type: 'choose', at: 2200, action: 'retry' },
    ])
    expect(hashStall.effects.at(-1)).toEqual({ kind: 'search', rung: 'filename' })
  })

  test('runs the filename and Subdl rungs when chosen', () => {
    const base = [...toSearch(), { type: 'searched', at: 300, candidates: [] }] as ThreadingEvent[]
    const byName = run([...base, { type: 'choose', at: 400, action: 'filename-search' }])
    expect(byName.effects.at(-1)).toEqual({ kind: 'search', rung: 'filename' })
    const subdl = run([...base, { type: 'choose', at: 400, action: 'subdl' }], {
      subdlEnabled: true,
      language: 'en',
    })
    expect(subdl.effects.at(-1)).toEqual({ kind: 'search', rung: 'subdl' })
    const off = run([...base, { type: 'choose', at: 400, action: 'subdl' }])
    expect(off.s.failure).toBe('no-results')
  })

  test('ignores fallback choices and results that do not belong to the current phase', () => {
    expect(
      run([...toSearch(), { type: 'choose', at: 100, action: 'manual' }]).effects.at(-1)?.kind,
    ).toBe('search')
    expect(run([...toSearch(), { type: 'choose', at: 100, action: 'webcodecs' }]).s.phase).toBe(
      'searching',
    )
    const stalled = run([...toSearch(), { type: 'failed', at: 50, failure: 'offline' }])
    expect(reduce(stalled.m, { type: 'choose', at: 60, action: 'webcodecs' }).machine).toBe(
      stalled.m,
    )
    expect(run([open(), { type: 'searched', at: 5, candidates: [A] }]).s.phase).toBe('hashing')
    expect(run([...toSearch(), { type: 'hashed', at: 50, hash: HASH }]).s.phase).toBe('searching')
    expect(run([open(), { type: 'flashed', at: 5 }]).s.phase).toBe('hashing')
    expect(run([{ type: 'attached', at: 5, inSync: true }]).s.phase).toBe('idle')
    expect(run([{ type: 'manual-query', at: 5, query: 'x' }]).s.phase).toBe('idle')
    expect(run([{ type: 'tick', at: 5 }]).s.phase).toBe('idle')
    expect(run([{ type: 'failed', at: 5, failure: 'offline' }]).s.failure).toBeNull()
    expect(run([{ type: 'progress', at: 5, value: 1 }]).m.progress).toBe(0)
  })

  test('labels the numerals and phases in plain words', () => {
    expect(numeral('idle')).toBe('')
    expect(numeral('probing')).toBe('3')
    expect(languageName('hi')).toBe('Hindi')
    expect(languageName('not a code!')).toBe('NOT A CODE!')
    const done = run([...toSearch(), { type: 'cancel', at: 10 }]).m
    expect(phaseLabel(done)).toBe('Playing without subtitles')
    expect(phaseLabel(initial({ subdlEnabled: false, language: 'en' }, ANONYMOUS))).toBe('')
  })

  test('re-runs the filename rung when another print is requested after playback began', () => {
    const { s, effects } = run([
      ...toSearch(),
      { type: 'cancel', at: 100 },
      { type: 'research', at: 5000 },
    ])
    expect(s.phase).toBe('searching')
    expect(effects.at(-1)).toEqual({ kind: 'search', rung: 'filename' })
    expect(run([...toSearch(), { type: 'research', at: 200 }]).s.phase).toBe('searching')
  })
})
