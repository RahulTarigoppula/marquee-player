# Marquee — Deployment & Release Runbook

Written 2026-09-06. Binding inputs: `_shared/DECISIONS.md` (D1 Marquee exception — Flutter + media_kit native tier, Vite + TypeScript web tier; **D2** hosting and repo naming; D5 licensing; D9 "day 1 = live"), `GOAL.md` (repo root; §8 platforms, §9 constraints), `docs/RESEARCH.md` (§2 stack, §5.4 the Worker is mandatory, §5.5 the CI pattern, §8 risks), `docs/DESIGN.md` (§14 Android, §16 assets), `docs/TESTING.md` (§9 budgets, §13 day-1 list, §16 what CI runs), `_shared/research/HOSTING.md` §A/§B, `_shared/research/ANDROID-PACKAGING.md` (runner facts, keystore, gotchas). Templates: `_shared/templates/{pages.yml,worker.yml,worker-proxy.ts,android-release.yml,app-build.gradle.snippet}`, script `_shared/scripts/make-keystore.sh`.

Marquee is **four deployables** and this document is the only place their wiring lives:

| # | Deployable | Built by | Lands at |
|---|---|---|---|
| 1 | **Marquee (Windows)** — `marquee.exe` + `libmpv-2.dll` | GitHub Actions `windows-latest` | zip asset on a GitHub Release |
| 2 | **Marquee (Android)** — signed split-per-ABI APKs | GitHub Actions `ubuntu-24.04` | APK assets on the same Release, sideloaded |
| 3 | **Marquee Lite** — the mandatory web tier | GitHub Actions → GitHub Pages | `https://<owner>.github.io/marquee/` |
| 4 | **`marquee-proxy`** — the mandatory Cloudflare Worker | GitHub Actions → `wrangler deploy` | `https://marquee-proxy.<subdomain>.workers.dev` |

The owner's machine has **no Java and no Android SDK**, and never needs them. Flutter SDK + Visual Studio 2022 Build Tools (C++ workload) are installed locally *only* for the Windows dev loop; §3.6 gives a CI-only path for a machine with neither.

Replace `<owner>` with the GitHub username and `<subdomain>` with the `workers.dev` subdomain Cloudflare assigns on first deploy, everywhere below.

---

## 1. Repo layout and what deploys from where

One **public** repo (D2: public is the price of Pages + unlimited Actions minutes), named **`marquee`** — the name DECISIONS §D2 reserves for this project. The Flutter app is at the repo root because `flutter build` expects `pubspec.yaml` there; the other two tiers are subfolders.

```
marquee/
├── GOAL.md                       # the product contract — at the ROOT, not under docs/
├── README.md
├── pubspec.yaml                  # the Flutter app IS the repo root
├── lib/
│   ├── engine/                   # pure Dart, no Flutter imports (D9.2) — hash, filename, scoring,
│   │                             #   opensubtitles, subdl, tickets, timecode, sync_rule, detents,
│   │                             #   threading, bias_light, srt
│   ├── db/                       # drift schema + DAOs
│   ├── theme/tokens.dart         # generated from tokens.css by scripts/tokens.mjs
│   ├── ui/                       # Lobby, Threading, Auditorium, Booth, Ticket Office
│   └── platform/                 # windows/android adapters (window, files, secure storage)
├── assets/fonts/                 # BigShouldersDisplay, Geist, GeistMono, NotoSans-Regular (libass!)
├── assets/shaders/beam.frag
├── android/                      # generated once by `flutter create`, then committed
├── windows/                      # generated once by `flutter create`, then committed
├── integration_test/             # real-libmpv tests (TESTING §6)
├── test/                         # unit, db, widget, goldens, fixtures (TESTING §2)
├── web/                          # Marquee Lite — Vite + TypeScript, its own package.json
│   ├── src/{engine,ui,styles/tokens.css}
│   ├── e2e/                      # Playwright
│   ├── public/{manifest.webmanifest,icons/…}
│   └── vite.config.ts
├── worker/                       # marquee-proxy — Cloudflare Worker
│   ├── src/index.ts
│   ├── test/{worker.test.ts,contract.test.ts,fixtures/}
│   └── wrangler.toml
├── design/{preview.html,cue-sheet.json}
├── scripts/{tokens.mjs,make-fixtures.sh,check-parity.mjs}
├── docs/                         # RESEARCH, DESIGN, ARCHITECTURE, PLAN, TESTING, DEPLOYMENT,
│                                #   IMPLEMENTATION-PROMPT (GOAL.md is at the repo root)
├── tools/libmpv-windows.sha256   # provenance lock for the shipped DLL (TESTING G3)
├── LICENSES/                     # MIT (app) + LGPL notices + OFL font licences
└── .github/workflows/
    ├── ci.yml                    # every push/PR — the gate (§7.1)
    ├── pages.yml                 # web/** → GitHub Pages (§5)
    ├── worker.yml                # worker/** → Cloudflare (§4)
    ├── release.yml               # tag v* → Windows zip + APKs (§7.2)
    └── contract.yml              # nightly live-API shape check (TESTING §7.2)
```

Path triggers keep the four pipelines independent: a CSS tweak in `web/` never rebuilds an APK, and a Dart change never redeploys the Worker.

> **Deviation from DECISIONS §D6 (declared here as D6 requires).** D6's layout assumes a Vite app at the repo root. Marquee inverts it: Flutter at the root, Vite in `web/`. `flutter build` cannot be pointed at a subdirectory without fighting the tool for no benefit, and the web tier is the smaller of the two. Every other D6 idea survives — `engine/` is framework-free and unit-tested first, `platform/` holds the per-OS adapters, `docs/` holds the planning docs, `design/preview.html` is the visual contract.

---

## 2. One-time accounts, keys and tools

Nothing here costs money and nothing asks for a card. **If a step asks for a payment method, stop** (DECISIONS §D9.5) and note it in `docs/RESEARCH.md`.

| # | Thing | Where | Notes |
|---|---|---|---|
| 2.1 | GitHub account + `gh` CLI | already present | `gh auth login` once |
| 2.2 | **OpenSubtitles.com account** (free) | opensubtitles.com → register | The account whose 10–20 downloads/day the app spends. Needed for the day-1 checks in TESTING §13 #5/#17 |
| 2.3 | **OpenSubtitles API consumer key** | Profile → **API Consumers** → New Consumer | Name it `Marquee`, give a real description. This is the `OS_API_KEY` used in three places (§10). Treat as semi-secret: rotate it here if it is ever abused |
| 2.4 | **Cloudflare account** (Free plan) | dash.cloudflare.com | The one place a card could be demanded — TESTING §13 #13. If it is, stop |
| 2.5 | **Cloudflare API token** | My Profile → API Tokens → **"Edit Cloudflare Workers"** template | Becomes the `CLOUDFLARE_API_TOKEN` repo secret |
| 2.6 | **Cloudflare Account ID** | Workers & Pages → right sidebar | Becomes `CLOUDFLARE_ACCOUNT_ID` |
| 2.7 | **TMDB API Read Access Token** (optional) | themoviedb.org → Settings → API | Only for posters. Non-commercial, logo + notice mandatory, cache ≤ 6 months, no ML (RESEARCH §3). Skippable for v1 |
| 2.8 | **Subdl key** (optional) | subdl.com account panel | The user's *own* key, entered in the Ticket Office. Never shipped, never a repo secret |
| 2.9 | Android release keystore | `_shared/scripts/make-keystore.sh` | §8.1. Do this **before** the first tag, not after |
| 2.10 | Local dev (optional) | Flutter SDK (pinned version) + VS 2022 Build Tools "Desktop development with C++" | ~7 GB, free. Only for `flutter run -d windows`. Android stays CI-only forever |

