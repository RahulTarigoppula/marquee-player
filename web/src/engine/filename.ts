// Filename grammar (IMPLEMENTATION-PROMPT §6.3): a TypeScript port of MIT parse-torrent-title,
// extended for anime brackets. Never guessit-js (LGPL-3.0). When confidence is 'low' the
// threading layer sends query=<raw filename> and lets the server's guessit do the work.
import type { ParsedName } from './types'

const VIDEO_EXT = /\.(mkv|mk3d|mp4|m4v|avi|mov|webm|ts|m2ts|mts|wmv|flv|mpe?g|ogv|3gp)$/i
const SUBTITLE_EXT = /\.(srt|ass|ssa|vtt|sub|idx|sup)$/i

const RESOLUTION = /^(\d{3,4}p|4K)$/i
// Sources that are also ordinary English words only count in their release-scene capitals.
const SOURCES_CI = ['BluRay', 'BDRip', 'BRRip', 'WEB-DL', 'WEBRip', 'HDTV', 'DVDRip', 'REMUX']
const SOURCES_CS = ['WEB', 'CAM', 'TS']
const CODEC = /^(x264|x265|H264|H265|HEVC|AVC|XviD|DivX|AV1|VP9)$/i
const AUDIO =
  /^(AAC|AAC2\.0|AAC5\.1|AC3|EAC3|DD5\.1|DDP5\.1|DDP|DTS|DTS-HD|TrueHD|Atmos|FLAC|MP3|Opus)$/i
const FLAG = /^(PROPER|REPACK|REMASTERED|EXTENDED|UNRATED|HDR|HDR10|10bit|UHD)$/i
const YEAR = /^(19|20)\d{2}$/
const SXXEXX = /^S(\d{1,2})E(\d{1,3})$/i
const NXN = /^(\d{1,2})x(\d{1,3})$/
const SEASON_EPISODE_WORDS = /Season (\d+).*?Episode (\d+)/i
const ANIME_GROUP = /^\[(\w+)\]$/
const CRC = /^\[[0-9A-F]{8}\]$/i

/** Remove surrounding brackets/parentheses: '(1080p)' → '1080p'. */
const bare = (t: string): string => t.replace(/^[([{]+/, '').replace(/[)\]}]+$/, '')

const isSource = (t: string): boolean =>
  SOURCES_CI.some((s) => s.toLowerCase() === t.toLowerCase()) || SOURCES_CS.includes(t)
const isCodec = (t: string): boolean => CODEC.test(t)
const isResolution = (t: string): boolean => RESOLUTION.test(t)

const isQualityPiece = (t: string): boolean =>
  isResolution(t) || isSource(t) || isCodec(t) || AUDIO.test(t) || FLAG.test(t)

/** A token's candidate pieces: the whole (bare) token first, then its dash-separated parts. */
function pieces(token: string): string[] {
  const b = bare(token)
  return b.includes('-') ? [b, ...b.split('-').filter((p) => p !== '')] : [b]
}

const isQuality = (token: string): boolean => pieces(token).some(isQualityPiece)

function firstPiece(tokens: string[], pred: (t: string) => boolean): string | null {
  for (const t of tokens) for (const p of pieces(t)) if (pred(p)) return p
  return null
}

/** Split on whitespace, keeping [bracket groups] and (paren groups) intact. */
function tokenize(s: string): string[] {
  const out: string[] = []
  let cur = ''
  let depth = 0
  for (const ch of s) {
    if (ch === '[' || ch === '(') depth++
    if ((ch === ']' || ch === ')') && depth > 0) depth--
    if (/\s/.test(ch) && depth === 0) {
      if (cur !== '') out.push(cur)
      cur = ''
      continue
    }
    cur += ch
  }
  if (cur !== '') out.push(cur)
  return out
}

export const isSubtitleName = (name: string): boolean => SUBTITLE_EXT.test(name)

