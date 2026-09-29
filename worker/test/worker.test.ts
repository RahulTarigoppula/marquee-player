// Every invariant of IMPLEMENTATION-PROMPT §7.6 / TESTING §7.1 (P1–P21).
// The Worker's default export is called directly under Node. Upstream is never contacted: global
// fetch is replaced with a router over the fixtures, and a fetch with no route fails the test.
// caches.default is an in-memory Cache from test/setup.ts.
import { afterEach, beforeEach, describe, expect, it, type MockInstance, vi } from 'vitest'
import worker, { type Env } from '../src/index'
import wranglerToml from '../wrangler.toml?raw'
import unauthorized from './fixtures/401.json'
import download406 from './fixtures/download-406.json'
import downloadOk from './fixtures/download-ok.json'
import loginOk from './fixtures/login-ok.json'
import searchHit from './fixtures/search-hash-hit.json'
import tmdbFind from './fixtures/tmdb-find.json'

const KEY = 'test-key-SECRET-123'
const TMDB_TOKEN = 'tmdb-TOKEN-456-secret'
const ORIGIN = 'https://owner.github.io'
const DEV_ORIGIN = 'http://localhost:5173'
const W = 'https://marquee-proxy.example.workers.dev'
const OS = 'https://api.opensubtitles.com/api/v1'
const LINK = 'https://www.opensubtitles.com/download/FIXTURE/subfile/The.Third.Man.1949.srt'
const SRT = '1\n00:00:01,000 --> 00:00:03,000\nThe Third Man\n'

// [vars] come from the real wrangler.toml; only the placeholder origin is replaced.
function tomlVar(name: string): string {
  const m = wranglerToml.match(new RegExp(`^${name}\\s*=\\s*"([^"]*)"`, 'm'))
  if (!m?.[1]) throw new Error(`wrangler.toml has no [vars] ${name}`)
  return m[1]
}
const env: Env = {
  OS_API_KEY: KEY,
  ALLOWED_ORIGIN: ORIGIN,
  UPSTREAM_BASE: tomlVar('UPSTREAM_BASE'),
  USER_AGENT: tomlVar('USER_AGENT'),
}

const NOT_FOUND = { error: 'not-found', sentence: 'That endpoint is not proxied.' }
const FORBIDDEN = {
  error: 'forbidden-origin',
  sentence: "This build isn't allowed to talk to the subtitle service.",
}
const SIGN_IN = {
  error: 'sign-in-required',
  sentence: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
}

// ── upstream stub ──────────────────────────────────────────────────────────────────────────

type Handler = (url: URL, init: RequestInit | undefined) => Response | Promise<Response>
interface Seen {
  url: URL
  method: string
  headers: Headers
  body: string | undefined
}

let routes: Handler | undefined
let seen: Seen[] = []
let fetchSpy: MockInstance<typeof fetch>
let consoleSpies: MockInstance[] = []
let ipCounter = 0
let ip = ''
// Every serialised response in the test, grepped for secrets in afterEach.
let transcript: string[] = []

function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  })
}

function upstream(h: Handler): void {
  routes = h
}

beforeEach(() => {
  seen = []
  transcript = []
  routes = undefined
  ip = `203.0.113.${++ipCounter}` // fresh rate-limit bucket per test
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input))
    seen.push({
      url,
      method: init?.method ?? 'GET',
      headers: new Headers(init?.headers),
      body: typeof init?.body === 'string' ? init.body : undefined,
    })
    if (!routes) throw new Error(`unexpected upstream fetch: ${url}`)
    return routes(url, init)
  })
  consoleSpies = (['log', 'info', 'warn', 'error', 'debug', 'trace'] as const).map((m) =>
    vi.spyOn(console, m).mockImplementation(() => {}),
  )
})

afterEach(() => {
  // Snapshot first and restore before asserting, so one failure cannot leak spies onward.
  const written = consoleSpies.flatMap((s) =>
    s.mock.calls.map((args) => args.map(String).join(' ')),
  )
  vi.restoreAllMocks()
  vi.useRealTimers()
  // P6: nothing is written to console at all, so the secret cannot be either.
  expect(written).toEqual([])
  for (const raw of transcript) {
    expect(raw).not.toContain(KEY)
    expect(raw).not.toContain(TMDB_TOKEN)
  }
})

// ── request helper ─────────────────────────────────────────────────────────────────────────

interface Call {
  res: Response
  text: string
  body: unknown
}

