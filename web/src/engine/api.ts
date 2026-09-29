// The Worker client (IMPLEMENTATION-PROMPT §7.1, §7.5, §7.6). Lite talks ONLY to
// `${VITE_API_BASE}` — the Worker holds the key. fetch is injected, so this file stays pure.
// Every HTTP status is mapped to a ThreadingFailure + one plain sentence BEFORE it reaches
// state. Nothing here retries: the leader owns the single 410 retry.
import type {
  Candidate,
  MovieHash,
  OsDownloadResponse,
  OsLoginResponse,
  OsSearchResponse,
  ParsedName,
  ThreadingFailure,
  WorkerError,
} from './types'

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

export interface ApiFailure {
  ok: false
  failure: ThreadingFailure
  sentence: string
  status: number | null
  retryAfterSeconds?: number
  /** A 406 body still carries the quota (remaining 0 + the reset instant). */
  download?: Pick<OsDownloadResponse, 'requests' | 'remaining' | 'reset_time_utc'>
}
export interface ApiOk<T> {
  ok: true
  value: T
}
export type ApiResult<T> = ApiOk<T> | ApiFailure

export const DEFAULT_RETRY_AFTER = 2 // seconds, when a 429 omits Retry-After

const SENTENCES = {
  offline: "You're offline — playing without new subtitles.",
  signIn: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
  expired: 'Ticket expired — sign in again.',
  quota: 'No tickets left tonight — sign in for more, or use the Subdl slot.',
  gone: 'That print expired — fetching a fresh link.',
  upstream: "The subtitle service didn't answer — playing without new subtitles.",
  wait: (s: number) => `OpenSubtitles asked us to wait ${s} s.`,
} as const

/** Params sorted alphabetically: an unsorted query costs a 301 (and a second CORS preflight). */
export function sortedQuery(params: Record<string, string | number | null | undefined>): string {
  const entries = Object.entries(params)
    .filter(
      (e): e is [string, string | number] => e[1] !== null && e[1] !== undefined && e[1] !== '',
    )
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => [k, String(v)])
  return new URLSearchParams(entries).toString()
}

export function hashSearchParams(hash: MovieHash, languages: string[]) {
  return {
    languages: languages.join(','),
    moviehash: hash,
    moviehash_match: 'include',
    order_by: 'download_count',
  }
}

/** Rung 3. A 'low' confidence parse sends the RAW filename and lets the server guessit it. */
export function nameSearchParams(p: ParsedName, languages: string[]) {
  if (p.confidence === 'low') return { languages: languages.join(','), query: p.raw }
  return {
    episode_number: p.episode,
    languages: languages.join(','),
    query: p.title,
    season_number: p.season,
    year: p.year,
  }
}

export function candidatesFromSearch(r: OsSearchResponse): Candidate[] {
  return r.data.flatMap(({ attributes: a }) => {
    const file = a.files[0]
    if (!file) return []
    return [
      {
        provider: 'opensubtitles' as const,
        id: String(file.file_id),
        language: a.language ?? 'und',
        release: a.release,
        downloadCount: a.download_count,
        hearingImpaired: a.hearing_impaired,
        moviehashMatch: a.moviehash_match === true, // ABSENT means false: the bulb never guesses
        machineTranslated: a.machine_translated,
        aiTranslated: a.ai_translated,
        fps: a.fps,
        feature: a.feature_details,
      },
    ]
  })
}

function retryAfter(res: Response, body: Partial<WorkerError> | null): number {
  const header = Number(res.headers.get('Retry-After'))
  if (Number.isFinite(header) && header > 0) return header
  return body?.retryAfterSeconds ?? DEFAULT_RETRY_AFTER
}

async function readJson(res: Response): Promise<unknown> {
  try {
    return await res.json()
  } catch {
    return null
  }
}

const asWorkerError = (b: unknown): Partial<WorkerError> | null =>
  typeof b === 'object' && b !== null && 'sentence' in b ? (b as WorkerError) : null

