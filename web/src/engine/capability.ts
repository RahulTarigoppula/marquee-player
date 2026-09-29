// Capability probe (IMPLEMENTATION-PROMPT §6.12) — Marquee Lite's honesty line.
// Pure: the browser surface (canPlayType, VideoDecoder, AudioDecoder) is injected.
import type { Capability, CodecSupport } from './types'

interface Probe {
  label: string
  mime: string
  /** WebCodecs fallback config. */
  webcodecs: { kind: 'video' | 'audio'; codec: string }
}

export const PROBES: readonly Probe[] = [
  {
    label: 'MP4/H.264',
    mime: 'video/mp4; codecs="avc1.42E01E, mp4a.40.2"',
    webcodecs: { kind: 'video', codec: 'avc1.42E01E' },
  },
  {
    label: 'WebM/VP9',
    mime: 'video/webm; codecs="vp9, opus"',
    webcodecs: { kind: 'video', codec: 'vp09.00.10.08' },
  },
  {
    label: 'AV1',
    mime: 'video/webm; codecs="av01.0.05M.08"',
    webcodecs: { kind: 'video', codec: 'av01.0.05M.08' },
  },
  {
    label: 'HEVC',
    mime: 'video/mp4; codecs="hvc1.1.6.L93.B0"',
    webcodecs: { kind: 'video', codec: 'hvc1.1.6.L93.B0' },
  },
  {
    label: 'AC-3',
    mime: 'audio/mp4; codecs="ac-3"',
    webcodecs: { kind: 'audio', codec: 'ac-3' },
  },
]

interface VideoSupportable {
  isConfigSupported(c: { codec: string; codedWidth: number; codedHeight: number }): Promise<{
    supported?: boolean
  }>
}
interface AudioSupportable {
  isConfigSupported(c: { codec: string; sampleRate: number; numberOfChannels: number }): Promise<{
    supported?: boolean
  }>
}

export interface ProbeEnv {
  canPlayType(mime: string): string
  VideoDecoder?: VideoSupportable | undefined
  AudioDecoder?: AudioSupportable | undefined
}

const PROBE_W = 1280
const PROBE_H = 720
const PROBE_RATE = 48000

async function viaWebCodecs(env: ProbeEnv, p: Probe): Promise<boolean> {
  const codec = p.webcodecs.codec
  try {
    if (p.webcodecs.kind === 'video') {
      const dec = env.VideoDecoder
      const cfg = { codec, codedWidth: PROBE_W, codedHeight: PROBE_H }
      return dec !== undefined && (await dec.isConfigSupported(cfg)).supported === true
    }
    const dec = env.AudioDecoder
    const cfg = { codec, sampleRate: PROBE_RATE, numberOfChannels: 2 }
    return dec !== undefined && (await dec.isConfigSupported(cfg)).supported === true
  } catch {
    return false
  }
}

function fragment(c: CodecSupport): string {
  if (c.via === 'native') return `${c.label} ✓`
  if (c.via === 'webcodecs') return `${c.label} ✓ (WebCodecs)`
  return `${c.label} ✗`
}

/** 1. canPlayType 'probably'|'maybe' → native; 2. else WebCodecs isConfigSupported; 3. else ✗. */
export async function probeCapability(env: ProbeEnv): Promise<Capability> {
  const webCodecsAvailable = env.VideoDecoder !== undefined
  const codecs: CodecSupport[] = []
  for (const p of PROBES) {
    const native = env.canPlayType(p.mime)
    if (native === 'probably' || native === 'maybe') {
      codecs.push({ label: p.label, ok: true, via: 'native' })
    } else if (await viaWebCodecs(env, p)) {
      codecs.push({ label: p.label, ok: true, via: 'webcodecs' })
    } else {
      codecs.push({ label: p.label, ok: false, via: 'none' })
    }
  }
  // MKV is NEVER probed: Chrome plays some H.264 MKVs and fails silently on others.
  const parts = [...codecs.map(fragment), 'MKV partial']
  if (!webCodecsAvailable) parts.push('WebCodecs unavailable')
  return { line: parts.join(' · '), codecs, webCodecsAvailable }
}