async function call(
  path: string,
  init: RequestInit & { origin?: string | null; ip?: string } = {},
  e: Env = env,
): Promise<Call> {
  const headers = new Headers(init.headers)
  const origin = init.origin === undefined ? ORIGIN : init.origin
  if (origin !== null) headers.set('Origin', origin)
  if (!headers.has('cf-connecting-ip')) headers.set('cf-connecting-ip', init.ip ?? ip)
  const res = await worker.fetch(new Request(W + path, { ...init, headers }), e)
  const text = await res.clone().text()
  const head = [...res.headers].map(([k, v]) => `${k}: ${v}`).join('\n')
  transcript.push(`${res.status} ${res.statusText}\n${head}\n\n${text}`)
  let body: unknown
  try {
    body = JSON.parse(text)
  } catch {
    body = undefined
  }
  return { res, text, body }
}

function expectWorkerError(c: Call, status: number, error: string): void {
  expect(c.res.status).toBe(status)
  expect(c.res.headers.get('Content-Type')).toBe('application/json')
  expect(c.res.headers.get('Cache-Control')).toBe('no-store')
  const b = c.body as { error: unknown; sentence: unknown }
  expect(b.error).toBe(error)
  expect(typeof b.sentence).toBe('string')
  expect((b.sentence as string).length).toBeGreaterThan(0)
}

function expectCors(res: Response, origin = ORIGIN): void {
  expect(res.headers.get('Access-Control-Allow-Origin')).toBe(origin)
  expect(res.headers.get('Access-Control-Allow-Methods')).toBe('GET,POST,OPTIONS')
  expect(res.headers.get('Access-Control-Allow-Headers')).toBe('Content-Type,Authorization')
  expect(res.headers.get('Access-Control-Max-Age')).toBe('86400')
  expect(res.headers.get('Vary')).toBe('Origin')
}

function expectNoCors(res: Response): void {
  for (const k of res.headers.keys()) expect(k.toLowerCase()).not.toMatch(/^access-control-/)
}

const searchRoute: Handler = (url) =>
  url.origin + url.pathname === `${OS}/subtitles`
    ? json(searchHit, 200, {
        'X-RateLimit-Limit': '40',
        'X-RateLimit-Remaining': '39',
        'X-RateLimit-Reset': '1',
      })
    : json({ unexpected: url.toString() }, 599)

// ── P1–P4: origin allow-list and preflight ─────────────────────────────────────────────────

