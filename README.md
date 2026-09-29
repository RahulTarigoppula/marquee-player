# Marquee — The No-Hassle Smart Media Player

> **Drop a film. The lights go down. The subtitles are already there.**

**Status: Planned — not started** · Project 08 of 8 · design system **HOUSE LIGHTS** · repo name `marquee` (public)

Marquee is one Flutter codebase that ships a **Windows `.exe`** and an **Android APK** on the same engine — libmpv (ffmpeg + libass) through `media_kit` — so an MKV with HEVC video, AC-3 audio and an ASS subtitle track plays identically on both, with no codec packs.
The instant a file opens it is fingerprinted with the OpenSubtitles **moviehash** (128 KiB of I/O), looked up hash-first, and the best subtitle is downloaded, saved beside the file and attached **before the first frame is shown** — a hash hit means the subtitle was uploaded for that exact release, so it is already in sync.
The whole identification chain is staged as an academy leader counting **3-2-1**, so the loading indicator is literally the truth about what the app is doing; a failure stalls the numeral instead of faking progress.
A third, mandatory tier — **Marquee Lite** — is a small Vite + TypeScript web player on GitHub Pages that runs the same hash → subtitle ritual for whatever the browser can decode, through a Cloudflare Worker that holds the API key.
Everything is free and open source: no accounts of our own, no telemetry, no store listings, no paid services anywhere.

---

## Documents

| Doc | What is in it |
|---|---|
| [GOAL.md](GOAL.md) | The goal, success criteria, non-goals, MVP/v1/Someday feature split, platforms, constraints |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Stack, system diagram, folder layout, Dart + TypeScript data model, moviehash, the subtitle matching ladder, house-lights colour extraction, the Worker contract, budgets |
| [docs/PLAN.md](docs/PLAN.md) | Phases 0–6 with checkbox tasks, acceptance criteria, effort, risks, and the Weekend MVP fast path |
| [docs/DESIGN.md](docs/DESIGN.md) | HOUSE LIGHTS: palettes, type, motion, signature interactions, screen-by-screen wireframes, tokens |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Verified stack survey, API facts, licensing findings, risks — with a full verification log |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy, golden data (hashes, scoring, timecodes, tickets, contrast), fixtures, the Worker suite, performance gates, a11y, the manual Android and Windows checklists |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Worker, Pages, `ci.yml` + `release.yml`, keystore, secrets, versioning, rollback, troubleshooting |
| [docs/IMPLEMENTATION-PROMPT.md](docs/IMPLEMENTATION-PROMPT.md) | The self-contained build brief: every reconciliation, the full design system, the algorithms with golden values, the Worker source, the CI YAML — build from this one file |
| [design/preview.html](design/preview.html) | The visual contract (Lobby night + Matinee, Threading mid-sweep, Auditorium with controls, Booth sheet) |

Shared, binding context: [`_shared/DECISIONS.md`](../_shared/DECISIONS.md) (D1 Marquee exception, D2 Worker, D5 licensing, D7 tokens, D9 working agreement) and [`_shared/GETTING-STARTED.md`](../_shared/GETTING-STARTED.md).

---

## Quickstart — scaffold from zero

Marquee is the one project in the portfolio that is **not** Vite + React + Capacitor. The native tier is Flutter; **`npx cap add android` is never run here** — the Android app *is* the Flutter app. Three deployables live in one repo: the Flutter app at the root, `web/` (Marquee Lite), `worker/` (the mandatory OpenSubtitles proxy).

### 0. Accounts and keys (once, all free, no card)

```bash
# 1. github.com            -> create the public repo "marquee"
# 2. opensubtitles.com     -> Profile > API Consumers > create a consumer  => OS_API_KEY
# 3. opensubtitles.com     -> a normal free user account (about 10 downloads/day)
# 4. dash.cloudflare.com   -> Workers (Free: 100k req/day, hard-fails, never bills)
# 5. themoviedb.org        -> (optional) API Read Access Token for posters  => TMDB_READ_TOKEN
```

### 1. Repo skeleton

```bash
mkdir marquee && cd marquee && git init -b main
mkdir -p .github/workflows docs design scripts assets/fonts assets/shaders
cp ../_shared/templates/worker.yml       .github/workflows/worker.yml
cp ../_shared/templates/pages.yml        .github/workflows/pages.yml   # then edit: build runs in web/
# android-release.yml and app-build.gradle.snippet are Capacitor templates:
# read them for the SIGNING pattern only (PKCS12 + env vars) and hand-write release.yml (see PLAN 0.6)
```

