// The leader state machine (IMPLEMENTATION-PROMPT §6.5). Pure: events in, (machine, effects)
// out. The driver (main.ts) performs the effects and feeds their results back as events.
// Each numeral is a promise, and the sweep is driven by that promise's progress:
//   - it advances only while the phase is pending, and FREEZES on failure (never 1, never 0);
//   - every phase has a deadline (hashing 2 s, searching 8 s, downloading 15 s) → a stall;
//   - a stall publishes next[] in a fixed order, sign-in inserted first when it would help;
//   - exactly ONE automatic retry exists: a 410 on the download link re-issues the download.
import type {
  LeaderPhase,
  MovieHash,
  NextAction,
  ParsedName,
  Quota,
  ScoredCandidate,
  ThreadingFailure,
  ThreadingState,
} from './types'

export const DEADLINE_MS: Readonly<Partial<Record<LeaderPhase, number>>> = {
  hashing: 2000,
  searching: 8000,
  downloading: 15000,
}
export const SWEEP_MS = 1000 // one numeral sweeps in 1000 ms, linear
export const SWEEP_HOLD = 0.96 // a pending phase never shows a finished sweep
export const FLASH_MS = 66 // the black flash before the first frame

export type SearchRung = 'hash' | 'filename' | 'subdl' | 'manual'

export interface Machine {
  state: ThreadingState
  phaseStartedAt: number
  progress: number // real progress reported by the pending phase, 0..1
  stalledIn: 'search' | 'download' | null
  rung: SearchRung | null
  query: string | null // the last manual query, so 'retry' can repeat it
  tried: SearchRung[]
  retried410: boolean
  /** "Find another print": list the results for a pick instead of auto-downloading one. */
  listOnly: boolean
  /** The file_id already attached, never offered again by "Find another print". */
  exclude: string | null
  subdlEnabled: boolean
  language: string
}

export type Effect =
  | { kind: 'hash' }
  | { kind: 'search'; rung: SearchRung; query?: string }
  | { kind: 'download'; candidate: ScoredCandidate }
  | { kind: 'abort' }
  | { kind: 'flash'; ms: number }
  | { kind: 'play'; withSubtitles: boolean }
  | { kind: 'show-sign-in' }
  | { kind: 'show-manual' }
  | { kind: 'announce'; text: string }

export type ThreadingEvent =
  | { type: 'open'; at: number; parsed: ParsedName | null; quota: Quota }
  | { type: 'progress'; at: number; value: number }
  | { type: 'hashed'; at: number; hash: MovieHash | null }
  | { type: 'searched'; at: number; candidates: ScoredCandidate[] }
  | { type: 'attached'; at: number; inSync: boolean; quota?: Quota }
  | { type: 'failed'; at: number; failure: ThreadingFailure; quota?: Quota }
  | { type: 'tick'; at: number }
  | { type: 'choose'; at: number; action: NextAction }
  | { type: 'pick'; at: number; candidate: ScoredCandidate }
  | { type: 'manual-query'; at: number; query: string }
  | { type: 'signed-in'; at: number; quota: Quota }
  | { type: 'flashed'; at: number }
  | { type: 'cancel'; at: number }
  | { type: 'research'; at: number; exclude?: string | null }

export interface Step {
  machine: Machine
  effects: Effect[]
}

export const FAILURE_SENTENCE: Readonly<Record<ThreadingFailure, string>> = {
  'file-too-small': '', // never shown: a small file silently skips to a filename search
  offline: "You're offline — playing without new subtitles.",
  timeout: 'The subtitle service is taking too long.',
  'no-results': 'No print matched this file.',
  unauthorized: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
  'quota-exhausted': 'No tickets left tonight — sign in for more, or use the Subdl slot.',
  'rate-limited': 'OpenSubtitles asked us to wait 2 s.',
  'link-expired': 'That print expired — fetching a fresh link.',
  undecodable: "This print can't be projected.",
  'no-codec': "This print can't be projected here.",
  cancelled: 'Playing without subtitles.',
}