---

## 3. Day 1 — from nothing to live

DECISIONS §D9.1: *Phase 0 ends with "hello world" on GitHub Pages and a debug APK on a Release, before any feature work.* Do these in order; the whole sequence is about half a day, most of it waiting on CI.

### 3.1 Create the repo

```bash
cd C:/Work/Personal_Projects/08-marquee-media-player
git init -b main
gh repo create marquee --public --source=. --remote=origin \
  --description "Drop a film. The lights go down. The subtitles are already there."
```

Commit `docs/`, a `README.md` and a `.gitignore` that excludes at minimum:

```gitignore
# Flutter / Dart
build/
.dart_tool/
.flutter-plugins*
# Generated code (drift / build_runner) is NEVER committed. CI regenerates it with
# `dart run build_runner build --delete-conflicting-outputs` after every `flutter pub get`
# and BEFORE `flutter analyze` — see §7.1 and §7.2.
**/*.g.dart
**/*.drift.dart
# Android — never commit these; the repo is public
android/local.properties
android/key.properties
**/*.p12
**/*.jks
**/*.keystore
# Node
node_modules/
web/dist/
web/playwright-report/
web/test-results/
.wrangler/
# Local secrets
.env
.env.*
!.env.example
```

Add `.gitattributes` so the Gradle wrapper survives Windows checkouts (ANDROID-PACKAGING pitfall 2):

```gitattributes
* text=auto eol=lf
*.bat text eol=crlf
android/gradlew text eol=lf
*.png binary
*.ttf binary
*.mkv binary
*.mp4 binary
*.webm binary
*.avi binary
```

### 3.2 Turn on Pages

Repo **Settings → Pages → Build and deployment → Source: "GitHub Actions"**. Nothing else to click — the workflow creates the `github-pages` environment on its first run.

### 3.3 Add the repo secrets

**Settings → Secrets and variables → Actions → New repository secret.** Full reference in §10; at minimum, on day 1:

| Secret | Value |
|---|---|
| `OS_API_KEY` | the consumer key from §2.3 |
| `CLOUDFLARE_API_TOKEN` | §2.5 |
| `CLOUDFLARE_ACCOUNT_ID` | §2.6 |

The four Android secrets follow in §8.2, and `TMDB_READ_TOKEN` whenever posters land.

### 3.4 Ship the Worker, then Lite, then the APK

1. `worker/` (§4) → `git push` → `worker.yml` runs → note the printed `https://marquee-proxy.<subdomain>.workers.dev`.
2. Put that URL into `pages.yml`'s `VITE_API_BASE` and the Worker's `ALLOWED_ORIGIN` into `wrangler.toml` (they point at each other; both are public values).
3. `web/` (§5) with a landing page that does nothing but print the capability line → push → `pages.yml` → `https://<owner>.github.io/marquee/` is live.
4. `flutter create` the shell (§3.6 if you have no Flutter locally), add the four Android secrets (§8), then tag a pre-release:

```bash
git tag v0.0.1 && git push origin v0.0.1
gh release edit v0.0.1 --prerelease
```

Download the `arm64-v8a` APK on the phone and install it. **Phase 0 is done when the APK opens to a black screen with the word MARQUEE on it and the Pages URL loads on the same phone's browser.**

### 3.5 Run the day-1 verification list

With the real key in hand, work through `docs/TESTING.md` §13 (18 rows) and write every answer into `docs/RESEARCH.md`'s verification log. Two of them gate deployment decisions specifically:

- **#13 Cloudflare without a card** — if a card is demanded, Lite loses OpenSubtitles entirely and becomes a sidecar-only player. That is a scope change to record, not a thing to work around.
- **#14 which Flutter version builds `media_kit` 1.2.6 cleanly** — the answer becomes `FLUTTER_VERSION` in `ci.yml` and `release.yml`, and it does not move again without a deliberate commit.

### 3.6 If Flutter is not installed locally (the CI-only bootstrap)

`android/` and `windows/` are generated once and then committed. If the owner never installs Flutter, generate them in CI with a throwaway `workflow_dispatch` job that runs

```bash
flutter create --platforms=windows,android --org com.rahul --project-name marquee .
```

and uploads the resulting `android/` + `windows/` trees as an artifact; download, commit, delete the job. After that, everything is CI-built forever and the local machine only ever edits Dart, TypeScript and Markdown.

---

## 4. The Cloudflare Worker (`marquee-proxy`) — mandatory

