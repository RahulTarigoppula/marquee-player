export interface Env {
  OS_API_KEY: string        // secret
  ALLOWED_ORIGIN: string    // var
  UPSTREAM_BASE: string     // var
  USER_AGENT: string        // var
  TMDB_READ_TOKEN?: string  // optional secret; absent => /api/tmdb/* answers 404
}

// Only these upstream paths may be reached at all.
const ALLOW: RegExp[] = [
  /^\/subtitles$/,
  /^\/login$/,
  /^\/logout$/,
  /^\/download$/,
  /^\/infos\/(languages|formats|user)$/,
  /^\/utilities\/guessit$/,
  /^\/tmdb\/.+$/,
]

// Responses that must never sit in a shared cache.
const NO_STORE = new Set(['/login', '/logout', '/download'])

// Hosts the subtitle-file route may fetch from.
const LINK_HOSTS = /(^|\.)opensubtitles\.(com|org)$/
const MAX_SUBTITLE_BYTES = 2 * 1024 * 1024
const IP_LIMIT_PER_MIN = 60

// The TMDB route has its own upstream; UPSTREAM_BASE is OpenSubtitles only.
const TMDB_BASE = 'https://api.themoviedb.org/3'

function cors(origin: string): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Max-Age': '86400',
    // Lite reads the wait from a 429 and the gateway's budget; without this the browser hides them.
    'Access-Control-Expose-Headers': 'Retry-After, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset',
    Vary: 'Origin',
  }
}

function allowedOrigin(req: Request, env: Env): string | null {
  const o = req.headers.get('Origin')
  if (!o) return null                                    // curl / native builds: refused by design
  if (o === env.ALLOWED_ORIGIN) return o
  if (/^http:\/\/localhost(:\d+)?$/.test(o)) return o    // vite dev server
  return null
}

function err(status: number, origin: string, body: {
  error: string; sentence: string; retryAfterSeconds?: number
}, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors(origin), 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra,
    },
  })
}

// A thrown upstream fetch (DNS, reset, timeout) must still be WorkerError JSON, never the
// platform's own HTML error page.
function unreachable(origin: string): Response {
  return err(502, origin, {
    error: 'upstream',
    sentence: "The subtitle service didn't answer — try again in a moment.",
  })
}

// The 2 MB cap for bodies that arrive without a Content-Length: count bytes as they stream
// through and abort the stream past the cap. Nothing is buffered.
function capped(
  body: ReadableStream<Uint8Array> | null,
  max: number,
): ReadableStream<Uint8Array> | null {
  if (!body) return null
  let seen = 0
  return body.pipeThrough(new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, ctrl) {
      seen += chunk.byteLength
      if (seen > max) ctrl.error(new Error('too-large'))
      else ctrl.enqueue(chunk)
    },
  }))
}

// The one error that must NOT carry CORS headers: a 403 with Allow-Origin would
// defeat the allow-list. Lite still gets a body it can print (ARCHITECTURE §12).
function forbiddenOrigin(): Response {
  return new Response(
    JSON.stringify({
      error: 'forbidden-origin',
      sentence: "This build isn't allowed to talk to the subtitle service.",
    }),
    { status: 403, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } },
  )
}