### 2. Flutter app (root) — needs Flutter SDK + VS 2022 Build Tools locally, or CI only

```bash
flutter create --org com.rahul --project-name marquee \
               --platforms=windows,android .
flutter pub add media_kit media_kit_video media_kit_libs_video \
                drift drift_flutter sqlite3_flutter_libs \
                flutter_riverpod http flutter_secure_storage file_picker \
                material_color_utilities clock path_provider \
                window_manager flutter_acrylic wakelock_plus screen_brightness \
                flutter_animate flutter_svg flutter_soloud
flutter pub add --dev build_runner drift_dev flutter_lints integration_test

# drift is code-generated. `*.g.dart` and `*.drift.dart` are GITIGNORED and never
# committed, so this must run after every `pub get` and before `flutter analyze`,
# locally and in CI (ci.yml + release.yml both do it):
dart run build_runner build --delete-conflicting-outputs

# The Windows dev loop is optional; see PLAN 0.3 for the CI-only path.
flutter run -d windows
```

### 3. Marquee Lite (`web/`) — Vite + TypeScript, no framework

```bash
npm create vite@latest web -- --template vanilla-ts
cd web && npm i
npm i jassub
npm i -D vite-plugin-pwa vitest happy-dom @testing-library/dom @testing-library/user-event \
         @playwright/test @axe-core/playwright
npm i @fontsource-variable/big-shoulders-display @fontsource-variable/geist @fontsource-variable/geist-mono
npx playwright install --with-deps chromium firefox chrome   # branded chrome: H.264/AAC
# vite.config.ts:  base: process.env.VITE_BASE_PATH ?? '/'   (pages.yml sets it to /marquee/)
cd ..
```

### 4. Worker (`worker/`) — the mandatory OpenSubtitles proxy

```bash
mkdir -p worker/src && cd worker && npm init -y
npm i -D wrangler typescript @cloudflare/vitest-pool-workers vitest
cp ../../_shared/templates/worker-proxy.ts src/index.ts
# The template is only a starting point. REPLACE it with the full listing in
# docs/IMPLEMENTATION-PROMPT.md §7.6 (path allow-list, alphabetical param sorting,
# /api/subtitle-file with its host allow-list + 2 MB cap, the Authorization gate on
# /api/download, the per-IP 60/min cap, the optional /api/tmdb/* route, no logging).
# docs/DEPLOYMENT.md §4.3 carries the same listing byte-for-byte.
cat > wrangler.toml <<'TOML'
name = "marquee-proxy"
main = "src/index.ts"
compatibility_date = "2026-09-01"
# No Workers Logs: the Worker logs nothing and stores nothing.
[observability]
enabled = false
[vars]
ALLOWED_ORIGIN = "https://<owner>.github.io"
UPSTREAM_BASE  = "https://api.opensubtitles.com/api/v1"
USER_AGENT     = "Marquee-Web v1.0.0"     # mandatory upstream; omitting it is a 403
TOML
npx wrangler secret put OS_API_KEY        # never in git, never in VITE_*
npx wrangler secret put TMDB_READ_TOKEN   # optional: only if you want Lobby posters in Lite
npx wrangler deploy
cd ..
```

### 5. Signing key and secrets (once)

```bash
bash ../_shared/scripts/make-keystore.sh marquee    # run OUTSIDE the repo; BACK UP the .p12
```

Add to the repo's **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | contents of `marquee-release.p12.b64` |
| `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_PASSWORD` | the passphrase (PKCS12: both are the same) |
| `ANDROID_KEY_ALIAS` | `release` |
| `OS_API_KEY` | OpenSubtitles consumer key (injected into native builds via `--dart-define`) |
| `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` | for `wrangler deploy` |
| `TMDB_READ_TOKEN` | optional, posters only (that exact name — `release.yml` and the Worker both read it) |

Then **Settings → Pages → Source: GitHub Actions**, push to `main` (Lite goes live at `https://<owner>.github.io/marquee/`), and `git tag v0.1.0 && git push --tags` for the first Windows zip + split-per-ABI APKs on a GitHub Release.

---

## Keyboard (Windows)

The same map drives the `?` cue-sheet overlay; both come from `design/cue-sheet.json`.

<!-- cue-sheet:start -->
<!-- Generated from design/cue-sheet.json by `node scripts/check-cue-sheet.mjs --write`. Do not edit by hand. -->

