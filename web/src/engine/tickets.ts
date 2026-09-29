// Quota → ticket strip (IMPLEMENTATION-PROMPT §6.6). A pure function of the last /download
// response (or the login payload) plus the injected clock. The total is NEVER a constant:
// print whatever allowed_downloads came back with.
import type { OsDownloadResponse, OsLoginResponse, Quota, TicketStrip } from './types'

const LOW_WATER = 2 // at 2 left the strip turns crimson

export const SENTENCE_LOW =
  'Sign in at the ticket office (free, more tickets) or use the Subdl slot.'
export const SENTENCE_EXHAUSTED =
  'No tickets left tonight — sign in for more, or use the Subdl slot.'

export const ANONYMOUS: Quota = {
  remaining: null,
  total: null,
  resetUtc: null,
  signedIn: false,
  vip: false,
  level: null,
}

export function quotaFromLogin(login: OsLoginResponse, prev: Quota = ANONYMOUS): Quota {
  return {
    remaining: prev.signedIn ? prev.remaining : null,
    total: login.user.allowed_downloads,
    resetUtc: prev.signedIn ? prev.resetUtc : null,
    signedIn: true,
    vip: login.user.vip,
    level: login.user.level,
  }
}

/** A 200 from /download, or the body of a 406 (remaining 0). */
export function quotaFromDownload(
  dl: Pick<OsDownloadResponse, 'requests' | 'remaining' | 'reset_time_utc'>,
  prev: Quota,
): Quota {
  return {
    ...prev,
    remaining: dl.remaining,
    total: prev.total ?? dl.requests + dl.remaining,
    resetUtc: dl.reset_time_utc,
  }
}

/** GET /infos/user — the current quota without spending one. Unknown shapes change nothing. */
export function quotaFromUserInfo(body: unknown, prev: Quota): Quota {
  const data = (body as { data?: Record<string, unknown> } | null)?.data
  if (!data) return prev
  const num = (v: unknown): number | null => (typeof v === 'number' ? v : null)
  return {
    ...prev,
    signedIn: true,
    remaining: num(data.remaining_downloads) ?? prev.remaining,
    total: num(data.allowed_downloads) ?? prev.total,
    vip: data.vip === true,
    level: typeof data.level === 'string' ? data.level : prev.level,
  }
}

/** `HH:MM` of an ISO instant, in UTC — the strip always prints UTC. */
function utcClock(iso: string): string {
  const d = new Date(iso)
  const hh = String(d.getUTCHours()).padStart(2, '0')
  const mm = String(d.getUTCMinutes()).padStart(2, '0')
  return `${hh}:${mm}`
}

export interface StripOptions {
  /** The injected clock. Once the reset instant has passed, the strip is full again. */
  now: Date
  /** HTTP 406 on /download: the quota is exhausted whatever the counter said. */
  status406?: boolean
  /** A ticket-tear animation is still running: show the count BEFORE the tear. */
  pendingTear?: boolean
}

export function ticketStrip(q: Quota, o: StripOptions): TicketStrip {
  const pendingTear = o.pendingTear === true
  if (!q.signedIn) {
    return {
      text: 'ANONYMOUS · 5 PER DAY PER IP',
      sentence: null,
      ariaLabel: 'Anonymous: 5 downloads per day per network',
      state: 'anonymous',
      pendingTear,
    }
  }
  const resetPassed = q.resetUtc !== null && o.now.getTime() >= Date.parse(q.resetUtc)
  const resets = q.resetUtc !== null && !resetPassed ? ` · RESETS ${utcClock(q.resetUtc)} UTC` : ''
  let remaining = resetPassed ? q.total : q.remaining
  if (remaining !== null && pendingTear) remaining += 1
  if (o.status406 === true) remaining = 0

  if (remaining === null || q.total === null) {
    const total = q.total === null ? '' : `${q.total} `
    return {
      text: `${total}TICKETS A DAY`.trim(),
      sentence: null,
      ariaLabel: q.total === null ? 'Signed in' : `${q.total} downloads a day`,
      state: 'unknown',
      pendingTear,
    }
  }
  if (remaining <= 0) {
    return {
      text: `NO TICKETS LEFT TONIGHT${resets}`,
      sentence: SENTENCE_EXHAUSTED,
      ariaLabel: 'No downloads left tonight',
      state: 'exhausted',
      pendingTear,
    }
  }
  const aria = `${remaining} of ${q.total} downloads left tonight`
  if (q.vip) {
    return {
      text: `${remaining} OF ${q.total} · VIP`,
      sentence: null,
      ariaLabel: aria,
      state: 'vip',
      pendingTear,
    }
  }
  const text = `${remaining} OF ${q.total} TONIGHT${resets}`
  if (remaining <= LOW_WATER) {
    return {
      text,
      sentence: SENTENCE_LOW,
      ariaLabel: aria,
      state: 'two-left',
      pendingTear,
    }
  }
  return { text, sentence: null, ariaLabel: aria, state: 'n-left', pendingTear }
}