const RETRYABLE: ReadonlySet<ThreadingFailure> = new Set([
  'offline',
  'timeout',
  'rate-limited',
  'link-expired',
])

export interface MachineOptions {
  subdlEnabled: boolean
  language: string // ISO 639-1, e.g. 'en'
}

export function initial(o: MachineOptions, quota: Quota): Machine {
  return {
    state: {
      phase: 'idle',
      sweep: 0,
      hash: null,
      parsed: null,
      candidates: [],
      picked: null,
      quota,
      failure: null,
      next: [],
    },
    phaseStartedAt: 0,
    progress: 0,
    stalledIn: null,
    rung: null,
    query: null,
    tried: [],
    retried410: false,
    listOnly: false,
    exclude: null,
    subdlEnabled: o.subdlEnabled,
    language: o.language,
  }
}

export function languageName(code: string): string {
  try {
    return new Intl.DisplayNames(['en'], { type: 'language' }).of(code) ?? code.toUpperCase()
  } catch {
    return code.toUpperCase()
  }
}

/** The phase label under the leader — announced once per phase, never per frame. */
export function phaseLabel(m: Machine): string {
  switch (m.state.phase) {
    case 'hashing':
      return 'Reading the print'
    case 'searching':
      return 'Searching subtitles'
    case 'downloading':
      return `Downloading ${languageName(m.language)} subtitles`
    case 'flash':
    case 'done':
      if (m.state.picked === null && m.state.phase === 'done') return 'Playing without subtitles'
      return m.state.picked?.candidate.moviehashMatch === false
        ? 'Subtitles attached, check sync'
        : 'Subtitles attached, in sync'
    default:
      return ''
  }
}

/** The numeral the leader shows: 3 while reading, 2 while searching, 1 while downloading. */
export function numeral(phase: LeaderPhase): '3' | '2' | '1' | '' {
  if (phase === 'hashing' || phase === 'probing') return '3'
  if (phase === 'searching') return '2'
  if (phase === 'downloading') return '1'
  return ''
}

const isPending = (m: Machine): boolean =>
  m.state.failure === null &&
  (m.state.phase === 'hashing' || m.state.phase === 'searching' || m.state.phase === 'downloading')

function sweepAt(m: Machine, at: number): number {
  const byTime = (at - m.phaseStartedAt) / SWEEP_MS
  return Math.min(SWEEP_HOLD, Math.max(0, m.progress, byTime))
}

function nextFor(m: Machine, failure: ThreadingFailure): NextAction[] {
  const out: NextAction[] = []
  if (failure === 'unauthorized' || failure === 'quota-exhausted') out.push('sign-in')
  if (RETRYABLE.has(failure)) out.push('retry')
  if (!m.tried.includes('filename')) out.push('filename-search')
  if (m.subdlEnabled && !m.tried.includes('subdl')) out.push('subdl')
  out.push('manual', 'skip')
  return out
}

/** Enter a pending phase: the sweep starts from 0 and the phase is announced once. */
function enter(m: Machine, phase: LeaderPhase, at: number, patch: Partial<ThreadingState> = {}) {
  const machine: Machine = {
    ...m,
    phaseStartedAt: at,
    progress: 0,
    stalledIn: null,
    state: { ...m.state, ...patch, phase, sweep: 0, failure: null, next: [] },
  }
  return { machine, announce: { kind: 'announce', text: phaseLabel(machine) } as Effect }
}

function stall(m: Machine, failure: ThreadingFailure, at: number, quota?: Quota): Step {
  const machine: Machine = {
    ...m,
    stalledIn: m.state.phase === 'downloading' ? 'download' : 'search',
    state: {
      ...m.state,
      sweep: isPending(m) ? sweepAt(m, at) : m.state.sweep, // frozen from here on
      failure,
      next: nextFor(m, failure),
      quota: quota ?? m.state.quota,
    },
  }
  return { machine, effects: [{ kind: 'announce', text: FAILURE_SENTENCE[failure] }] }
}