/** Parse one file or release name. Returns null for a subtitle file — it is not a video. */
export function parseName(filename: string): ParsedName | null {
  if (isSubtitleName(filename)) return null
  const raw = filename
  const original = filename.replace(VIDEO_EXT, '')
  // [._] becomes a space only between word characters: keeps S02E04, x264, WEB-DL.
  let tokens = tokenize(original.replace(/(?<=\w)[._](?=\w)/g, ' '))

  let group: string | null = null
  let animeEpisode: number | null = null
  let titleLimit = Number.POSITIVE_INFINITY

  // 1. anime bracket form: [Group] Title - 12 (1080p) [HASH]
  const anime = ANIME_GROUP.exec(tokens[0] ?? '')
  if (anime) {
    group = anime[1] ?? null
    tokens = tokens.slice(1).filter((t) => !CRC.test(t))
    const dash = tokens.indexOf('-')
    if (dash >= 0) {
      titleLimit = dash
      const ep = tokens.slice(dash + 1).find((t) => /^\d+$/.test(t))
      if (ep !== undefined) animeEpisode = Number(ep)
    }
  } else {
    // group: the segment after the LAST dash of the original name, unless it is a codec or a
    // resolution, contains a dot or a space, or belongs to a quality token such as WEB-DL.
    const dash = original.lastIndexOf('-')
    const seg = dash >= 0 ? original.slice(dash + 1) : ''
    const last = tokens.at(-1) ?? ''
    if (
      seg !== '' &&
      !/[.\s]/.test(seg) &&
      !isCodec(seg) &&
      !isResolution(seg) &&
      last.endsWith(`-${seg}`) &&
      !isQualityPiece(bare(last))
    ) {
      group = seg
      const rest = last.slice(0, -(seg.length + 1))
      tokens = rest === '' ? tokens.slice(0, -1) : [...tokens.slice(0, -1), rest]
    }
  }

  // 2. quality boundary: everything after the FIRST quality token is metadata, not title.
  let cut = tokens.length
  for (let i = 1; i < tokens.length; i++) {
    if (isQuality(tokens[i] ?? '')) {
      cut = i
      break
    }
  }

  // 3. year: the LAST 19xx/20xx token strictly before the cut, never the first token
  //    (so a year inside a title is not stolen, and a year can be a whole title).
  let yearIdx = -1
  for (let i = 1; i < cut; i++) if (YEAR.test(bare(tokens[i] ?? ''))) yearIdx = i
  const year = yearIdx >= 0 ? Number(bare(tokens[yearIdx] ?? '')) : null

  // 4. season/episode, in priority order.
  let season: number | null = null
  let episode: number | null = animeEpisode
  let seIdx = -1
  for (let i = 0; i < tokens.length && seIdx < 0; i++) {
    const t = bare(tokens[i] ?? '')
    const m = SXXEXX.exec(t) ?? NXN.exec(t)
    if (m) {
      season = Number(m[1])
      episode = Number(m[2])
      seIdx = i
    }
  }
  if (seIdx < 0) {
    const words = SEASON_EPISODE_WORDS.exec(tokens.join(' '))
    if (words) {
      season = Number(words[1])
      episode = Number(words[2])
      seIdx = tokens.findIndex((t) => t.toLowerCase() === 'season')
    }
  }
  if (seIdx >= 0) titleLimit = Math.min(titleLimit, seIdx)

  // 5. metadata from tokens[cut..]
  const meta = tokens.slice(cut)
  const flag = (re: RegExp) => tokens.some((t) => pieces(t).some((p) => re.test(p)))

  const titleTokens = tokens
    .slice(0, Math.min(cut, titleLimit))
    .filter((t, i) => i !== yearIdx && t !== '-')
  const title = titleTokens.join(' ').replace(/\s+/g, ' ').trim() || original.trim()

  const hasAlpha = titleTokens.some((t) => /[A-Za-z]/.test(t))
  const isEpisode = season !== null || episode !== null
  let confidence: ParsedName['confidence'] = 'low'
  if (anime || ((year !== null || isEpisode) && hasAlpha)) confidence = 'high'
  else if (titleTokens.length >= 2 && cut < tokens.length) confidence = 'medium'

  return {
    title,
    year,
    season,
    episode,
    resolution: firstPiece(meta, isResolution),
    source: firstPiece(meta, isSource),
    videoCodecToken: firstPiece(meta, isCodec),
    group,
    remastered: flag(/^REMASTERED$/i),
    proper: flag(/^(PROPER|REPACK)$/i),
    extended: flag(/^EXTENDED$/i),
    kind: isEpisode ? 'episode' : 'movie',
    confidence,
    raw,
  }
}

const RANK = { low: 0, medium: 1, high: 2 } as const

/**
 * Parse only the basename; when it is 'low' confidence, parse the parent directory name as a
 * second attempt and use it when it scores higher (D:\Films\The Third Man (1949)\video.mkv).
 */
export function parsePath(path: string): ParsedName | null {
  const parts = path.split(/[\\/]/).filter((p) => p !== '')
  const base = parseName(parts.at(-1) ?? path)
  if (base?.confidence !== 'low' || parts.length < 2) return base
  const parent = parseName(parts.at(-2) ?? '')
  return parent && RANK[parent.confidence] > RANK[base.confidence] ? parent : base
}