// A best-effort soft cap: 60 requests per minute per client IP, counted in the Cache API. No KV,
// no logging. HONEST LIMITS: the Cache API is per data centre, and on a *.workers.dev hostname
// cache operations are no-ops — there this never limits anything (OpenSubtitles' own per-key and
// per-user limits still apply). It only bites on a custom domain. It always fails OPEN: a cache
// error never blocks a request.
async function overRateLimit(req: Request): Promise<boolean> {
  try {
    const ip = req.headers.get('cf-connecting-ip') ?? 'anon'
    const minute = Math.floor(Date.now() / 60_000)
    const key = new Request(`https://rl.marquee.invalid/${encodeURIComponent(ip)}/${minute}`)
    const cache = caches.default
    const hit = await cache.match(key)
    const n = hit ? Number(await hit.text()) : 0
    if (n >= IP_LIMIT_PER_MIN) return true
    await cache.put(key, new Response(String(n + 1), {
      headers: { 'Cache-Control': 'max-age=90' },
    }))
  } catch {
    // fail open
  }
  return false
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const origin = allowedOrigin(req, env)

    // OpenSubtitles' own preflight is a 403, so we answer it ourselves.
    if (req.method === 'OPTIONS') {
      return origin
        ? new Response(null, { status: 204, headers: cors(origin) })
        : forbiddenOrigin()                              // deliberately NO cors headers here
    }
    if (!origin) return forbiddenOrigin()
    if (req.method !== 'GET' && req.method !== 'POST') {
      return err(405, origin, {
        error: 'method-not-allowed',
        sentence: 'That request method is not proxied.',
      })
    }
    if (await overRateLimit(req)) {
      return err(429, origin, {
        error: 'rate-limited',
        sentence: 'Too many requests from your network — try again in a minute.',
        retryAfterSeconds: 60,
      }, { 'Retry-After': '60' })
    }

    const url = new URL(req.url)
    if (!url.pathname.startsWith('/api/')) {
      return err(404, origin, { error: 'not-found', sentence: 'That endpoint is not proxied.' })
    }
    // Normalise "." / ".." / duplicate slashes before matching the allow-list.
    const path = new URL(url.pathname.slice(4), 'https://x').pathname

    // ── the temporary-link route: host allow-list, size cap, streamed ──
    if (path === '/subtitle-file') {
      const link = url.searchParams.get('link')
      if (!link) return err(400, origin, { error: 'bad-link', sentence: 'No subtitle link was given.' })
      let target: URL
      try { target = new URL(link) } catch {
        return err(400, origin, { error: 'bad-link', sentence: 'That subtitle link is not a valid URL.' })
      }
      if (target.protocol !== 'https:' || !LINK_HOSTS.test(target.hostname)) {
        return err(403, origin, { error: 'bad-link', sentence: 'That subtitle link is not from OpenSubtitles.' })
      }
      let r: Response
      try {
        r = await fetch(target.toString(), { headers: { 'User-Agent': env.USER_AGENT } })
      } catch {
        return unreachable(origin)
      }
      const type = r.headers.get('Content-Type') ?? ''
      const len = Number(r.headers.get('Content-Length') ?? '0')
      if (!/^(text|application)\//.test(type)) {
        return err(415, origin, { error: 'bad-link', sentence: "That link didn't return a subtitle file." })
      }
      if (len > MAX_SUBTITLE_BYTES) {
        return err(413, origin, { error: 'too-large', sentence: 'That subtitle file is too large to fetch here.' })
      }
      // Content-Length is the fast path above; this enforces the cap when it is absent or wrong.
      const passed = new Response(capped(r.body, MAX_SUBTITLE_BYTES), r)
      for (const [k, v] of Object.entries(cors(origin))) passed.headers.set(k, v)
      passed.headers.set('Cache-Control', 'no-store')
      passed.headers.delete('Set-Cookie')
      return passed
    }

    if (!ALLOW.some((re) => re.test(path))) {
      return err(404, origin, { error: 'not-found', sentence: 'That endpoint is not proxied.' })
    }

    // ── optional TMDB metadata: a different upstream, and a server-side Bearer ──
    // The token comes from the var and NEVER from the client; a client Authorization
    // header is not forwarded on this route.
    if (path.startsWith('/tmdb/')) {
      if (!env.TMDB_READ_TOKEN) {
        return err(404, origin, {
          error: 'not-found',
          sentence: 'This build has no TMDB token, so artwork is off.',
        })
      }
      const tq = new URLSearchParams(
        [...new URLSearchParams(url.search).entries()].sort(([a], [b]) => a.localeCompare(b)),
      ).toString()
      let t: Response
      try {
        t = await fetch(TMDB_BASE + path.slice(5) + (tq ? `?${tq}` : ''), {
          headers: {
            Authorization: `Bearer ${env.TMDB_READ_TOKEN}`,
            'User-Agent': env.USER_AGENT,
            Accept: 'application/json',
          },
        })
      } catch {
        return unreachable(origin)
      }
      const meta = new Response(t.body, t)
      for (const [k, v] of Object.entries(cors(origin))) meta.headers.set(k, v)
      meta.headers.set('Cache-Control', 'private, max-age=3600')
      meta.headers.delete('Set-Cookie')
      return meta
    }

    // A download without a user JWT would spend the shared anonymous pool on OUR IP.
    const auth = req.headers.get('Authorization')
    if ((path === '/download' || path === '/infos/user') && !auth) {
      return err(401, origin, {
        error: 'sign-in-required',
        sentence: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
      })
    }

    // Sort params so the gateway's canonical-URL 301 never fires.
    const sorted = new URLSearchParams(
      [...new URLSearchParams(url.search).entries()].sort(([a], [b]) => a.localeCompare(b)),
    )
    const qs = sorted.toString()

    const headers = new Headers({
      'Api-Key': env.OS_API_KEY,          // the entire reason this Worker exists
      'User-Agent': env.USER_AGENT,       // mandatory upstream, and must be descriptive
      Accept: 'application/json',
      'Content-Type': 'application/json',
    })
    // The user's own JWT is forwarded verbatim. Nothing else from the client is:
    // no cookies, no X-Forwarded-*, and a client-supplied Api-Key is dropped.
    if (auth) headers.set('Authorization', auth)

    const body = req.method === 'POST' ? await req.text() : undefined
    let res: Response
    try {
      res = await fetch(env.UPSTREAM_BASE + path + (qs ? `?${qs}` : ''), {
        method: req.method,
        headers,
        body,
      })
    } catch {
      return unreachable(origin)
    }

    const out = new Response(res.body, res)   // streamed, never buffered
    for (const [k, v] of Object.entries(cors(origin))) out.headers.set(k, v)
    out.headers.set(
      'Cache-Control',
      req.method === 'GET' && !NO_STORE.has(path) ? 'private, max-age=300' : 'no-store',
    )
    out.headers.delete('Set-Cookie')
    // 429 / 406 / 401 / 410 and the X-RateLimit-* headers pass through untouched:
    // the client owns the copy, the Worker owns the transport.
    return out
  },
}