function search(m: Machine, rung: SearchRung, at: number, query?: string): Step {
  const { machine, announce } = enter(
    {
      ...m,
      rung,
      query: query ?? null,
      tried: m.tried.includes(rung) ? m.tried : [...m.tried, rung],
    },
    'searching',
    at,
  )
  const effect: Effect =
    query === undefined ? { kind: 'search', rung } : { kind: 'search', rung, query }
  return { machine, effects: [announce, effect] }
}

/** A candidate is chosen: spend a ticket only when signed in with tickets left. */
function download(m: Machine, picked: ScoredCandidate, at: number, pre: Effect[] = []): Step {
  const { machine, announce } = enter(m, 'downloading', at, { picked })
  const q = machine.state.quota
  if (!q.signedIn) return withPre(stall(machine, 'unauthorized', at), pre)
  if (q.remaining !== null && q.remaining <= 0) {
    return withPre(stall(machine, 'quota-exhausted', at), pre)
  }
  return { machine, effects: [...pre, announce, { kind: 'download', candidate: picked }] }
}

const withPre = (s: Step, pre: Effect[]): Step => ({ ...s, effects: [...pre, ...s.effects] })

/** Skip or cancel: resolves to done with no subtitle — playback still starts. */
function finish(m: Machine, at: number): Step {
  const machine: Machine = {
    ...m,
    phaseStartedAt: at,
    stalledIn: null,
    state: { ...m.state, phase: 'done', picked: null, failure: null, next: [] },
  }
  return {
    machine,
    effects: [
      { kind: 'abort' },
      { kind: 'play', withSubtitles: false },
      { kind: 'announce', text: phaseLabel(machine) },
    ],
  }
}