**Why it is not optional.** Probed 2026-09-06 (RESEARCH §5.4 pt 6, verification log #8): `api.opensubtitles.com` returns `Access-Control-Allow-Origin: *` on responses, but a CORS **preflight `OPTIONS` gets HTTP 403 with no `Access-Control-Allow-Headers`** — and the mandatory `Api-Key` header *always* triggers a preflight. A browser therefore cannot call OpenSubtitles at all. The Worker answers the preflight itself, injects the key, and keeps it out of the public bundle (DECISIONS §D2, §D5).

Native builds do **not** use the Worker. They ship the key via `--dart-define` and call the API directly, so the Worker's 100k requests/day is only ever spent by Lite.

### 4.1 `worker/wrangler.toml`

```toml
name = "marquee-proxy"
main = "src/index.ts"
compatibility_date = "2026-09-01"

# Workers Logs OFF. Leaving this on would retain request metadata server-side, which
# contradicts "the Worker logs nothing and stores nothing" (GOAL §9, ARCHITECTURE §9.4/§13,
# IMPLEMENTATION-PROMPT §2.5). Never add [[kv_namespaces]], [[d1_databases]] or
# [[analytics_engine_datasets]] either — TESTING P17 greps this file for all four.
[observability]
enabled = false

[vars]
# Public, non-secret. ALLOWED_ORIGIN is the Pages ORIGIN: scheme + host + port, NO path.
ALLOWED_ORIGIN = "https://<owner>.github.io"
UPSTREAM_BASE  = "https://api.opensubtitles.com/api/v1"
USER_AGENT     = "Marquee-Web v1.0.0"
```

Note `ALLOWED_ORIGIN` has **no** `/marquee/` suffix: an `Origin` header is scheme + host + port only. The sub-path is enforced by nothing, and does not need to be — the key never reaches the browser either way.

### 4.2 The secret

Run once, locally, from `worker/`:

```bash
npx wrangler login          # opens a browser; or set CLOUDFLARE_API_TOKEN in the shell
npx wrangler secret put OS_API_KEY
# paste the consumer key from §2.3; it is write-only from here on

# Optional — only if Lite should show Lobby posters. Without it the Worker's
# /api/tmdb/* route answers 404 {"error":"not-found"} and Lite falls back to frame grabs.
npx wrangler secret put TMDB_READ_TOKEN
```

Secrets are per-Worker and survive redeploys. They are never in git, never in `wrangler.toml`, and never in a `VITE_*` variable (that prefix inlines into the public bundle — HOSTING pitfall 4).

### 4.3 `worker/src/index.ts`

**This listing is byte-identical to IMPLEMENTATION-PROMPT §7.6, which is the normative copy.** They are the same bytes on purpose: this file is what a deployer copies from, and it used to drift. If you change one, change the other in the same commit.

Adapted from `_shared/templates/worker-proxy.ts` with the **seven** Marquee-specific rules settled by IMPLEMENTATION-PROMPT R6 (the superset — this file used to ship a smaller Worker, which could not fetch the `.srt` for Lite and spent OpenSubtitles' shared anonymous pool on the Worker's own IP):

1. a **path allow-list** (everything else is a JSON `404 not-found`);
2. **alphabetical query-param sorting** — the OpenSubtitles gateway 301s unsorted query strings to a canonical URL and *drops* `moviehash_match` on the way (RESEARCH §5.4 pt 6);
3. **`no-store`** on login, logout, download and subtitle-file;
4. **stripping any client-supplied `Api-Key`** (and cookies, and `X-Forwarded-*`);
5. the **`GET /api/subtitle-file?link=`** route — host allow-list (`opensubtitles.com` / `.org`, https only), `text/*`+`application/*` content types, **2 MB cap**, streamed back with CORS;
6. an **`Authorization` gate** on `/api/download` and `/api/infos/user` → `401 {error:'sign-in-required'}` rather than spending the shared anonymous 5/day/IP pool on the Worker's IP;
7. a **per-IP soft cap of 60 requests/minute** (Cache-API counter on `cf-connecting-ip`) → `429 {error:'rate-limited', retryAfterSeconds:60}`.

Plus the optional **`GET /api/tmdb/*`** route (ARCHITECTURE §9.4): a separate upstream, `Authorization: Bearer` built server-side from the `TMDB_READ_TOKEN` secret and never from the client; a `404 not-found` when the secret is unset. Every rule here is asserted by `worker/test/worker.test.ts` (TESTING §7.1 P1–P21).

```ts
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

// Cache-API sliding counter: 60 requests per minute per client IP. No KV, no logging.
async function overRateLimit(req: Request): Promise<boolean> {
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
```

### 4.4 `.github/workflows/worker.yml`

Copy `_shared/templates/worker.yml` and add the test gate — the Worker is the only component that can leak a key, so it never deploys red:

```yaml
name: worker

on:
  push:
    branches: [main]
    paths: ['worker/**', '.github/workflows/worker.yml']
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: worker
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: worker/package-lock.json
      - run: npm ci
        working-directory: worker
      - run: npm test                       # @cloudflare/vitest-pool-workers — TESTING §7.1
        working-directory: worker
      - uses: cloudflare/wrangler-action@v4
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          workingDirectory: worker
```

### 4.5 Verify it after the first deploy

```bash
W=https://marquee-proxy.<subdomain>.workers.dev

# 1. Preflight from the real origin -> 204 with CORS headers
curl -i -X OPTIONS "$W/api/subtitles" \
  -H "Origin: https://<owner>.github.io" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: authorization"

# 2. Wrong origin -> 403, and no Access-Control-Allow-Origin in the response
curl -i -X OPTIONS "$W/api/subtitles" -H "Origin: https://evil.example"

# 3. No Origin at all -> 403 (native builds must not use the proxy)
curl -i "$W/api/subtitles?languages=en&moviehash=8e245d9679d31e12"

# 4. A real search from the real origin -> 200, and grep proves the key is not echoed
curl -s "$W/api/subtitles?languages=en&moviehash=8e245d9679d31e12&moviehash_match=include" \
  -H "Origin: https://<owner>.github.io" | tee /tmp/os.json | head -c 400
grep -c "$OS_API_KEY" /tmp/os.json     # must print 0

# 5. Path outside the allow-list -> 404 {"error":"not-found",...}
curl -i "$W/api/admin" -H "Origin: https://<owner>.github.io"

# 6. Download with no Authorization -> 401 {"error":"sign-in-required",...}
#    (never a silent spend of the shared anonymous 5/day/IP pool on the Worker's IP)
curl -i -X POST "$W/api/download" -H "Origin: https://<owner>.github.io" \
  -H "Content-Type: application/json" -d '{"file_id":123}'

# 7. subtitle-file with an off-host link -> 403 {"error":"bad-link",...}
curl -i "$W/api/subtitle-file?link=https%3A%2F%2Fevil.example%2Fx.srt" \
  -H "Origin: https://<owner>.github.io"

# 8. subtitle-file with a real opensubtitles.com temporary link -> 200 text/plain, <= 2 MB
curl -is "$W/api/subtitle-file?link=<urlencoded temporary link>" \
  -H "Origin: https://<owner>.github.io" | head -20

# 9. TMDB route: 200 when TMDB_READ_TOKEN is set, 404 {"error":"not-found",...} when it is not.
#    Either way the token must not appear in the response.
curl -s "$W/api/tmdb/find/tt0041959?external_source=imdb_id" \
  -H "Origin: https://<owner>.github.io" | head -c 200
```

Free-plan reality (RESEARCH §4): **100,000 requests/day, 10 ms CPU per invocation, 50 subrequests per request**, resetting 00:00 UTC. Exceeding it returns error 1027 — it hard-fails and never bills. A single-user hobby player will not come close; the origin allow-list is what stops someone else spending the quota.

---

## 5. Marquee Lite on GitHub Pages

### 5.1 Vite base path

Lite is served from the sub-path `/marquee/` on Pages and from `/` locally, so `base` is parameterised (HOSTING §A.3):

```ts
// web/vite.config.ts
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  base: process.env.VITE_BASE_PATH ?? '/',
  build: { target: 'es2022', sourcemap: true },
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/*.png'],
      manifest: {
        name: 'Marquee Lite',
        short_name: 'Marquee',
        description: 'Drop a film. The lights go down. The subtitles are already there.',
        theme_color: '#07060A',
        background_color: '#07060A',
        display: 'standalone',
        orientation: 'any',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // The app shell and fonts precache. Never precache media or /api/**.
        globPatterns: ['**/*.{js,css,html,woff2,png,svg,frag}'],
        navigateFallback: 'index.html',
        runtimeCaching: [{ urlPattern: /\/api\//, handler: 'NetworkOnly' }],
      },
    }),
  ],
})
```

`vite-plugin-pwa` derives `scope` and `start_url` from `base`, so both become `/marquee/` automatically. Two rules that bite on sub-path hosting (HOSTING pitfalls 2 and 3): never `fetch('/data.json')` — always `import.meta.env.BASE_URL + 'data.json'` — and test with `npm run build && npx vite preview --base /marquee/` before pushing.

### 5.2 How Lite finds the Worker

The Worker URL is **public config, not a secret** (the secret is inside the Worker). It arrives as a build-time env var with a dev fallback:

```ts
// web/src/config.ts
export const API_BASE: string =
  import.meta.env.VITE_API_BASE ?? 'http://127.0.0.1:8787/api'   // `npx wrangler dev` in worker/
```

`VITE_API_BASE` is set in `pages.yml` (§5.3). **Nothing with the `VITE_` prefix may ever hold the OpenSubtitles key** — that prefix is inlined verbatim into the shipped bundle, and `ci.yml` greps `web/dist/**` for it on every run (TESTING G5).

### 5.3 `.github/workflows/pages.yml`

`_shared/templates/pages.yml` adapted for the `web/` subdirectory:

```yaml
# Prereq: Settings -> Pages -> Source = "GitHub Actions" (§3.2)
name: pages

on:
  push:
    branches: [main]
    paths: ['web/**', 'design/**', '.github/workflows/pages.yml']
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false      # never cancel an in-flight production deploy

jobs:
  build:
    runs-on: ubuntu-24.04
    defaults:
      run:
        working-directory: web
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: web/package-lock.json
      - run: npm ci
      - run: npm test -- --run                 # a broken Lite never reaches the live URL
      - name: Build Marquee Lite (served from /marquee/)
        run: npm run build
        env:
          VITE_BASE_PATH: /${{ github.event.repository.name }}/
          # Public config only. The API key lives in the Worker (§4.2).
          VITE_API_BASE: https://marquee-proxy.<subdomain>.workers.dev/api
          VITE_APP_VERSION: ${{ github.sha }}
      - name: SPA fallback for deep links
        run: cp dist/index.html dist/404.html
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v4
        with:
          path: web/dist                        # relative to the workspace, not working-directory

  deploy:
    needs: build
    runs-on: ubuntu-24.04
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

### 5.4 First deploy and the URL

Push to `main`. The first run takes 1–2 minutes; the URL appears on the workflow summary and under Settings → Pages:

**`https://<owner>.github.io/marquee/`**

Then check the sub-path plumbing:

```bash
U=https://<owner>.github.io/marquee
curl -sI $U/                       # 200
curl -sI $U/manifest.webmanifest   # 200, application/manifest+json
curl -sI $U/sw.js                  # 200, javascript
curl -s  $U/ | grep -o 'src="[^"]*"' | head   # every asset path starts with /marquee/
```

That last check is TESTING §13 #18. A 404 on `sw.js` or an asset path missing `/marquee/` means `VITE_BASE_PATH` did not reach the build.

### 5.5 What Pages cannot do for us

- **No custom headers**, so no `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`, so no `SharedArrayBuffer` — **JASSUB runs single-threaded** on the deployed site. It falls back automatically; the app must not attempt the threaded path (TESTING §8.3). The escape hatch if ASS rendering ever proves too slow is Cloudflare **Workers with static assets** (free, unlimited static requests, `_headers` supported) — DECISIONS §D2. That is a hosting move, not a code rewrite: same `dist/`, same Worker account.
- **Deep links return HTTP 404 even when they render.** Harmless for Lite, which is one screen; the `404.html` copy makes them boot anyway.
- **1 GB site / 100 GB-month soft limits.** Lite ships no media, so the only weight is JASSUB's WASM — keep it a lazy chunk (TESTING N13).

---

## 6. PWA install check

Do this once after the first Pages deploy, and again before every tag (TESTING §15 W-W1..W-W3).

**Desktop (Chrome/Edge on the owner's PC)**
1. Open `https://<owner>.github.io/marquee/`.
2. DevTools → Application → Manifest: name "Marquee Lite", `start_url` **and** `scope` both `/marquee/`, theme `#07060A`, three icons resolving (192, 512, maskable 512).
3. Application → Service workers: one registered worker, scope `/marquee/`, status "activated and is running".
4. The install icon appears in the address bar. Install it; it must open at the Lite landing, not at `/`.
5. Application → Service workers → tick **Offline**, reload: the shell renders and the previously fetched subtitle is still there (TESTING X11). A browser error page is a failure.
6. Push a trivial change, wait for `pages.yml`, relaunch the installed app: it picks up the new build (`registerType: 'autoUpdate'`). A permanently stale shell is a failure.

**Android (Chrome)**
7. Open the same URL, ⋮ → **Install app** (or "Add to Home screen" with the app icon, not the shortcut icon).
8. Launch from the home screen: standalone, no browser chrome, status bar tinted `#07060A`.
9. Aeroplane mode → relaunch → the shell loads.

If the install prompt never appears, it is almost always `scope`/`start_url` disagreeing with the served path, or the service worker registering at `/` instead of `/marquee/` (register with `import.meta.env.BASE_URL + 'sw.js'`).

---

## 7. CI and the native release pipeline

Both workflows pin one Flutter version. `media_kit`'s changelog names no Flutter version and the "3.38" attribution in RESEARCH is unverified (verification log, last row), so the pin is whatever TESTING §13 #14 proves builds cleanly, and it moves only in a deliberate commit.

### 7.1 `.github/workflows/ci.yml` — the gate on every push

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: '3.47.0'      # pinned — TESTING §13 #14

jobs:
  dart:
    name: analyze + dart tests + goldens
    runs-on: ubuntu-24.04        # goldens are generated on Linux only (TESTING §5)
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs   # drift: *.g.dart is gitignored
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - name: Coverage gates (TESTING §12)
        run: dart run tool/check_coverage.dart coverage/lcov.info
      - uses: actions/upload-artifact@v7
        if: failure()
        with: { name: golden-failures, path: test/**/failures/, retention-days: 7 }

  web:
    name: vitest + size-limit
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: web } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: web/package-lock.json }
      - run: npm ci
      - run: npx biome ci .
      - run: npm test -- --run --coverage
      - run: npm run build
        env: { VITE_BASE_PATH: /marquee/, VITE_API_BASE: https://marquee-proxy.<subdomain>.workers.dev/api }
      - run: npx size-limit          # TESTING N12/N13

  worker:
    name: worker tests
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: worker } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: worker/package-lock.json }
      - run: npm ci
      - run: npm test                # TESTING §7.1 P1-P21

  e2e:
    name: playwright
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: web } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: web/package-lock.json }
      - run: npm ci
      - run: npx playwright install --with-deps chromium firefox chrome
      - run: npx playwright test
      - uses: actions/upload-artifact@v7
        if: always()
        with: { name: playwright-report, path: web/playwright-report/, retention-days: 7 }

  checks:
    name: fixtures, tokens, licences, secrets
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }
      - uses: actions/setup-node@v7
        with: { node-version: 22 }
      - name: Media fixtures are bit-exact (TESTING §12)
        run: bash scripts/make-fixtures.sh && git diff --exit-code test/fixtures
      - name: Design tokens in sync (TESTING G9)
        run: node scripts/tokens.mjs && git diff --exit-code web/src/styles/tokens.css lib/theme/tokens.dart
      - name: Engine test parity between Dart and TS
        run: node scripts/check-parity.mjs
      - name: Licence allow-list (TESTING G1)
        run: flutter pub get && dart run build_runner build --delete-conflicting-outputs && dart run tool/check_licences.dart
      - name: No secrets, no telemetry (TESTING G5/G6)
        run: bash tool/check_no_secrets.sh