// ── What is inside a print: a cheap, honest sniff of the first bytes ──

export interface PrintSniff {
  container: string | null // 'MKV' | 'WebM' | 'MP4' | 'AVI' | …
  video: string | null // a PROBES label or a codec name we cannot probe
  audio: string | null
}

const MARKERS: ReadonlyArray<{ kind: 'video' | 'audio'; label: string; ids: string[] }> = [
  { kind: 'video', label: 'HEVC', ids: ['V_MPEGH/ISO/HEVC', 'hvc1', 'hev1'] },
  { kind: 'video', label: 'H.264', ids: ['V_MPEG4/ISO/AVC', 'avc1'] },
  { kind: 'video', label: 'AV1', ids: ['V_AV1', 'av01'] },
  { kind: 'video', label: 'VP9', ids: ['V_VP9', 'vp09'] },
  { kind: 'video', label: 'MPEG-4 Part 2', ids: ['V_MPEG4/ISO/ASP', 'XVID', 'DIVX', 'mp4v'] },
  { kind: 'audio', label: 'E-AC-3', ids: ['A_EAC3', 'ec-3'] },
  { kind: 'audio', label: 'AC-3', ids: ['A_AC3', 'ac-3'] },
  { kind: 'audio', label: 'DTS', ids: ['A_DTS', 'dtsc'] },
  { kind: 'audio', label: 'TrueHD', ids: ['A_TRUEHD', 'mlpa'] },
  { kind: 'audio', label: 'AAC', ids: ['A_AAC', 'mp4a'] },
  { kind: 'audio', label: 'Opus', ids: ['A_OPUS', 'Opus'] },
]

function containerOf(b: Uint8Array, name: string): string | null {
  const ascii = (from: number, len: number) => String.fromCharCode(...b.subarray(from, from + len))
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) {
    return /\.webm$/i.test(name) ? 'WebM' : 'MKV'
  }
  if (ascii(4, 4) === 'ftyp') return 'MP4'
  if (ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'AVI ') return 'AVI'
  if (b[0] === 0x47 && b[188] === 0x47) return 'TS'
  const ext = /\.([a-z0-9]{2,4})$/i.exec(name)?.[1]
  return ext ? ext.toUpperCase() : null
}

/** Look for codec identifiers in the head of the file (the first ~1 MiB is plenty). */
export function sniffPrint(head: Uint8Array, name: string): PrintSniff {
  const text = new TextDecoder('latin1').decode(head)
  const find = (kind: 'video' | 'audio') =>
    MARKERS.find((m) => m.kind === kind && m.ids.some((id) => text.includes(id)))?.label ?? null
  return { container: containerOf(head, name), video: find('video'), audio: find('audio') }
}

const PROBE_FOR: Record<string, string> = {
  'H.264': 'MP4/H.264',
  VP9: 'WebM/VP9',
  AV1: 'AV1',
  HEVC: 'HEVC',
  'AC-3': 'AC-3',
}

/** Browsers never decode these natively; they are not in the probe list for that reason. */
const NEVER_NATIVE = new Set(['E-AC-3', 'DTS', 'TrueHD', 'MPEG-4 Part 2'])

export interface NoPrintReason {
  tags: string // 'MKV · HEVC · AC-3'
  sentence: string // one sentence naming the exact missing decoder
  missing: string | null
}

/** The No Print card's copy: names the first codec (video, then audio) this browser lacks. */
export function noPrintReason(s: PrintSniff, cap: Capability): NoPrintReason {
  const tags = [s.container, s.video, s.audio].filter((t): t is string => t !== null).join(' · ')
  const lacks = (codec: string | null): boolean => {
    if (codec === null) return false
    if (NEVER_NATIVE.has(codec)) return true
    const label = PROBE_FOR[codec]
    return cap.codecs.some((c) => c.label === label && !c.ok)
  }
  const missing = [s.video, s.audio].find(lacks) ?? null
  return {
    tags,
    missing,
    sentence:
      missing === null
        ? "This browser couldn't decode this print."
        : `This browser has no ${missing} decoder.`,
  }
}