export function reduce(m: Machine, e: ThreadingEvent): Step {
  const s = m.state
  const same: Step = { machine: m, effects: [] }

  switch (e.type) {
    case 'open': {
      const fresh = initial({ subdlEnabled: m.subdlEnabled, language: m.language }, e.quota)
      const { machine, announce } = enter(fresh, 'hashing', e.at, { parsed: e.parsed })
      return { machine, effects: [announce, { kind: 'hash' }] }
    }

    case 'progress':
      if (!isPending(m)) return same
      return {
        machine: { ...m, progress: Math.min(SWEEP_HOLD, Math.max(m.progress, e.value)) },
        effects: [],
      }

    case 'hashed':
      if (s.phase !== 'hashing' || s.failure !== null) return same
      // A null hash (file < 128 KiB, or unreadable) is SILENT: "3" completes normally
      // and "2" starts with a filename query.
      return search({ ...m, state: { ...s, hash: e.hash } }, e.hash ? 'hash' : 'filename', e.at)

    case 'searched': {
      if (s.phase !== 'searching' || s.failure !== null) return same
      if (m.listOnly) {
        // "Find another print": every other print, for the viewer to pick. No ticket is spent
        // until they do.
        const list = e.candidates.filter((c) => c.candidate.id !== m.exclude)
        const listed: Machine = { ...m, state: { ...s, candidates: list } }
        if (list.length === 0) return stall(listed, 'no-results', e.at)
        const machine: Machine = {
          ...listed,
          phaseStartedAt: e.at,
          stalledIn: null,
          state: { ...listed.state, phase: 'done', sweep: 1, failure: null, next: [] },
        }
        return {
          machine,
          effects: [{ kind: 'announce', text: `${list.length} other prints found — pick one` }],
        }
      }
      const withList: Machine = { ...m, state: { ...s, candidates: e.candidates } }
      const pick = e.candidates.find((c) => c.autoPick)
      if (!pick) return stall(withList, 'no-results', e.at)
      return download(withList, pick, e.at)
    }

    case 'attached': {
      if (s.phase === 'idle' || s.phase === 'flash' || s.phase === 'done') return same
      const machine: Machine = {
        ...m,
        phaseStartedAt: e.at,
        stalledIn: null,
        state: {
          ...s,
          phase: 'flash',
          sweep: 1,
          failure: null,
          next: [],
          quota: e.quota ?? s.quota,
        },
      }
      const text = e.inSync ? 'Subtitles attached, in sync' : 'Subtitles attached, check sync'
      return {
        machine,
        effects: [
          { kind: 'announce', text },
          { kind: 'flash', ms: FLASH_MS },
        ],
      }
    }

    case 'flashed': {
      if (s.phase !== 'flash') return same
      const machine: Machine = { ...m, phaseStartedAt: e.at, state: { ...s, phase: 'done' } }
      return { machine, effects: [{ kind: 'play', withSubtitles: true }] }
    }

    case 'failed': {
      if (!isPending(m)) return same
      if (e.failure === 'link-expired' && s.phase === 'downloading' && !m.retried410 && s.picked) {
        // The one automatic retry in the whole machine.
        return {
          machine: { ...m, retried410: true },
          effects: [{ kind: 'download', candidate: s.picked }],
        }
      }
      return stall(m, e.failure, e.at, e.quota)
    }

    case 'tick': {
      if (!isPending(m)) return same
      const deadline = DEADLINE_MS[s.phase] ?? Number.POSITIVE_INFINITY
      if (e.at - m.phaseStartedAt > deadline)
        return withPre(stall(m, 'timeout', e.at), [{ kind: 'abort' }])
      return { machine: { ...m, state: { ...s, sweep: sweepAt(m, e.at) } }, effects: [] }
    }

    case 'choose':
      return choose(m, e.action, e.at)

    case 'manual-query':
      if (s.phase === 'idle' || s.phase === 'flash' || s.phase === 'done') return same
      return search(m, 'manual', e.at, e.query)

    case 'pick':
      // While threading, or from the booth once the film plays (phase done).
      if (s.phase !== 'searching' && s.phase !== 'downloading' && s.phase !== 'done') return same
      return download(m, e.candidate, e.at, [{ kind: 'abort' }])

    case 'signed-in': {
      const machine: Machine = { ...m, state: { ...s, quota: e.quota } }
      const blocked = s.failure === 'unauthorized' || s.failure === 'quota-exhausted'
      if (m.stalledIn === 'download' && blocked && s.picked)
        return download(machine, s.picked, e.at)
      return { machine, effects: [] }
    }

    case 'cancel':
      if (s.phase === 'idle' || s.phase === 'done') return same
      return finish(m, e.at)

    case 'research':
      // "Find another print" from the booth: the filename rung again, without leaving the film,
      // listing the results for a pick. It works again after that search (or a pick) stalled.
      if (s.phase !== 'done' && s.failure === null) return same
      return search(
        {
          ...m,
          retried410: false,
          listOnly: true,
          exclude: e.exclude ?? null,
          tried: m.tried.filter((r) => r !== 'filename'),
        },
        'filename',
        e.at,
      )
  }
}

function choose(m: Machine, action: NextAction, at: number): Step {
  const s = m.state
  const same: Step = { machine: m, effects: [] }
  if (action === 'skip') {
    if (s.phase === 'idle' || s.phase === 'done' || s.phase === 'flash') return same
    return finish(m, at)
  }
  if (s.failure === null) return same // fallback rows only exist on a stall
  switch (action) {
    case 'filename-search':
      return search(m, 'filename', at)
    case 'subdl':
      return m.subdlEnabled ? search(m, 'subdl', at) : same
    case 'manual':
      return { machine: m, effects: [{ kind: 'show-manual' }] }
    case 'sign-in':
      return { machine: m, effects: [{ kind: 'show-sign-in' }] }
    case 'retry':
      if (m.stalledIn === 'download' && s.picked) return download(m, s.picked, at)
      return search(m, m.rung ?? 'filename', at, m.query ?? undefined)
    default:
      return same
  }
}
