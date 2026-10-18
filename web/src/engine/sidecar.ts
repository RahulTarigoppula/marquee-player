// Subtitle files the viewer brings (web-only). Pure: bytes in, cues out.
//   - text decoding: UTF-8/UTF-16 BOMs honoured, strict UTF-8 tried next, then windows-1252
//     (the encoding of most old Western SRTs) so a "Ã©" never reaches the picture;
//   - WebVTT: hour-less timestamps (`01:02.500`) and cue settings are normalised so the
//     anchored SRT parser reads them; NOTE / STYLE / REGION blocks are dropped;
//   - ASS/SSA are not parsed here: they go to libass (JASSUB) whole.
import { type Cue, parseSrt } from './srt2vtt'

export type SidecarKind = 'srt' | 'vtt' | 'ass'

const SUBTITLE_EXT = /\.(srt|vtt|ass|ssa)$/i

/** The kind of subtitle file a name denotes, or null for anything else. */
export function sidecarKind(name: string): SidecarKind | null {
  const ext = SUBTITLE_EXT.exec(name)?.[1]?.toLowerCase()
  if (!ext) return null
  if (ext === 'ssa' || ext === 'ass') return 'ass'
  return ext === 'vtt' ? 'vtt' : 'srt'
}

/** Decode a subtitle file's bytes to text, whatever its encoding. */
export function decodeSubtitle(bytes: Uint8Array): string {
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder('utf-8').decode(bytes.subarray(3))
  }
  if (bytes[0] === 0xff && bytes[1] === 0xfe) {
    return new TextDecoder('utf-16le').decode(bytes.subarray(2))
  }
  if (bytes[0] === 0xfe && bytes[1] === 0xff) {
    return new TextDecoder('utf-16be').decode(bytes.subarray(2))
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    return windows1252(bytes)
  }
}

// 0x80–0x9F in windows-1252 (the rest of the code page is Latin-1). Spelled out because some
// runtimes alias "windows-1252" to plain Latin-1 and would lose the curly quotes.
const CP1252_HIGH = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F\u0090‘’“”•–—˜™š›œ\u009DžŸ'

function windows1252(bytes: Uint8Array): string {
  let out = ''
  for (const b of bytes) {
    out += b >= 0x80 && b <= 0x9f ? CP1252_HIGH[b - 0x80] : String.fromCharCode(b)
  }
  return out
}

const VTT_TIME = /(^|[\s>])(\d{2}:\d{2}\.\d{3})(?=$|\s)/g
const VTT_TIMING_LINE = /-->/

/** WebVTT → the SRT shape parseSrt reads: hours added, cue settings and blocks dropped. */
export function vttAsSrt(text: string): string {
  const blocks = text
    .replace(/^﻿/, '')
    .replace(/\r\n?/g, '\n')
    .split(/\n{2,}/)
  const out: string[] = []
  for (const block of blocks) {
    const head = block.trimStart()
    if (/^(WEBVTT|NOTE|STYLE|REGION)\b/.test(head)) continue
    const lines = block.split('\n')
    const at = lines.findIndex((l) => VTT_TIMING_LINE.test(l))
    if (at < 0) continue
    const timing = (lines[at] ?? '').replace(VTT_TIME, '$100:$2')
    const [start, rest = ''] = timing.split('-->')
    const end = rest.trim().split(/\s+/)[0] ?? ''
    out.push(`${(start ?? '').trim()} --> ${end}\n${lines.slice(at + 1).join('\n')}`)
  }
  return out.join('\n\n')
}

/** Cues from an SRT or VTT sidecar; null for ASS/SSA (rendered by libass instead). */
export function parseSidecar(kind: SidecarKind, text: string): Cue[] | null {
  if (kind === 'ass') return null
  return parseSrt(kind === 'vtt' ? vttAsSrt(text) : text)
}
