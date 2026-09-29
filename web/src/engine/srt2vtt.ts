// SRT → WebVTT and delay (IMPLEMENTATION-PROMPT §6.11). A state machine over lines: no eval,
// every pattern anchored, each cue capped at 10 000 characters. The output goes into a <track>
// via a Blob URL — never into innerHTML.

export interface Cue {
  start: number // ms
  end: number // ms
  text: string
  settings: string // VTT cue settings, e.g. ' line:0'
}

const MAX_CUE_CHARS = 10_000
const TIMING =
  /^(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,3}):(\d{2}):(\d{2})[,.](\d{1,3})/
const AN8 = /^\{\\an8\}/
const ASS_OVERRIDE = /\{\\[^}]*\}/g
// Keep <i> <b> <u> (VTT supports them); strip every other tag, <font …> included, to its text.
const FOREIGN_TAG = /<(?!\/?[ibu]>)[^>]*>/gi

const ms = (h: string, m: string, s: string, f: string): number =>
  ((Number(h) * 60 + Number(m)) * 60 + Number(s)) * 1000 + Number(f.padEnd(3, '0'))

export function parseSrt(input: string): Cue[] {
  const lines = input.replace(/^﻿/, '').replace(/\r\n?/g, '\n').split('\n')
  const cues: Cue[] = []
  let cur: Cue | null = null
  let body: string[] = []

  const flush = () => {
    if (cur && body.length > 0) {
      let text = body.join('\n')
      if (AN8.test(text)) cur.settings = ' line:0'
      text = text.replace(ASS_OVERRIDE, '').replace(FOREIGN_TAG, '').replace(/-->/g, '→')
      cur.text = text.slice(0, MAX_CUE_CHARS)
      cues.push(cur)
    }
    cur = null
    body = []
  }

  for (const line of lines) {
    const t = TIMING.exec(line.trim())
    if (t) {
      flush()
      cur = {
        start: ms(t[1] ?? '0', t[2] ?? '0', t[3] ?? '0', t[4] ?? '0'),
        end: ms(t[5] ?? '0', t[6] ?? '0', t[7] ?? '0', t[8] ?? '0'),
        text: '',
        settings: '',
      }
    } else if (line.trim() === '') {
      flush()
    } else if (cur) {
      body.push(line)
    }
    // A line outside a cue (the index line, or stray text) is ignored.
  }
  flush()
  // Sort by start (stable) — a real file had cue 2 before cue 1.
  return cues
    .map((c, i) => ({ c, i }))
    .sort((a, b) => a.c.start - b.c.start || a.i - b.i)
    .map((x) => x.c)
}

const pad = (n: number, w = 2): string => String(n).padStart(w, '0')

export function vttTime(t: number): string {
  const v = Math.max(0, Math.round(t))
  const h = Math.floor(v / 3_600_000)
  const m = Math.floor((v % 3_600_000) / 60_000)
  const s = Math.floor((v % 60_000) / 1000)
  return `${pad(h)}:${pad(m)}:${pad(s)}.${pad(v % 1000, 3)}`
}

/** Shift every cue by `delayMs`, clamped at 00:00:00.000. Overlaps are preserved. */
export function shiftCues(cues: Cue[], delayMs: number): Cue[] {
  return cues.map((c) => ({
    ...c,
    start: Math.max(0, c.start + delayMs),
    end: Math.max(0, c.end + delayMs),
  }))
}

export function toVtt(cues: Cue[], delayMs = 0): string {
  const blocks = shiftCues(cues, delayMs).map(
    (c, i) => `${i + 1}\n${vttTime(c.start)} --> ${vttTime(c.end)}${c.settings}\n${c.text}`,
  )
  return `WEBVTT\n\n${blocks.join('\n\n')}\n`
}

export const srtToVtt = (srt: string, delayMs = 0): string => toVtt(parseSrt(srt), delayMs)