describe('P1–P4 origin allow-list', () => {
  it('P1 answers the preflight itself: 204 with CORS for the allowed origin', async () => {
    const c = await call('/api/subtitles', {
      method: 'OPTIONS',
      headers: {
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'authorization',
      },
    })
    expect(c.res.status).toBe(204)
    expectCors(c.res)
    expect(c.text).toBe('')
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('P3 localhost on any port is allowed and echoed, not the production origin', async () => {
    for (const o of [DEV_ORIGIN, 'http://localhost', 'http://localhost:4173']) {
      const pre = await call('/api/subtitles', { method: 'OPTIONS', origin: o })
      expect(pre.res.status).toBe(204)
      expectCors(pre.res, o)
    }
    upstream(searchRoute)
    const c = await call('/api/subtitles?languages=en', { origin: DEV_ORIGIN })
    expect(c.res.status).toBe(200)
    expectCors(c.res, DEV_ORIGIN)
  })

  it.each([
    'https://evil.example',
    'https://owner.github.io.evil.example',
    'https://evil.github.io',
    'http://owner.github.io',
    'https://localhost:5173',
    'http://localhost.evil.example',
    'http://localhost:5173/path',
    'null',
  ])('P2 rejects origin %s with 403, no CORS headers, WorkerError body, no upstream', async (o) => {
    for (const method of ['OPTIONS', 'GET', 'POST']) {
      const c = await call('/api/subtitles?languages=en', { method, origin: o })
      expectWorkerError(c, 403, 'forbidden-origin')
      expect(c.body).toEqual(FORBIDDEN)
      expectNoCors(c.res)
    }
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('P4 no Origin header at all → 403 forbidden-origin, no CORS, no upstream', async () => {
    for (const method of ['OPTIONS', 'GET', 'POST']) {
      const c = await call('/api/subtitles?languages=en&moviehash=8e245d9679d31e12', {
        method,
        origin: null,
      })
      expectWorkerError(c, 403, 'forbidden-origin')
      expect(c.body).toEqual(FORBIDDEN)
      expectNoCors(c.res)
    }
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('P4 a rejected origin is refused even on an otherwise unknown path or method', async () => {
    expectNoCors((await call('/api/admin', { origin: 'https://evil.example' })).res)
    expectNoCors((await call('/api/subtitles', { method: 'PUT', origin: null })).res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

// ── P5, P9, P10: what is forwarded ─────────────────────────────────────────────────────────

describe('P5/P9/P10 forwarding', () => {
  it('P5 forwards to UPSTREAM_BASE with the server-side Api-Key and User-Agent', async () => {
    upstream(searchRoute)
    const c = await call('/api/subtitles?languages=en&moviehash=8e245d9679d31e12')
    expect(c.res.status).toBe(200)
    expect(c.body).toEqual(searchHit)
    expectCors(c.res)
    expect(seen).toHaveLength(1)
    const s = seen[0]!
    expect(s.url.origin + s.url.pathname).toBe(`${OS}/subtitles`)
    expect(s.method).toBe('GET')
    expect(s.headers.get('Api-Key')).toBe(KEY)
    expect(s.headers.get('User-Agent')).toBe('Marquee-Web v1.0.0')
    expect(s.headers.get('Accept')).toBe('application/json')
  })

  it('P9 re-sorts query params alphabetically before forwarding', async () => {
    upstream(searchRoute)
    await call(
      '/api/subtitles?moviehash_match=include&moviehash=8e245d9679d31e12&languages=en,fr&imdb_id=41959',
    )
    expect(seen[0]!.url.search).toBe(
      '?imdb_id=41959&languages=en%2Cfr&moviehash=8e245d9679d31e12&moviehash_match=include',
    )
    const keys = [...seen[0]!.url.searchParams.keys()]
    expect(keys).toEqual([...keys].sort())
  })

  it('P9 omits the "?" entirely when there are no params', async () => {
    upstream(() => json({ data: [] }))
    await call('/api/infos/languages')
    expect(seen[0]!.url.toString()).toBe(`${OS}/infos/languages`)
  })

  it('P10 forwards Authorization verbatim; strips client Api-Key, cookies, X-Forwarded-*', async () => {
    upstream(searchRoute)
    const jwt = 'Bearer eyJhbGciOiJIUzI1NiJ9.fixture.token'
    await call('/api/subtitles?languages=en', {
      headers: {
        Authorization: jwt,
        'Api-Key': 'client-supplied-key',
        Cookie: 'session=abc; other=def',
        'X-Forwarded-For': '198.51.100.7',
        'X-Forwarded-Host': 'evil.example',
        'X-Forwarded-Proto': 'http',
        'X-Real-IP': '198.51.100.7',
        'User-Agent': 'client-UA/9.9',
        Referer: 'https://owner.github.io/marquee/',
      },
    })
    const h = seen[0]!.headers
    expect(h.get('Authorization')).toBe(jwt)
    expect(h.get('Api-Key')).toBe(KEY)
    expect(h.get('User-Agent')).toBe('Marquee-Web v1.0.0')
    const names = [...h.keys()].map((k) => k.toLowerCase()).sort()
    expect(names).toEqual(['accept', 'api-key', 'authorization', 'content-type', 'user-agent'])
  })

  it('P10 without a client Authorization none is invented', async () => {
    upstream(searchRoute)
    await call('/api/subtitles?languages=en')
    expect(seen[0]!.headers.has('Authorization')).toBe(false)
  })

  it('POST bodies are passed through to login unchanged', async () => {
    upstream((url) => (url.pathname.endsWith('/login') ? json(loginOk) : json({}, 599)))
    const body = JSON.stringify({ username: 'u', password: 'p' })
    const c = await call('/api/login', {
      method: 'POST',
      body,
      headers: { 'Content-Type': 'application/json' },
    })
    expect(c.res.status).toBe(200)
    expect(c.body).toEqual(loginOk)
    expect(seen[0]!.method).toBe('POST')
    expect(seen[0]!.body).toBe(body)
    expect(seen[0]!.url.toString()).toBe(`${OS}/login`)
  })

  it.each([
    ['/api/subtitles', 'GET', '/subtitles'],
    ['/api/login', 'POST', '/login'],
    ['/api/logout', 'POST', '/logout'],
    ['/api/infos/languages', 'GET', '/infos/languages'],
    ['/api/infos/formats', 'GET', '/infos/formats'],
    ['/api/utilities/guessit?filename=x.mkv', 'GET', '/utilities/guessit'],
  ])('allow-listed %s (%s) forwards to %s', async (path, method, up) => {
    upstream(() => json({ ok: true }))
    const c = await call(path, { method, body: method === 'POST' ? '{}' : undefined })
    expect(c.res.status).toBe(200)
    expect(seen[0]!.url.pathname).toBe(`/api/v1${up}`)
  })
})

// ── P6, P16, P17: the secret and the config ────────────────────────────────────────────────

describe('P6/P16/P17 secrets and config', () => {
  it('P6 no response header carries the key on a successful proxy', async () => {
    // The Worker does not scrub upstream bodies; what it guarantees is that it never itself
    // writes the key into a response. Upstream echo is OpenSubtitles' contract, not ours.
    // So this test checks every header the Worker *adds* or passes and every Worker-authored body.
    upstream(() => json(searchHit, 200, { 'X-Upstream': 'ok' }))
    const c = await call('/api/subtitles?languages=en')
    for (const [, v] of c.res.headers) expect(v).not.toContain(KEY)
  })

  it('P16 wrangler.toml keeps ALLOWED_ORIGIN/UPSTREAM_BASE as vars and no secret literal', () => {
    const vars = wranglerToml.slice(wranglerToml.indexOf('[vars]'))
    expect(vars).toMatch(/^ALLOWED_ORIGIN\s*=\s*"https:\/\/[^"/]+"$/m)
    expect(vars).toMatch(/^UPSTREAM_BASE\s*=\s*"https:\/\/api\.opensubtitles\.com\/api\/v1"$/m)
    expect(vars).toMatch(/^USER_AGENT\s*=\s*"Marquee-Web v\d+\.\d+\.\d+"$/m)
    expect(wranglerToml).not.toMatch(/OS_API_KEY\s*=/)
    expect(wranglerToml).not.toMatch(/TMDB_READ_TOKEN\s*=/)
  })

  it('P16 no key-shaped literal anywhere in the worker sources, config or fixtures', () => {
    const files = import.meta.glob(['../src/**/*', '../*.toml', '../*.json', './fixtures/*'], {
      query: '?raw',
      import: 'default',
      eager: true,
    }) as Record<string, string>
    const names = Object.keys(files)
    expect(names.some((n) => n.endsWith('src/index.ts'))).toBe(true)
    for (const [name, src] of Object.entries(files)) {
      // OpenSubtitles consumer keys are 32 alphanumerics; flag any assignment of one.
      expect(src, name).not.toMatch(/Api-Key['"]?\s*[:=]\s*['"][A-Za-z0-9]{20,}['"]/)
      expect(src, name).not.toMatch(/OS_API_KEY\s*[:=]\s*['"][^'"]+['"]/)
    }
  })

  it('P17 wrangler.toml has no storage/analytics bindings and observability is off', () => {
    // The file's own comments name the forbidden blocks, so grep only the live TOML.
    const live = wranglerToml.replace(/#.*$/gm, '')
    expect(live).not.toMatch(/\[\[\s*kv_namespaces\s*\]\]/)
    expect(live).not.toMatch(/\[\[\s*d1_databases\s*\]\]/)
    expect(live).not.toMatch(/\[\[\s*analytics_engine_datasets\s*\]\]/)
    expect(live).not.toMatch(/\[\[?\s*(r2_buckets|durable_objects|queues)/)
    const obs = live.match(/\[observability\]([^[]*)/)
    expect(obs).not.toBeNull()
    expect(obs![1]).toMatch(/^enabled\s*=\s*false$/m)
    expect(obs![1]).not.toMatch(/=\s*true/)
  })

  it('P6 the key never appears in any Worker-authored error across every route', async () => {
    upstream(() => json({ ok: true }))
    const probes: Array<[string, RequestInit & { origin?: string | null }]> = [
      ['/api/subtitles', { origin: null }],
      ['/api/subtitles', { origin: 'https://evil.example' }],
      ['/api/subtitles', { method: 'DELETE' }],
      ['/api/admin', {}],
      ['/', {}],
      ['/api/download', { method: 'POST', body: '{"file_id":1}' }],
      ['/api/infos/user', {}],
      ['/api/subtitle-file', {}],
      ['/api/subtitle-file?link=nope', {}],
      ['/api/subtitle-file?link=https%3A%2F%2Fevil.example%2Fx.srt', {}],
      ['/api/tmdb/find/tt0041959', {}],
    ]
    for (const [p, init] of probes) {
      const c = await call(p, init)
      expect(c.res.status).toBeGreaterThanOrEqual(400)
    }
    expect(transcript.length).toBe(probes.length) // all grepped in afterEach
  })
})

// ── P7, P8, P14: routing ───────────────────────────────────────────────────────────────────

describe('P7/P8/P14 routing', () => {
  it.each([
    '/api/../../admin',
    '/api/subtitles/../../x',
    '/api/%2e%2e/%2e%2e/admin',
    '/api/subtitles/%2E%2E/%2E%2E/etc/passwd',
    '/api/./../admin',
    '/api//subtitles',
    '/api/subtitles/extra',
    '/api/infos/secret',
    '/api/admin',
    '/api/',
    '/api',
    '/api/tmdb',
    '/api/tmdb/',
    '/subtitles',
    '/api/v1/subtitles',
    '/api/SUBTITLES',
  ])('P7 %s is normalised and rejected 404 not-found before any upstream call', async (p) => {
    const c = await call(p)
    expectWorkerError(c, 404, 'not-found')
    expect((c.body as { error: string }).error).toBe('not-found')
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('P7 the literal not-found body is exact', async () => {
    expect((await call('/api/../../admin')).body).toEqual(NOT_FOUND)
    expect((await call('/api/subtitles/../../x')).body).toEqual(NOT_FOUND)
  })

  it('P7 a traversal that normalises onto a gated route still hits the gate', async () => {
    const c = await call('/api/infos/../download', { method: 'POST', body: '{}' })
    expect(c.body).toEqual(SIGN_IN)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it.each(['/', '/health', '/healthz', '/favicon.ico'])('P8 %s → 404 not-found', async (p) => {
    const c = await call(p)
    expectWorkerError(c, 404, 'not-found')
    expect(c.body).toEqual(NOT_FOUND)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it.each(['PUT', 'PATCH', 'DELETE'])('P14 %s → 405 method-not-allowed', async (method) => {
    const c = await call('/api/subtitles', { method, body: method === 'DELETE' ? null : '{}' })
    expectWorkerError(c, 405, 'method-not-allowed')
    expect(c.body).toEqual({
      error: 'method-not-allowed',
      sentence: 'That request method is not proxied.',
    })
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

// ── P11, P12: upstream statuses pass through ───────────────────────────────────────────────

describe('P11/P12 upstream pass-through', () => {
  it('P11 upstream 429 keeps its status, body, Retry-After and X-RateLimit-*', async () => {
    upstream(() =>
      json({ message: 'Throttle limit reached. Retry later.' }, 429, {
        'Retry-After': '2',
        'X-RateLimit-Limit': '40',
        'X-RateLimit-Remaining': '0',
        'X-RateLimit-Reset': '2',
      }),
    )
    const c = await call('/api/subtitles?languages=en')
    expect(c.res.status).toBe(429)
    expect(c.body).toEqual({ message: 'Throttle limit reached. Retry later.' })
    expect(c.res.headers.get('Retry-After')).toBe('2')
    expect(c.res.headers.get('X-RateLimit-Limit')).toBe('40')
    expect(c.res.headers.get('X-RateLimit-Remaining')).toBe('0')
    expect(c.res.headers.get('X-RateLimit-Reset')).toBe('2')
    expectCors(c.res)
  })

  it('P11 X-RateLimit-* also pass through on a 200', async () => {
    upstream(searchRoute)
    const c = await call('/api/subtitles?languages=en')
    expect(c.res.headers.get('X-RateLimit-Remaining')).toBe('39')
  })

  it('P12 upstream 406 from /download passes through unchanged', async () => {
    upstream(() => json(download406, 406))
    const c = await call('/api/download', {
      method: 'POST',
      body: '{"file_id":1234567}',
      headers: { Authorization: 'Bearer eyJ.jwt' },
    })
    expect(c.res.status).toBe(406)
    expect(c.body).toEqual(download406)
    expect(c.res.headers.get('Cache-Control')).toBe('no-store')
  })

  it('P12 upstream 401 passes through unchanged', async () => {
    upstream(() => json(unauthorized, 401))
    const c = await call('/api/infos/user', { headers: { Authorization: 'Bearer expired' } })
    expect(c.res.status).toBe(401)
    expect(c.body).toEqual(unauthorized)
  })

  it('P12 upstream 410 (expired link) passes through the subtitle-file route', async () => {
    upstream(
      () =>
        new Response('This link has expired', {
          status: 410,
          headers: { 'Content-Type': 'text/plain' },
        }),
    )
    const c = await call(`/api/subtitle-file?link=${encodeURIComponent(LINK)}`)
    expect(c.res.status).toBe(410)
    expect(c.text).toBe('This link has expired')
    expectCors(c.res)
  })

  it('P12 upstream 5xx status passes through too', async () => {
    upstream(() => json({ message: 'bad gateway' }, 502))
    const c = await call('/api/subtitles?languages=en')
    expect(c.res.status).toBe(502)
  })
})

// ── P13: caching and cookies ───────────────────────────────────────────────────────────────

describe('P13 Cache-Control and Set-Cookie', () => {
  const cookieUpstream: Handler = () =>
    json({ ok: true }, 200, {
      'Set-Cookie': 'cf_bm=abc; Path=/; HttpOnly',
      'Cache-Control': 'public, max-age=86400',
    })

  it('GET /api/subtitles → private, max-age=300 (overriding upstream)', async () => {
    upstream(cookieUpstream)
    const c = await call('/api/subtitles?languages=en')
    expect(c.res.headers.get('Cache-Control')).toBe('private, max-age=300')
    expect(c.res.headers.has('Set-Cookie')).toBe(false)
  })

  it.each([
    ['/api/login', 'POST', {}],
    ['/api/logout', 'POST', { Authorization: 'Bearer eyJ.jwt' }],
    ['/api/download', 'POST', { Authorization: 'Bearer eyJ.jwt' }],
  ])('%s → no-store, Set-Cookie deleted', async (path, method, headers) => {
    upstream(cookieUpstream)
    const c = await call(path, { method, body: '{}', headers })
    expect(c.res.status).toBe(200)
    expect(c.res.headers.get('Cache-Control')).toBe('no-store')
    expect(c.res.headers.has('Set-Cookie')).toBe(false)
    expect(c.text).not.toMatch(/cf_bm/)
  })

  it('subtitle-file → no-store, Set-Cookie deleted', async () => {
    upstream(
      () =>
        new Response(SRT, {
          headers: {
            'Content-Type': 'application/x-subrip',
            'Set-Cookie': 'x=y',
            'Cache-Control': 'public, max-age=600',
          },
        }),
    )
    const c = await call(`/api/subtitle-file?link=${encodeURIComponent(LINK)}`)
    expect(c.res.headers.get('Cache-Control')).toBe('no-store')
    expect(c.res.headers.has('Set-Cookie')).toBe(false)
  })

  it('download returns the link fixture body intact', async () => {
    upstream(() => json(downloadOk))
    const c = await call('/api/download', {
      method: 'POST',
      body: '{"file_id":1234567}',
      headers: { Authorization: 'Bearer eyJ.jwt' },
    })
    expect(c.body).toEqual(downloadOk)
  })
})

// ── P15: streaming ─────────────────────────────────────────────────────────────────────────

describe('P15 streaming', () => {
  it('a 12 MB upstream body is streamed, never buffered by the Worker', async () => {
    const chunk = new Uint8Array(1024 * 1024).fill(0x61)
    let pulled = 0
    const stream = new ReadableStream<Uint8Array>({
      pull(ctrl) {
        if (pulled++ < 12) ctrl.enqueue(chunk)
        else ctrl.close()
      },
    })
    const up = new Response(stream, { headers: { 'Content-Type': 'application/json' } })
    const buffered = [
      vi.spyOn(up, 'arrayBuffer'),
      vi.spyOn(up, 'text'),
      vi.spyOn(up, 'json'),
      vi.spyOn(up, 'blob'),
    ]
    upstream(() => up)
    const req = new Request(`${W}/api/subtitles?languages=en`, {
      headers: { Origin: ORIGIN, 'cf-connecting-ip': ip },
    })
    const res = await worker.fetch(req, env)
    for (const s of buffered) expect(s).not.toHaveBeenCalled()
    // Before the client reads, the Worker has pulled at most the stream's initial buffer.
    expect(pulled).toBeLessThan(12)
    let total = 0
    const reader = res.body!.getReader()
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.byteLength
    }
    expect(total).toBe(12 * 1024 * 1024)
  })
})

// ── P18: the subtitle-file route ───────────────────────────────────────────────────────────

describe('P18 subtitle-file', () => {
  const file = (link: string) => `/api/subtitle-file?link=${encodeURIComponent(link)}`

  it('streams a text/plain opensubtitles.com link back 200 with CORS and no-store', async () => {
    upstream(
      () =>
        new Response(SRT, {
          headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Content-Length': '50' },
        }),
    )
    const c = await call(file(LINK))
    expect(c.res.status).toBe(200)
    expect(c.text).toBe(SRT)
    expectCors(c.res)
    expect(c.res.headers.get('Cache-Control')).toBe('no-store')
    expect(seen[0]!.url.toString()).toBe(LINK)
    // The temporary link is fetched with our UA only: no Api-Key, no client Authorization.
    expect(seen[0]!.headers.get('User-Agent')).toBe('Marquee-Web v1.0.0')
    expect(seen[0]!.headers.has('Api-Key')).toBe(false)
    expect(seen[0]!.headers.has('Authorization')).toBe(false)
  })

  it.each([
    'https://opensubtitles.com/x.srt',
    'https://dl.opensubtitles.org/x.srt',
    'https://a.b.opensubtitles.com/x.srt',
  ])('accepts allow-listed host %s', async (link) => {
    upstream(() => new Response(SRT, { headers: { 'Content-Type': 'application/octet-stream' } }))
    expect((await call(file(link))).res.status).toBe(200)
  })

  it('400 bad-link when link is missing', async () => {
    const c = await call('/api/subtitle-file')
    expectWorkerError(c, 400, 'bad-link')
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it.each(['not a url', '/relative/x.srt', ''])('400 bad-link for invalid link %j', async (l) => {
    const c = await call(`/api/subtitle-file?link=${encodeURIComponent(l)}`)
    expectWorkerError(c, 400, 'bad-link')
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it.each([
    'https://evil.example/x.srt',
    'http://www.opensubtitles.com/x.srt',
    'https://opensubtitles.com.evil.example/x.srt',
    'https://evilopensubtitles.com/x.srt',
    'https://www.opensubtitles.net/x.srt',
    'https://user@evil.example/?h=opensubtitles.com',
    'ftp://www.opensubtitles.com/x.srt',
    'javascript:alert(1)',
  ])('403 bad-link for off-host / non-https link %s, no upstream fetch', async (link) => {
    const c = await call(file(link))
    expectWorkerError(c, 403, 'bad-link')
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it.each(['image/png', 'video/mp4', ''])(
    '415 bad-link for upstream content type %j',
    async (t) => {
      upstream(() => {
        const r = new Response('PNG')
        if (t) r.headers.set('Content-Type', t)
        else r.headers.delete('Content-Type')
        return r
      })
      const c = await call(file(LINK))
      expectWorkerError(c, 415, 'bad-link')
      expectCors(c.res)
    },
  )

  it('413 too-large when Content-Length exceeds 2 MB', async () => {
    upstream(
      () =>
        new Response('x', {
          headers: {
            'Content-Type': 'text/plain',
            'Content-Length': String(2 * 1024 * 1024 + 1),
          },
        }),
    )
    const c = await call(file(LINK))
    expectWorkerError(c, 413, 'too-large')
    expectCors(c.res)
  })

  it('exactly 2 MB is allowed', async () => {
    upstream(
      () =>
        new Response('x', {
          headers: { 'Content-Type': 'text/plain', 'Content-Length': String(2 * 1024 * 1024) },
        }),
    )
    expect((await call(file(LINK))).res.status).toBe(200)
  })

  function chunked(bytes: number, chunkSize = 256 * 1024): Response {
    let sent = 0
    const stream = new ReadableStream<Uint8Array>({
      pull(ctrl) {
        if (sent >= bytes) return ctrl.close()
        const n = Math.min(chunkSize, bytes - sent)
        sent += n
        ctrl.enqueue(new Uint8Array(n).fill(0x61))
      },
    })
    // No Content-Length: the cap has to be enforced on the stream itself.
    return new Response(stream, { headers: { 'Content-Type': 'text/plain' } })
  }

  async function drain(res: Response): Promise<number> {
    let total = 0
    const reader = res.body!.getReader()
    for (;;) {
      const { done, value } = await reader.read()
      if (done) return total
      total += value.byteLength
    }
  }

  it('a chunked body with no Content-Length is aborted once it passes 2 MB', async () => {
    upstream(() => chunked(3 * 1024 * 1024))
    const res = await worker.fetch(
      new Request(`${W}${file(LINK)}`, { headers: { Origin: ORIGIN, 'cf-connecting-ip': ip } }),
      env,
    )
    expect(res.status).toBe(200)
    expectCors(res)
    expect(res.headers.get('Cache-Control')).toBe('no-store')
    await expect(drain(res)).rejects.toThrow(/too-large/)
  })

  it('a chunked body of exactly 2 MB streams through whole', async () => {
    upstream(() => chunked(2 * 1024 * 1024))
    const res = await worker.fetch(
      new Request(`${W}${file(LINK)}`, { headers: { Origin: ORIGIN, 'cf-connecting-ip': ip } }),
      env,
    )
    expect(await drain(res)).toBe(2 * 1024 * 1024)
  })
})

// ── upstream unreachable ───────────────────────────────────────────────────────────────────

describe('upstream fetch throws → 502 upstream', () => {
  const UPSTREAM_ERR = {
    error: 'upstream',
    sentence: "The subtitle service didn't answer — try again in a moment.",
  }

  it.each([
    ['/api/subtitles?languages=en', 'GET', {}],
    ['/api/login', 'POST', {}],
    ['/api/download', 'POST', { Authorization: 'Bearer eyJ.jwt' }],
    [`/api/subtitle-file?link=${encodeURIComponent(LINK)}`, 'GET', {}],
  ])('%s (%s) → 502 WorkerError with CORS', async (path, method, headers) => {
    upstream(() => {
      throw new TypeError('fetch failed')
    })
    const c = await call(path, { method, headers, body: method === 'POST' ? '{}' : undefined })
    expectWorkerError(c, 502, 'upstream')
    expect(c.body).toEqual(UPSTREAM_ERR)
    expectCors(c.res)
    expect(seen).toHaveLength(1)
  })

  it('TMDB route → 502 WorkerError with CORS, token not echoed', async () => {
    upstream(() => {
      throw new TypeError('fetch failed')
    })
    const c = await call(
      '/api/tmdb/find/tt0041959?external_source=imdb_id',
      {},
      {
        ...env,
        TMDB_READ_TOKEN: TMDB_TOKEN,
      },
    )
    expectWorkerError(c, 502, 'upstream')
    expect(c.body).toEqual(UPSTREAM_ERR)
    expectCors(c.res)
  })

  it('the 502 is not given to a rejected origin', async () => {
    const c = await call('/api/subtitles', { origin: 'https://evil.example' })
    expect(c.res.status).toBe(403)
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

// ── P19: the Authorization gate ────────────────────────────────────────────────────────────

describe('P19 sign-in gate', () => {
  it('POST /api/download without Authorization → 401 sign-in-required, no upstream', async () => {
    const c = await call('/api/download', {
      method: 'POST',
      body: '{"file_id":123}',
      headers: { 'Content-Type': 'application/json' },
    })
    expectWorkerError(c, 401, 'sign-in-required')
    expect(c.body).toEqual(SIGN_IN)
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('GET /api/infos/user without Authorization → 401 sign-in-required, no upstream', async () => {
    const c = await call('/api/infos/user')
    expectWorkerError(c, 401, 'sign-in-required')
    expect(c.body).toEqual(SIGN_IN)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('with Authorization both forward normally', async () => {
    upstream((url) => (url.pathname.endsWith('/download') ? json(downloadOk) : json(loginOk)))
    const auth = { Authorization: 'Bearer eyJ.jwt' }
    const d = await call('/api/download', { method: 'POST', body: '{"file_id":1}', headers: auth })
    const u = await call('/api/infos/user', { headers: auth })
    expect(d.res.status).toBe(200)
    expect(u.res.status).toBe(200)
    expect(seen.map((s) => s.url.pathname)).toEqual(['/api/v1/download', '/api/v1/infos/user'])
    expect(seen.every((s) => s.headers.get('Authorization') === 'Bearer eyJ.jwt')).toBe(true)
    expect(seen[0]!.body).toBe('{"file_id":1}')
  })
})

// ── P20: per-IP soft cap ───────────────────────────────────────────────────────────────────

describe('P20 per-IP rate limit', () => {
  it('the 61st request in a minute from one IP is 429 rate-limited; another IP is fine', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-09-29T12:00:05Z'))
    const one = '198.51.100.61'
    for (let i = 0; i < 60; i++) {
      const c = await call('/api/nope', { ip: one })
      expect(c.res.status).toBe(404)
    }
    const over = await call('/api/nope', { ip: one })
    expectWorkerError(over, 429, 'rate-limited')
    expect(over.body).toEqual({
      error: 'rate-limited',
      sentence: 'Too many requests from your network — try again in a minute.',
      retryAfterSeconds: 60,
    })
    expectCors(over.res)
    expect(over.res.headers.get('Retry-After')).toBe('60')
    // Still limited on real routes, and without spending upstream.
    const blocked = await call('/api/subtitles?languages=en', { ip: one })
    expect(blocked.res.status).toBe(429)
    expect(fetchSpy).not.toHaveBeenCalled()

    const other = await call('/api/nope', { ip: '198.51.100.62' })
    expect(other.res.status).toBe(404)

    // The next minute starts a fresh bucket.
    vi.setSystemTime(new Date('2026-09-29T12:01:05Z'))
    expect((await call('/api/nope', { ip: one })).res.status).toBe(404)
  })

  it('preflights are not counted against the cap', async () => {
    const one = '198.51.100.99'
    for (let i = 0; i < 70; i++) {
      const c = await call('/api/subtitles', { method: 'OPTIONS', ip: one })
      expect(c.res.status).toBe(204)
    }
    expect((await call('/api/nope', { ip: one })).res.status).toBe(404)
  })
})

// ── P21: optional TMDB route ───────────────────────────────────────────────────────────────

describe('P21 TMDB route', () => {
  const path = '/api/tmdb/find/tt0041959?external_source=imdb_id'
  const withToken = (): Env => ({ ...env, TMDB_READ_TOKEN: TMDB_TOKEN })

  it('unset token → 404 not-found, no upstream call', async () => {
    expect(env.TMDB_READ_TOKEN).toBeUndefined()
    const c = await call(path, { headers: { Authorization: `Bearer ${TMDB_TOKEN}` } })
    expectWorkerError(c, 404, 'not-found')
    expectCors(c.res)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('set token → forwards with server-side Bearer, never the client Authorization', async () => {
    upstream(() => json(tmdbFind, 200, { 'Set-Cookie': 'tmdb=1' }))
    const c = await call(
      `${path}&language=en-US`,
      { headers: { Authorization: 'Bearer client-jwt', 'Api-Key': 'client', Cookie: 'a=b' } },
      withToken(),
    )
    expect(c.res.status).toBe(200)
    expect(c.body).toEqual(tmdbFind)
    expectCors(c.res)
    expect(c.res.headers.get('Cache-Control')).toBe('private, max-age=3600')
    expect(c.res.headers.has('Set-Cookie')).toBe(false)
    const s = seen[0]!
    expect(s.url.toString()).toBe(
      'https://api.themoviedb.org/3/find/tt0041959?external_source=imdb_id&language=en-US',
    )
    expect(s.headers.get('Authorization')).toBe(`Bearer ${TMDB_TOKEN}`)
    expect(s.headers.has('Api-Key')).toBe(false) // the OpenSubtitles key never goes to TMDB
    expect(s.headers.has('Cookie')).toBe(false)
    expect(s.headers.get('User-Agent')).toBe('Marquee-Web v1.0.0')
  })

  it('TMDB upstream errors pass through, token still absent from the response', async () => {
    upstream(() => json({ status_message: 'Invalid API key' }, 401))
    const c = await call(path, {}, withToken())
    expect(c.res.status).toBe(401)
  })
})