| Key | Action |
|---|---|
| `Space` | Play / pause |
| `←` | Back 5 s |
| `→` | Forward 5 s |
| `Shift+←` | Back 30 s |
| `Shift+→` | Forward 30 s |
| `↑` | Volume up |
| `↓` | Volume down |
| `J` | Subtitles 50 ms earlier |
| `K` | Subtitles 50 ms later |
| `Shift+J` | Subtitles 500 ms earlier |
| `Shift+K` | Subtitles 500 ms later |
| `,` | Previous frame |
| `.` | Next frame |
| `L` | A–B loop |
| `[` | Slower (pitch-corrected) |
| `]` | Faster (pitch-corrected) |
| `F` | Fullscreen |
| `S` | Subtitle booth |
| `A` | Next audio track |
| `?` | This cue sheet |
| `Esc` | Back one lighting state |

<!-- cue-sheet:end -->

---

## Attribution

Marquee's own code is **MIT**. Everything it stands on:

**Playback engine (dynamically linked, LGPL — licence texts and source links ship in the Ticket Office)**
- [libmpv / mpv](https://github.com/mpv-player/mpv) — LGPL-2.1+ (built `-Dgpl=false`)
- [FFmpeg](https://ffmpeg.org) — LGPL-3.0 (built `--disable-gpl --enable-version3`)
- [libass](https://github.com/libass/libass) — ISC
- Build scripts: [media-kit/libmpv-android-video-build](https://github.com/media-kit/libmpv-android-video-build) (`default` flavour only — never `encoders-gpl`) and [media-kit/libmpv-win32-video-cmake](https://github.com/media-kit/libmpv-win32-video-cmake)

**Libraries** — [media_kit](https://github.com/media-kit/media-kit) (MIT), [drift](https://pub.dev/packages/drift) (MIT), [Riverpod](https://pub.dev/packages/flutter_riverpod) (MIT), [material_color_utilities](https://pub.dev/packages/material_color_utilities) (Apache-2.0), [flutter_animate](https://pub.dev/packages/flutter_animate) (BSD-3), [window_manager](https://pub.dev/packages/window_manager) · [flutter_acrylic](https://pub.dev/packages/flutter_acrylic) · [flutter_soloud](https://pub.dev/packages/flutter_soloud) (MIT), [JASSUB](https://github.com/ThaUnknown/jassub) (LGPL-2.1+ / FTL / MIT — loaded as a separate WASM module, not statically linked), [mediabunny](https://github.com/Vanilagy/mediabunny) (MPL-2.0) / [movi-player](https://github.com/mrujjwalg/movi-player) (Apache-2.0) for the optional WebCodecs path, [Howler.js](https://howlerjs.com) (MIT). Filename parsing is a Dart/TS port of [parse-torrent-title](https://github.com/clement-escolano/parse-torrent-title) (**MIT**) — deliberately *not* [guessit-js](https://github.com/opensubtitles/guessit-js) (LGPL-3.0). Candidate scoring follows [subliminal](https://github.com/Diaoul/subliminal) (MIT) as a reference model.

**Data & APIs**
- **Subtitles by [OpenSubtitles.com](https://www.opensubtitles.com)** — used through the official REST API v1 with a consumer key and the user's own free account. Credit line shown in the Lobby and the Ticket Office.
- [Subdl](https://subdl.com) — optional fallback provider, user's own free key.
- **This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.** Posters and backdrops from [themoviedb.org](https://www.themoviedb.org) are optional, non-commercial, cached ≤ 6 months, never used for ML. TMDB logo per [their attribution rules](https://www.themoviedb.org/about/logos-attribution).
- moviehash algorithm — public spec, [opensubtitles.github.io/oshash](https://opensubtitles.github.io/oshash/).

**Fonts (all SIL OFL 1.1, self-hosted / bundled — never hotlinked)**
- [Big Shoulders Display](https://github.com/xotypeco/big_shoulders) (display) · [Geist](https://github.com/vercel/geist-font) and Geist Mono (UI + numerals) · [Noto Sans](https://fonts.google.com/noto) (subtitle rendering by libass/JASSUB only)

**Icons, sound, shaders** — [Lucide](https://lucide.dev) (ISC), subset shipped as SVG assets; room tone and ticket-tear from [freesound.org CC0](https://freesound.org) / [Kenney](https://kenney.nl/assets/ui-audio) (CC0); the sine sweep, 2-pop and detent clicks are synthesised, no asset; optional upscaling presets from [Anime4K](https://github.com/bloc97/Anime4K) (MIT).

**Privacy** — no analytics, no telemetry, no crash reporting, no accounts of our own. Only the moviehash, file size, a filename-derived query and the user's own OpenSubtitles JWT ever leave the device. The Worker stores nothing and logs nothing.
