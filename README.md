# Marquee — The No-Hassle Smart Media Player

> **Drop a film. The lights go down. The subtitles are already there.**

**Status: first build pass complete — see [docs/STATUS.md](docs/STATUS.md)** · Project 08 of 8 · design system **HOUSE LIGHTS** · repo name `marquee` (public)

Marquee is one Flutter codebase that ships a **Windows `.exe`** and an **Android APK** on the same engine — libmpv (ffmpeg + libass) through `media_kit` — so an MKV with HEVC video, AC-3 audio and an ASS subtitle track plays identically on both, with no codec packs.
The instant a file opens it is fingerprinted with the OpenSubtitles **moviehash** (128 KiB of I/O), looked up hash-first, and the best subtitle is downloaded, saved beside the file and attached **before the first frame is shown** — a hash hit means the subtitle was uploaded for that exact release, so it is already in sync.
The whole identification chain is staged as an academy leader counting **3-2-1**, so the loading indicator is literally the truth about what the app is doing; a failure stalls the numeral instead of faking progress.
A third, mandatory tier — **Marquee Lite** — is a small Vite + TypeScript web player on GitHub Pages that runs the same hash → subtitle ritual for whatever the browser can decode, through a Cloudflare Worker that holds the API key.
Everything is free and open source: no accounts of our own, no telemetry, no store listings, no paid services anywhere.

---

## Documents

| Doc | What is in it |
|---|---|
| [docs/STATUS.md](docs/STATUS.md) | What is built, how it was verified, deliberate deviations from the plan, and what is open |
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

## Quickstart

Three deployables live in one repo: the Flutter app at the root (Windows + Android — **not**
Capacitor), `web/` (Marquee Lite) and `worker/` (the mandatory OpenSubtitles proxy). The scaffold
is done; this is how to work on it.

### 0. Accounts and keys (once, all free, no card)

```bash
# 1. github.com            -> create the public repo "marquee" and push this folder
# 2. opensubtitles.com     -> Profile > API Consumers > create a consumer  => OS_API_KEY
# 3. opensubtitles.com     -> a normal free user account (sign in from the Ticket Office)
# 4. dash.cloudflare.com   -> Workers (Free: 100k req/day, hard-fails, never bills)
# 5. themoviedb.org        -> (optional) API Read Access Token for posters  => TMDB_READ_TOKEN
```

### 1. Flutter app (Flutter 3.47.5, pinned in `.fvmrc`)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift; *.g.dart is gitignored
flutter analyze
dart test test/engine test/api test/db                      # the golden engine suites
flutter test                                                # + widget tests
flutter run -d windows --dart-define=OS_API_KEY=<your consumer key>
```

Without `OS_API_KEY` the app still plays everything and attaches sidecar subtitles; the leader
simply stalls at "2" with a sentence instead of searching. Windows builds need Developer Mode
(plugin symlinks) and the VS C++ workload; Android is built by CI only.

### 2. Marquee Lite (`web/`) and the Worker (`worker/`)

```bash
cd web && npm ci && npm run dev          # http://localhost:5173, talks to VITE_API_BASE
npx vitest run && npx playwright test    # unit + e2e (Worker mocked)
cd ../worker && npm ci && npm test       # every §7.6 invariant, incl. "the key never leaks"
npx wrangler secret put OS_API_KEY && npx wrangler deploy
```

Set `ALLOWED_ORIGIN` in `worker/wrangler.toml` to your Pages origin and the Worker URL in the
`VITE_API_BASE` of `.github/workflows/pages.yml` and `ci.yml` (search for `<subdomain>`).

### 3. Releasing

Push to `main` → `ci` (analyze, tests, coverage gates, parity, licences, secrets), Pages deploys
Lite, `worker.yml` deploys the proxy. `git tag v0.1.0 && git push --tags` → `release.yml` builds the
Windows zip and three split-per-ABI APKs and publishes a GitHub Release.

> **Windows SmartScreen:** the exe is unsigned (certificates cost money), so the first run shows
> "Windows protected your PC" → *More info* → *Run anyway*. Verify the zip against
> `SHA256SUMS-windows.txt` on the Release.

### 4. Signing key and secrets (once)

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
| `←` | Back 5 s (hold to keep going) |
| `→` | Forward 5 s (hold to keep going) |
| `Shift+←` | Back 30 s |
| `Shift+→` | Forward 30 s |
| `0-9` | Jump to 0 %–90 % of the film |
| `↑` | Volume up (to 150 %) |
| `↓` | Volume down |
| `M` | Mute / unmute |
| `N` | Next film in the folder |
| `P` | Previous film in the folder |
| `J` | Subtitles 50 ms earlier |
| `K` | Subtitles 50 ms later |
| `Shift+J` | Subtitles 500 ms earlier |
| `Shift+K` | Subtitles 500 ms later |
| `,` | Previous frame |
| `.` | Next frame |
| `L` | A–B loop: set A, set B, clear |
| `[` | Slower (pitch-corrected) |
| `]` | Faster (pitch-corrected) |
| `F` | Fullscreen (or double-click the picture) |
| `S` | Subtitle booth |
| `A` | Next audio track |
| `Ctrl+O` | Open a film |
| `MediaPlayPause` / `MediaTrackNext` / `MediaTrackPrevious` | Media keys: play / pause, next, previous film |
| `?` | This cue sheet |
| `Esc` | Back one lighting state (fullscreen first) |

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