```

### 7.2 `.github/workflows/release.yml` — the Flutter matrix

One workflow produces both native artifacts: **Windows x64 exe on `windows-latest`** and **signed split-per-ABI APKs on `ubuntu-24.04`**, then publishes them to a GitHub Release. The pattern mirrors Mangayomi's verified `release.yml` (RESEARCH §5.5, §6) with the size and signature gates from TESTING §9 and §11 added. The `test` job is the Windows integration suite (TESTING §6); the weekly cron runs that job alone.

```yaml
name: release

on:
  push:
    tags: ['v*']
  schedule:
    - cron: '0 4 * * 1'          # Mondays 04:00 UTC — integration tests only
  workflow_dispatch:             # manual run: artifacts only, no Release

permissions:
  contents: write                # softprops/action-gh-release needs this

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false      # never cancel a half-published release

env:
  FLUTTER_VERSION: '3.47.0'

jobs:
  # ---------------------------------------------------------------- integration
  test:
    name: integration (real libmpv, windows)
    runs-on: windows-latest      # VS 2022 + C++ workload preinstalled
    timeout-minutes: 25
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }
      - run: flutter --version
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs   # drift: *.g.dart is gitignored
      - run: flutter analyze --fatal-infos
      - name: Unit + widget tests (goldens are Linux-only)
        run: flutter test --exclude-tags golden
      - name: Integration tests against the committed fixtures
        run: flutter test integration_test -d windows

  # ---------------------------------------------------------------- build matrix
  build:
    name: ${{ matrix.label }}
    needs: test
    if: github.event_name != 'schedule'
    runs-on: ${{ matrix.os }}
    timeout-minutes: 25          # TESTING N17: tag -> artifacts in under 25 min
    strategy:
      fail-fast: false
      matrix:
        include:
          - label: windows-x64
            os: windows-latest
            target: windows
          - label: android-apks
            os: ubuntu-24.04     # Android SDK 34-37, build-tools, JDK 8-25 preinstalled
            target: android
    steps:
      - uses: actions/checkout@v7

      - name: Derive version
        id: v
        shell: bash
        run: |
          set -euo pipefail
          RAW='${{ github.ref_type == 'tag' && github.ref_name || format('v0.0.{0}', github.run_number) }}'
          echo "name=${RAW#v}"            >> "$GITHUB_OUTPUT"
          echo "code=${{ github.run_number }}" >> "$GITHUB_OUTPUT"

      - uses: actions/setup-java@v6
        if: matrix.target == 'android'
        with:
          distribution: temurin
          java-version: '17'     # the version RESEARCH §5.5 verified for this Flutter+AGP pair
          cache: gradle

      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }

      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs   # drift: *.g.dart is gitignored

      # ------------------------------------------------------------- Windows
      - name: Build Windows release
        if: matrix.target == 'windows'
        run: >
          flutter build windows --release
          --build-name=${{ steps.v.outputs.name }}
          --build-number=${{ steps.v.outputs.code }}
          --dart-define=OS_API_KEY=${{ secrets.OS_API_KEY }}
          --dart-define=TMDB_READ_TOKEN=${{ secrets.TMDB_READ_TOKEN }}
          --dart-define=MARQUEE_VERSION=${{ steps.v.outputs.name }}

      - name: Zip, gate on size, checksum
        if: matrix.target == 'windows'
        shell: pwsh
        run: |
          $src = 'build/windows/x64/runner/Release'
          # media_kit_libs_windows_video copies the DLL here; a build without it runs nowhere.
          foreach ($dll in 'libmpv-2.dll','flutter_windows.dll','msvcp140.dll','vcruntime140.dll') {
            if (-not (Test-Path "$src/$dll")) { throw "$dll missing from the build output" }
          }
          New-Item -ItemType Directory -Force out | Out-Null
          $zip = "out/marquee-${{ steps.v.outputs.name }}-windows-x64.zip"
          Compress-Archive -Path "$src/*" -DestinationPath $zip
          $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
          Write-Host "Windows zip: $mb MB"
          if ($mb -gt 60) { throw "Windows zip is $mb MB; budget is 60 MB (TESTING N9)" }
          Get-FileHash $zip -Algorithm SHA256 |
            ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $_.Path -Leaf)" } |
            Out-File -Encoding ascii out/SHA256SUMS-windows.txt

      # ------------------------------------------------------------- Android
      - name: Decode keystore
        if: matrix.target == 'android'
        env:
          KS_B64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          test -n "$KS_B64" || { echo "::error::ANDROID_KEYSTORE_BASE64 is empty"; exit 1; }
          printf '%s' "$KS_B64" | base64 -d > "$RUNNER_TEMP/release.p12"

      - name: Build signed split-per-ABI APKs
        if: matrix.target == 'android'
        env:
          ANDROID_KEYSTORE_FILE: ${{ runner.temp }}/release.p12
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: >
          flutter build apk --release --split-per-abi
          --build-name=${{ steps.v.outputs.name }}
          --build-number=${{ steps.v.outputs.code }}
          --dart-define=OS_API_KEY=${{ secrets.OS_API_KEY }}
          --dart-define=TMDB_READ_TOKEN=${{ secrets.TMDB_READ_TOKEN }}
          --dart-define=MARQUEE_VERSION=${{ steps.v.outputs.name }}

      - name: Verify signing, gate on size, rename, checksum
        if: matrix.target == 'android'
        run: |
          set -euo pipefail
          mkdir -p out
          APKSIGNER=$(ls "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
          for abi in arm64-v8a armeabi-v7a x86_64; do
            src="build/app/outputs/flutter-apk/app-$abi-release.apk"
            test -f "$src" || { echo "::error::$src was not built"; exit 1; }
            # A debug-signed APK cannot update a release install: fail loudly, not silently.
            "$APKSIGNER" verify --print-certs "$src" | grep -q 'Signer #1 certificate DN' \
              || { echo "::error::$abi APK is not signed with the release key"; exit 1; }
            "$APKSIGNER" verify --print-certs "$src" | grep -qi 'CN=Android Debug' \
              && { echo "::error::$abi APK is DEBUG-signed"; exit 1; }
            cp "$src" "out/marquee-${{ steps.v.outputs.name }}-$abi.apk"
          done
          # No universal APK — libmpv is ~30-40 MB per ABI (TESTING N11)
          test ! -f build/app/outputs/flutter-apk/app-release.apk
          sz=$(stat -c%s "out/marquee-${{ steps.v.outputs.name }}-arm64-v8a.apk")
          echo "arm64-v8a APK: $((sz / 1024 / 1024)) MB"
          test "$sz" -le $((55 * 1024 * 1024)) \
            || { echo "::error::arm64 APK exceeds the 55 MB budget (TESTING N10)"; exit 1; }
          (cd out && sha256sum *.apk > SHA256SUMS-android.txt)
          ls -la out

      - uses: actions/upload-artifact@v7
        with:
          name: marquee-${{ matrix.label }}-${{ steps.v.outputs.name }}
          path: out/
          retention-days: 14

  # ---------------------------------------------------------------- publish
  publish:
    needs: build
    if: github.ref_type == 'tag'
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/download-artifact@v7
        with: { path: dist, merge-multiple: true }
      - run: ls -la dist
      - uses: softprops/action-gh-release@v3
        with:
          tag_name: ${{ github.ref_name }}
          generate_release_notes: true
          fail_on_unmatched_files: true
          body: |
            **Windows:** download `marquee-*-windows-x64.zip`, extract anywhere, run `marquee.exe`.
            The exe is unsigned, so Windows SmartScreen will say "Windows protected your PC" —
            More info → Run anyway. Nothing is installed and nothing writes outside the folder
            except the app's own data directory.

            **Android:** download `marquee-*-arm64-v8a.apk` on the phone (that is the right one for
            every phone made since ~2019; `armeabi-v7a` for older, `x86_64` for emulators). Allow
            "install unknown apps" once. It installs over the previous version.

            Subtitles by OpenSubtitles.com. Playback by libmpv / FFmpeg / libass (LGPL — see
            the Ticket Office for notices and source links). Verify downloads against `SHA256SUMS-*.txt`.
          files: |
            dist/*.zip
            dist/*.apk
            dist/SHA256SUMS-*.txt
```

**Why a matrix rather than two hand-written jobs:** the checkout, the version derivation, the Flutter pin and the `--dart-define` set are identical on both platforms and must stay identical — a matrix makes drift between them impossible. The platform-specific halves are guarded with `if: matrix.target == …` rather than duplicated.

---

## 8. Android: keystore, secrets, Gradle and manifest before the first build

Do all of §8 **before** the first `v*` tag. An unsigned or debug-signed first release can never be updated in place.

### 8.1 Generate the keystore (no Java needed)

In **Git Bash**, in a folder **outside** the repo:

```bash
bash C:/Work/Personal_Projects/_shared/scripts/make-keystore.sh marquee
```

It runs `openssl req` + `openssl pkcs12 -export` (Git for Windows ships OpenSSL) and produces `marquee-release.p12` and `marquee-release.p12.b64`. PKCS12 requires the key password to equal the store password — the script enforces that.

> **Back up `marquee-release.p12` and the passphrase now** (password manager + one offline copy). Losing them means every future APK must be installed after an uninstall, taking the user's library, resume positions and sync offsets with it. GitHub cannot show a secret back to you. See §11.4.

### 8.2 The four repository secrets

Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the entire contents of `marquee-release.p12.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the passphrase |
| `ANDROID_KEY_ALIAS` | `release` |
| `ANDROID_KEY_PASSWORD` | the same passphrase (PKCS12 rule) |

### 8.3 `android/app/build.gradle.kts`

`_shared/templates/app-build.gradle.snippet` is written for Capacitor's Groovy file; this is the same idea translated to the Kotlin DSL that `flutter create` generates. **Merge these blocks** into the generated file — do not replace it.

```kotlin
import java.io.File
import java.util.Properties

// Present only in CI; a local build without it still works and signs with the debug key.
val ksFile: String? = System.getenv("ANDROID_KEYSTORE_FILE")

android {
    namespace = "com.rahul.marquee"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        // NEVER changes after the first install — it is the identity of every future update.
        applicationId = "com.rahul.marquee"
        minSdk = 26                 // Android 8.0+, GOAL §8
        targetSdk = 36
        versionCode = flutter.versionCode   // from --build-number
        versionName = flutter.versionName   // from --build-name
    }

    signingConfigs {
        create("release") {
            if (ksFile != null) {
                storeFile = File(ksFile)
                storeType = "PKCS12"
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Keep R8 off: media_kit reaches libmpv through JNI and reflection, and a stripped
            // build fails at runtime rather than at build time. Size is controlled by ABI splits.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig =
                if (ksFile != null) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }

    packaging {
        // libmpv/ffmpeg .so files must stay page-aligned and uncompressed.
        jniLibs { useLegacyPackaging = false }
    }
}
```

`--split-per-abi` on the Flutter command line is what produces the three APKs; do **not** also add a `splits { abi { … } }` block — the two mechanisms fight.

### 8.4 `android/app/src/main/AndroidManifest.xml`

Only what Marquee actually needs. Everything absent from this list is absent on purpose (GOAL §9 privacy): no camera, no location, no notifications, no exact alarms, no `MANAGE_EXTERNAL_STORAGE`, no network-state snooping.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <!-- keep-screen-on during playback (wakelock_plus) -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <!-- MediaStore library scan. SAF ("Open with", file picker) needs none of these. -->
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
    <!-- No READ_MEDIA_AUDIO: Marquee is a video player with no audio-library feature.
         PLAN 4.1, DESIGN §14 and TESTING M-F3 all list the video permission only. If an
         "external audio track" feature ever lands, add it back here WITH the feature named,
         and add the matching row to TESTING §14. -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
                     android:maxSdkVersion="32" />

    <application
        android:label="Marquee"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:enableOnBackInvokedCallback="true">   <!-- predictive back, DESIGN §14 -->

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:supportsPictureInPicture="true"
            android:resizeableActivity="true"
            android:hardwareAccelerated="true"
            android:theme="@style/LaunchTheme"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden|density|uiMode|locale|layoutDirection|fontScale|navigation|keyboard">

            <meta-data android:name="io.flutter.embedding.android.NormalTheme"
                       android:resource="@style/NormalTheme" />

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <!-- "Open with" from Files, a browser download, or any file manager -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="content" />
                <data android:scheme="file" />
                <data android:mimeType="video/*" />
            </intent-filter>

            <!-- Share sheet -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>
        </activity>

        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
```

`configChanges` must list `orientation|screenSize|smallestScreenSize|screenLayout` or Android recreates the Activity on rotation and libmpv restarts mid-film (DESIGN §14; TESTING §14 M-G8). `supportsPictureInPicture` + `resizeableActivity` are what make M-N1 possible. `enableOnBackInvokedCallback="true"` opts in to predictive back, which the Booth sheet and Threading screen must handle (M-G7).

### 8.5 `pubspec.yaml` — what must be there before the first Android build

```yaml
name: marquee
description: Drop a film. The lights go down. The subtitles are already there.
publish_to: none
version: 1.0.0+1                 # CI overrides both halves; this is the local default

environment:
  sdk: ^3.9.0
  flutter: '>=3.47.0'

dependencies:
  flutter: { sdk: flutter }

  # ── playback (libmpv = ffmpeg + libass; MIT wrapper over LGPL natives) ──
  media_kit: ^1.2.6
  media_kit_video: ^2.0.1        # texture-backed video widget
  media_kit_libs_video: ^1.0.7   # pulls the LGPL `default` native builds — NEVER encoders-gpl

  # ── state ──
  flutter_riverpod: ^3.0.0       # threadingProvider / houseProvider — the whole state layer

  # ── database ──
  drift: ^2.34.4                 # code-generated: `dart run build_runner build …`
  drift_flutter: ^0.2.0          # the Flutter-side connection helper
  sqlite3_flutter_libs: ^0.5.0

  # ── platform ──
  path_provider: ^2.1.0          # %LOCALAPPDATA%\Marquee — drift DB, mpv.log, subtitle fallback
  file_picker: ^8.0.0            # SAF on Android, native dialog on Windows
  flutter_secure_storage: ^9.2.0 # the OpenSubtitles JWT only, never the password
  wakelock_plus: ^1.2.0
  screen_brightness: ^2.0.0      # per-app override, restored on exit
  window_manager: ^0.5.2         # frameless Windows window (MIT)
  flutter_acrylic: ^1.1.4        # Mica in the Lobby only

  # ── presentation ──
  flutter_animate: ^4.5.2
  flutter_svg: ^2.0.0            # the Lucide SVG subset in assets/icons/
  flutter_soloud: ^3.0.0         # room tone + synthesised sweep / 2-pop / detent
  material_color_utilities: ^0.11.0   # bias light — NOT palette_generator (discontinued)

  # ── plumbing ──
  http: ^1.2.0
  clock: ^1.1.1                  # injectable clock, TESTING determinism rules

dev_dependencies:
  flutter_test: { sdk: flutter }
  integration_test: { sdk: flutter }
  drift_dev: ^2.34.0
  build_runner: ^2.4.0
  flutter_lints: ^5.0.0
  flutter_native_splash: ^2.4.0
  flutter_launcher_icons: ^0.14.0

flutter:
  uses-material-design: false    # no Material icon font is shipped; icons are Lucide SVGs
  assets:
    - assets/shaders/
    - assets/icons/              # Lucide SVG subset (ISC), read by flutter_svg
    - assets/sounds/             # projector-loop.ogg, ticket-tear.ogg (CC0)
    - design/cue-sheet.json      # the ONE keyboard cue sheet: `?` overlay + README (TESTING I11)
  shaders:
    - assets/shaders/beam.frag
    - assets/shaders/grain.frag
  fonts:
    - family: Big Shoulders Display
      fonts: [{ asset: assets/fonts/BigShouldersDisplay-Variable.ttf }]
    - family: Geist
      fonts: [{ asset: assets/fonts/Geist-Variable.ttf }]
    - family: Geist Mono
      fonts: [{ asset: assets/fonts/GeistMono-Variable.ttf }]
    - family: Noto Sans
      fonts:
        - { asset: assets/fonts/NotoSans-Regular.ttf }
        - { asset: assets/fonts/NotoSans-Bold.ttf, weight: 700 }
```

**Every dependency above is load-bearing.** `flutter_riverpod` is the entire state layer (ARCHITECTURE §1.1/§7.1, IMPLEMENTATION-PROMPT §2.2: `threadingProvider`, `houseProvider`); `drift_flutter` is the connection helper drift needs on device; `flutter_svg` renders the Lucide subset in `assets/icons/`; `flutter_soloud` plays the room tone and the synthesised sweep / 2-pop / detent; `path_provider` is how the app finds `%LOCALAPPDATA%\Marquee` for the drift DB, `mpv.log` and the app-storage subtitle fallback. This list is the same one `README.md` §2 installs — if you change one, change both.

**The `assets:` block must list all four entries.** `assets/icons/` and `assets/sounds/` are not bundled unless they are declared, and `design/cue-sheet.json` lives outside `assets/` entirely — without that line the runtime `?` overlay has nothing to read (TESTING I11 makes the cue sheet a build-failing single source of truth; PLAN 2.16 names the same path).

**drift is code-generated.** `dart run build_runner build --delete-conflicting-outputs` writes `lib/db/database.g.dart`; `*.g.dart` is gitignored (§3.1) and regenerated by CI after every `flutter pub get` and before `flutter analyze`.

**`assets/fonts/NotoSans-Regular.ttf` is load-bearing, not decorative.** On Android `media_kit` sets `sub-font-provider=none`, so libass can only use fonts the app ships. `PlayerConfiguration(libass: true, libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf', libassAndroidFontName: 'Noto Sans')` — and `libassAndroidFontName` must be the TTF's **internal family name**, not the filename. Get it wrong and subtitles are invisible on Android while working perfectly on Windows (RESEARCH §5.3, §8; media_kit issue #945).

`flutter_native_splash` config (background `#07060A`, one 72 dp bulb) and `flutter_launcher_icons` config (adaptive foreground/background/monochrome per DESIGN §14) go in the same file or their own YAML; both are generated once and committed.

### 8.6 First release and install

```bash
git tag v1.0.0 && git push origin v1.0.0
```

On the phone: open the repo's Releases page in Chrome, tap `marquee-1.0.0-arm64-v8a.apk`, tap Open; Android asks once to allow Chrome to "install unknown apps"; allow, install. Updates are the same flow with a higher tag — same key, higher `versionCode` (from `github.run_number`), installs over the top.

**Developer verification (ANDROID-PACKAGING).** Google's rollout begins 2026-09-30 regionally and goes global in 2027. Sideloading keeps working, but register the **free limited-distribution account** (no ID, up to 20 devices) as insurance before the region flips. Marquee is not a Play project — no fees, no policies, no review.

---

## 9. Windows build specifics

- **The zip is the product.** No installer in v1; `inno_bundle` is a "someday" line (GOAL §7). Extract anywhere and run `marquee.exe`.
- **What must be inside the zip:** `marquee.exe`, `flutter_windows.dll`, **`libmpv-2.dll`** (copied in by `media_kit_libs_windows_video`), the `data/` folder, and the MSVC runtime DLLs Flutter bundles (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`). The workflow asserts the first four exist before zipping — a build missing `libmpv-2.dll` starts and then plays nothing.
- **DLL provenance is a licence matter, not a detail.** The shipped DLL comes from `media-kit/libmpv-win32-video-cmake` release `20241021`, built `--disable-gpl --disable-nonfree --enable-version3` + `-Dgpl=false`, i.e. **LGPL** — which is why Marquee can be MIT. `tools/libmpv-windows.sha256` pins its hash and `ci.yml` checks it (TESTING G3). If the refresh idea in GOAL §7 is ever acted on, the replacement must be zhongfly's **`mpv-dev-lgpl-x86_64-*`** package; the plain package is a GPL build and would relicense the app.
- **The exe is unsigned.** SmartScreen shows "Windows protected your PC" on first run. Code-signing certificates cost money, so this is permanent and the README says so **before** a user meets it (TESTING §15 W-I2). Publishing the SHA-256 alongside the zip is the mitigation we can afford.
- **Frameless window.** `window_manager` + `flutter_acrylic`: Mica in the Lobby, opaque black during playback (DESIGN §16 verification list). Window size and position persist.
- **File associations** are a "someday" item that needs the installer; for now `marquee.exe "<path>"` works from the command line and from a manually created "Open with" entry.

---

## 10. Configuration and secrets reference

Every value in the project, in one table. The rule that governs all of it: **anything that reaches the browser bundle is public**; secrets live in the Worker or in the runner's memory during a build.

| Name | Kind | Set where | Consumed by | Notes |
|---|---|---|---|---|
| `OS_API_KEY` | secret | GitHub repo secret **and** `wrangler secret put` | `release.yml` → `--dart-define` (native); the Worker (Lite) | The same consumer key in two places by necessity. Semi-secret in native builds — standard practice (Kodi's official addon does it), rotate at opensubtitles.com if abused (RESEARCH §8) |
| `TMDB_READ_TOKEN` | secret, optional | GitHub repo secret | `release.yml` → `--dart-define` | Posters only. A user's own BYO key in the Ticket Office is the alternative |
| `ANDROID_KEYSTORE_BASE64` | secret | GitHub repo secret | `release.yml` android leg | §8.2 |
| `ANDROID_KEYSTORE_PASSWORD` | secret | GitHub repo secret | " | " |
| `ANDROID_KEY_ALIAS` | secret | GitHub repo secret | " | `release` |
| `ANDROID_KEY_PASSWORD` | secret | GitHub repo secret | " | equals the store password (PKCS12) |
| `CLOUDFLARE_API_TOKEN` | secret | GitHub repo secret | `worker.yml` | "Edit Cloudflare Workers" template |
| `CLOUDFLARE_ACCOUNT_ID` | secret | GitHub repo secret | `worker.yml` | not really secret, but keep it out of the tree |
| `ALLOWED_ORIGIN` | public var | `worker/wrangler.toml` `[vars]` | Worker | `https://<owner>.github.io` — no path |
| `UPSTREAM_BASE` | public var | `worker/wrangler.toml` `[vars]` | Worker | `https://api.opensubtitles.com/api/v1` |
| `USER_AGENT` | public var | `worker/wrangler.toml` `[vars]` | Worker | `Marquee-Web v1.0.0` — OpenSubtitles requires a descriptive UA |
| `VITE_BASE_PATH` | public build var | `pages.yml` | `web/vite.config.ts` | `/marquee/` on Pages, `/` locally |
| `VITE_API_BASE` | public build var | `pages.yml` | `web/src/config.ts` | the Worker URL + `/api` |
| `VITE_APP_VERSION` | public build var | `pages.yml` | About line | `github.sha` |
| `MARQUEE_VERSION` | build define | `release.yml` | About line, `User-Agent` | the tag without `v` |
| Subdl key | user data | Ticket Office UI → secure storage | the app | the **user's** key; never a repo secret, never shipped |
| OpenSubtitles JWT | user data | login response → `flutter_secure_storage` / WebCrypto AES-GCM | the app | the password is never stored (TESTING O14) |

**Never do these:** put the key in a `VITE_*` variable; commit `android/key.properties`, `android/local.properties`, or any `.p12`/`.jks`; echo a secret into a workflow log; add a secret to `wrangler.toml`. `ci.yml`'s `checks` job greps for the first three (TESTING G5).

---

## 11. Versioning, releasing, rolling back, backing up

### 11.1 Versioning

- **SemVer**, one tag per release: `v1.0.0`, `v1.0.1`, `v1.1.0`.
- `pubspec.yaml` carries `1.0.0+1` as the local default; CI overrides both halves — `--build-name` from the tag (minus the `v`), `--build-number` from `github.run_number`. That guarantees `versionCode` **always increases**, including on a re-run of a failed job (a harmless gap in the sequence).
- Marquee Lite has no version of its own; it ships `github.sha` in its About line. It deploys continuously from `main` and is never tagged.
- The Worker likewise deploys from `main`. Cloudflare keeps its own deployment history for rollback.
- `applicationId` (**`com.rahul.marquee`** — the portfolio convention `com.rahul.<repo>`, produced directly by `flutter create --org com.rahul`) and the signing key are permanent. Neither ever changes.

### 11.2 Release checklist

The full gate is `docs/TESTING.md` §17. Condensed:

1. `ci.yml` green on `main`; golden diffs reviewed as images, not accepted blind.
2. `contract.yml` green (or its auto-filed issue triaged) within the last 24 h.
3. Every row of TESTING §13 has an answer or a written mitigation in RESEARCH's verification log.
4. Bump `pubspec.yaml`'s version, update `CHANGELOG.md`, push to `main`, wait for green.
5. `git tag v1.2.3 && git push origin v1.2.3`.
6. Watch `release.yml`: `test` → `build` (both legs) → `publish`. Under 25 minutes (TESTING N17) or the job's own timeout fails it.
7. Download the Release's **own** artifacts and walk TESTING §14 (Android, installing over the previous version) and §15 (Windows + the browser matrix against the live Pages URL).
8. If either checklist fails, mark the Release as a pre-release immediately (`gh release edit v1.2.3 --prerelease`) and fix forward.

### 11.3 Rollback

| Broken thing | How to roll back | Caveat |
|---|---|---|
| **Marquee Lite (Pages)** | `git revert <sha> && git push` — `pages.yml` redeploys the previous build in ~2 min | Re-running an old workflow run also works while its artifact has not expired, but a revert is the honest record |
| **Worker** | `npx wrangler deployments list` then `npx wrangler rollback [<deployment-id>]` from `worker/`; instant, no build | Secrets are not part of a deployment, so a rollback never loses `OS_API_KEY` |
| **A bad Release** | `gh release edit v1.2.3 --prerelease` (hides it from "Latest"), or `gh release delete-asset` for one bad artifact. Then tag `v1.2.4` with the fix | **Users cannot downgrade an APK** — a lower `versionCode` refuses to install over a higher one. Rolling back Android means shipping a *forward* fix, or telling the user to uninstall (which loses their library unless they exported it). This is why §11.2 step 7 exists |
| **A bad Windows zip** | Delete the asset; the previous Release's zip is still downloadable | The app is portable, so the user just re-extracts the old folder |
| **A leaked `OS_API_KEY`** | Revoke at opensubtitles.com → API Consumers, create a new one, update the repo secret **and** `wrangler secret put OS_API_KEY`, redeploy the Worker, tag a patch release for native | Native builds already in the wild keep the old key until they update — another reason to rotate rather than panic |
| **A leaked keystore** | There is no rollback. A new key means a new `applicationId` and a clean install for the user | Which is why §11.4 is not optional |

### 11.4 Backups

| What | Where it must live | Why |
|---|---|---|
| `marquee-release.p12` **and its passphrase** | password manager **and** one offline copy (USB / encrypted archive) | Losing it ends the update path for every installed APK. Nothing else in this project is unrecoverable |
| OpenSubtitles consumer key + account credentials | password manager | Recoverable (regenerate), but a regeneration means a Worker secret update and a native patch release |
| Cloudflare API token + Account ID | password manager | Token is regenerable in one click |
| TMDB read token | password manager | Regenerable |
| `docs/`, `design/`, `scripts/`, all source | the public GitHub repo | It is the backup |
| **User data** — library, resume positions, per-hash sync offsets, cached subtitle index | Ticket Office → **Export library** → a single JSON file the user saves wherever they like | GOAL §6: no accounts, no cloud sync. Export/import is the entire backup story, and it must exist before v1.0.0 because §11.3 makes an Android uninstall a real possibility |
| Downloaded subtitles | already on disk beside the films (`<video>.<lang>.srt`) | The sidecar *is* the backup — this is why "save beside file" is the default |

Restore drill, worth doing once: export the library, uninstall the APK, reinstall from the Release, import the JSON, confirm the rail, the resume positions and one `±0.35` sync badge all come back.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pages deploy is green but the site is blank, console shows 404s for `/assets/…` | `VITE_BASE_PATH` did not reach the build | Check the `env:` block of the build step; verify with `curl -s <url> \| grep 'src='` — every path must start with `/marquee/` |
| Lite loads, subtitle search returns nothing, console shows a CORS error on the preflight | `ALLOWED_ORIGIN` does not match the browser's `Origin` exactly (trailing slash, `www.`, wrong case) | An `Origin` is scheme + host + port with **no path**. Fix `wrangler.toml`, redeploy, re-run the §4.5 probes |
| Worker returns 403 to everything | The request has no `Origin` (curl, or a native build pointed at the proxy by mistake) | Expected. Native calls the API directly; add `-H "Origin: https://<owner>.github.io"` when probing |
| Worker returns 404 for a valid endpoint | The path is not in `ALLOW` | Add the exact upstream path to the allow-list in `worker/src/index.ts` **and** a case to `worker.test.ts` |
| Search results are missing `moviehash_match` | Unsorted query params caused the gateway's canonical 301, which drops that param | The Worker sorts them (§4.3); the native client must too (TESTING O1) |
| Everything worked yesterday, now HTTP 429 everywhere | The undocumented per-second limit (TESTING §13 #1) | Honour `Retry-After` and `X-RateLimit-Reset`; check `worker/test/observed-limits.json` for what the nightly run has seen |
| APK builds but will not install over the previous one | Debug-signed, or `versionCode` did not increase | The workflow's `apksigner verify` step catches the first; the second means `--build-number` was not passed |
| APK installs but subtitles are invisible **only on Android** | `libassAndroidFontName` is not the TTF's internal family name, or the font asset is not bundled | §8.5. Verify with `fc-query`/any font inspector that the family really is `Noto Sans` |
| Android plays video but the picture has no subtitles and no OSD | Someone set `vo: 'mediacodec_embed'` | mpv disables subtitle rendering under that vo. Keep media_kit's defaults (`vo=gpu`, `hwdec=auto-safe`) — TESTING I8 fails the build if this regresses |
| `flutter build windows` fails on a fresh runner | Flutter pin and `media_kit` disagree | This is TESTING §13 #14; move `FLUTTER_VERSION` deliberately in both `ci.yml` and `release.yml`, never by switching to `channel: stable` unpinned |
| Windows build runs but plays nothing | `libmpv-2.dll` missing from the output | The workflow asserts it before zipping; if it fails, `media_kit_libs_windows_video` did not resolve — clear the pub cache and rebuild |
| Golden tests fail only on Windows | Goldens are Linux-only by design | `flutter test --exclude-tags golden` locally; regenerate on `ubuntu-24.04` |
| `make-fixtures.sh` diff fails in CI | A different ffmpeg build produced different bytes | Regenerate on `ubuntu-24.04` (the reference), commit both the fixtures and `hashes.json`, and note it — a fixture change moves every moviehash golden |
| Cloudflare returns error 1027 | The Worker's 100k requests/day is spent | It hard-fails and never bills. Check the origin allow-list first — the only way a solo user hits this is someone else using the proxy |
| A tag ran but no Release appeared | `publish` is `if: github.ref_type == 'tag'`; a `workflow_dispatch` run deliberately produces artifacts only | Tag properly, or download the artifact from the run |
