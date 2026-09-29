// Folio timecodes (IMPLEMENTATION-PROMPT §6.7).
// Position FLOORS to whole seconds and remaining CEILS, so the two always add up to the
// duration. Always HH:MM:SS, never wrapping at 24 h, U+2212 (−) not a hyphen.

const MINUS = '−'
const TITLE_MAX = 40

const pad2 = (n: number): string => String(n).padStart(2, '0')

/** HH:MM:SS with HH unbounded (12:30:00 stays 12:30:00, 30:00:00 stays 30:00:00). */
export function fmt(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  return `${pad2(Math.floor(s / 3600))}:${pad2(Math.floor((s % 3600) / 60))}:${pad2(s % 60)}`
}

/** `01:12:44 · −01:28:19`; an unknown duration (live / stream) prints `00:00:45 · —`. */
export function folio(position: number, duration: number | null): string {
  const pos = Math.floor(Math.max(0, position))
  if (duration === null || !Number.isFinite(duration)) return `${fmt(pos)} · —`
  return `${fmt(pos)} · ${MINUS}${fmt(Math.max(0, Math.ceil(duration) - pos))}`
}

/** A signed two-decimal value: +0.35 / −0.35 / +0.00. */
export function signed(v: number): string {
  const r = Math.round(v * 100) / 100
  return `${r < 0 ? MINUS : '+'}${Math.abs(r).toFixed(2)}`
}

export interface FolioSuffixes {
  speed?: number // shown while not 1× (e.g. the long-press 2.0×)
  looping?: boolean // A–B
  subDelay?: number // seconds; shown only when non-zero
}

/** Suffixes append, never replace. */
export function withSuffixes(base: string, s: FolioSuffixes): string {
  const parts = [base]
  if (s.speed !== undefined && s.speed !== 1) parts.push(`${s.speed.toFixed(1)}×`)
  if (s.looping === true) parts.push('A–B')
  if (s.subDelay !== undefined && Math.round(s.subDelay * 100) !== 0) {
    parts.push(`SUB ${signed(s.subDelay)}`)
  }
  return parts.join(' · ')
}

export const THREADING_FOLIO = 'REEL 01 · THREADING'

/** Uppercased and condensed to 40 characters with an ellipsis. */
export function condenseTitle(title: string): string {
  const t = title.trim().toUpperCase()
  return t.length > TITLE_MAX ? `${t.slice(0, TITLE_MAX - 1)}…` : t
}

/** Desktop auditorium folio: `REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19`. */
export function auditoriumFolio(title: string | null, pos: number, dur: number | null): string {
  const head = title ? `REEL 01 · ${condenseTitle(title)}` : 'REEL 01'
  return `${head} · ${folio(pos, dur)}`
}