/** Map a non-2xx response to a typed failure and one sentence. */
export async function failureOf(res: Response): Promise<ApiFailure> {
  const body = await readJson(res)
  const we = asWorkerError(body)
  const base = { ok: false as const, status: res.status }
  switch (res.status) {
    case 401:
      return {
        ...base,
        failure: 'unauthorized',
        sentence: we?.error === 'sign-in-required' ? SENTENCES.signIn : SENTENCES.expired,
      }
    case 403:
      return { ...base, failure: 'offline', sentence: we?.sentence ?? SENTENCES.upstream }
    case 406: {
      const dl = body as Partial<OsDownloadResponse> | null
      const out: ApiFailure = { ...base, failure: 'quota-exhausted', sentence: SENTENCES.quota }
      if (dl && typeof dl.remaining === 'number' && typeof dl.reset_time_utc === 'string') {
        out.download = {
          requests: dl.requests ?? 0,
          remaining: dl.remaining,
          reset_time_utc: dl.reset_time_utc,
        }
      }
      return out
    }
    case 410:
      return { ...base, failure: 'link-expired', sentence: SENTENCES.gone }
    case 429: {
      const s = retryAfter(res, we)
      return { ...base, failure: 'rate-limited', sentence: SENTENCES.wait(s), retryAfterSeconds: s }
    }
    default:
      return { ...base, failure: 'offline', sentence: we?.sentence ?? SENTENCES.upstream }
  }
}

const offline = (e: unknown): ApiFailure =>
  e instanceof DOMException && e.name === 'AbortError'
    ? { ok: false, failure: 'cancelled', sentence: 'Playing without subtitles.', status: null }
    : { ok: false, failure: 'offline', sentence: SENTENCES.offline, status: null }

export interface ApiOptions {
  base: string // e.g. https://marquee-proxy.<sub>.workers.dev/api
  fetch: FetchLike
  jwt: () => string | null
}

export function createApi(o: ApiOptions) {
  async function call<T>(
    path: string,
    init: RequestInit,
    read: (r: Response) => Promise<T>,
  ): Promise<ApiResult<T>> {
    let res: Response
    try {
      res = await o.fetch(`${o.base}${path}`, init)
    } catch (e) {
      return offline(e)
    }
    if (!res.ok) return failureOf(res)
    try {
      return { ok: true, value: await read(res) }
    } catch (e) {
      return offline(e)
    }
  }
  const json = <T>(r: Response) => r.json() as Promise<T>
  const auth = (): Record<string, string> => {
    const t = o.jwt()
    return t ? { Authorization: `Bearer ${t}` } : {}
  }
  const get = <T>(path: string, signal?: AbortSignal) =>
    call<T>(path, signal ? { method: 'GET', signal } : { method: 'GET' }, json)
  const post = <T>(
    path: string,
    body: unknown,
    headers: Record<string, string>,
    signal?: AbortSignal,
  ) =>
    call<T>(
      path,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: JSON.stringify(body),
        ...(signal ? { signal } : {}),
      },
      json,
    )

  return {
    search(params: Record<string, string | number | null | undefined>, signal?: AbortSignal) {
      return get<OsSearchResponse>(`/subtitles?${sortedQuery(params)}`, signal)
    },
    login(username: string, password: string) {
      return post<OsLoginResponse>('/login', { password, username }, {})
    },
    download(fileId: number, signal?: AbortSignal) {
      return post<OsDownloadResponse>(
        '/download',
        { file_id: fileId, sub_format: 'srt' },
        auth(),
        signal,
      )
    },
    /** The temporary link, fetched through the Worker (its own CORS posture is unverified). */
    subtitleFile(link: string, signal?: AbortSignal) {
      const init: RequestInit = signal ? { method: 'GET', signal } : { method: 'GET' }
      return call(`/subtitle-file?${sortedQuery({ link })}`, init, (r) => r.text())
    },
    userInfo() {
      return call<unknown>('/infos/user', { method: 'GET', headers: auth() }, json)
    },
  }
}

export type Api = ReturnType<typeof createApi>
