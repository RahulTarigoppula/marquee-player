// The single source of types for the web tier (IMPLEMENTATION-PROMPT §5.3).
// Wire shapes mirror api.opensubtitles.com/api/v1 (only the fields we read);
// engine shapes mirror the Dart classes 1:1 so the golden tables are shared.

// ── wire shapes ──

export interface OsFile {
  file_id: number
  cd_number?: number
  file_name?: string
}

export interface OsFeatureDetails {
  feature_type: 'Movie' | 'Episode' | string
  title?: string
  year?: number
  season_number?: number | null
  episode_number?: number | null
  imdb_id?: number | null
  tmdb_id?: number | null
}

export interface OsSubtitleAttributes {
  language: string | null
  download_count: number
  new_download_count?: number
  hearing_impaired: boolean
  machine_translated: boolean
  ai_translated: boolean
  fps: number | null
  release: string | null
  upload_date?: string
  moviehash_match?: boolean // ABSENT unless the search included a moviehash
  files: OsFile[]
  feature_details: OsFeatureDetails
}

export interface OsSearchResponse {
  total_pages: number
  total_count: number
  page: number
  data: Array<{ id: string; type: 'subtitle'; attributes: OsSubtitleAttributes }>
}

export interface OsLoginResponse {
  token: string
  base_url: string
  status: number
  user: {
    allowed_downloads: number
    level: string
    user_id: number
    ext_installed?: boolean
    vip: boolean
  }
}

export interface OsDownloadResponse {
  link: string // TEMPORARY: store the FILE, never this URL (410 after expiry)
  file_name: string
  requests: number
  remaining: number
  message?: string
  reset_time?: string // human text, never parsed
  reset_time_utc: string // ISO — the only reset value the UI trusts
}

// ── engine types ──

export type MovieHash = string & { readonly __brand: 'MovieHash' }
export type Provider = 'opensubtitles' | 'subdl' | 'embedded' | 'sidecar'

export interface Candidate {
  provider: Provider
  id: string
  language: string
  release: string | null
  downloadCount: number
  hearingImpaired: boolean
  moviehashMatch: boolean
  machineTranslated: boolean
  aiTranslated: boolean
  fps: number | null
  feature: OsFeatureDetails | null
}

export interface ScoredCandidate {
  candidate: Candidate
  score: number
  reasons: string[]
  autoPick: boolean
}

export interface ParsedName {
  title: string
  year: number | null
  season: number | null
  episode: number | null
  resolution: string | null
  source: string | null
  videoCodecToken: string | null
  group: string | null
  remastered: boolean
  proper: boolean
  extended: boolean
  kind: 'movie' | 'episode'
  confidence: 'high' | 'medium' | 'low'
  raw: string
}

export type TicketState = 'anonymous' | 'n-left' | 'two-left' | 'exhausted' | 'vip' | 'unknown'

export interface Quota {
  remaining: number | null
  total: number | null
  resetUtc: string | null
  signedIn: boolean
  vip: boolean
  level: string | null
}

export interface TicketStrip {
  text: string
  sentence: string | null
  ariaLabel: string
  state: TicketState
  pendingTear: boolean
}

export type LeaderPhase =
  | 'idle'
  | 'probing'
  | 'hashing'
  | 'searching'
  | 'downloading'
  | 'flash'
  | 'done'

export type ThreadingFailure =
  | 'file-too-small'
  | 'offline'
  | 'timeout'
  | 'no-results'
  | 'unauthorized'
  | 'quota-exhausted'
  | 'rate-limited'
  | 'link-expired'
  | 'undecodable'
  | 'no-codec'
  | 'cancelled'

export type NextAction =
  | 'filename-search'
  | 'subdl'
  | 'manual'
  | 'skip'
  | 'sign-in'
  | 'webcodecs'
  | 'retry'

export interface ThreadingState {
  phase: LeaderPhase
  sweep: number // 0..1; FROZEN while `failure` is set
  hash: MovieHash | null
  parsed: ParsedName | null
  candidates: ScoredCandidate[]
  picked: ScoredCandidate | null
  quota: Quota
  failure: ThreadingFailure | null
  next: NextAction[]
}

// ── web-only: what the browser can actually play ──

export interface CodecSupport {
  label: string
  ok: boolean
  via: 'native' | 'webcodecs' | 'none'
}

export interface Capability {
  line: string
  codecs: CodecSupport[]
  webCodecsAvailable: boolean
}

// ── Worker contract ──

export interface WorkerError {
  error:
    | 'sign-in-required'
    | 'forbidden-origin'
    | 'not-found'
    | 'method-not-allowed'
    | 'rate-limited'
    | 'bad-link'
    | 'too-large'
    | 'upstream'
  sentence: string // what Lite prints under the stalled leader. Never a code
  retryAfterSeconds?: number
}

// ── IndexedDB records (web tier) ──

export interface CachedSubtitle {
  // key: `${hash}|${lang}`
  hash: MovieHash
  language: string
  provider: Provider
  release: string | null
  syncedByHash: boolean
  vttText: string // stored already converted, so offline reattach is instant
  bytes: number
  fetchedAt: number
}

export interface StoredOffset {
  hash: MovieHash
  delayMs: number
}

export interface LiteSession {
  jwt: string | null
  jwtExpiresAt: number | null
  quota: Quota
  languages: string[]
  preferHearingImpaired: boolean
}
