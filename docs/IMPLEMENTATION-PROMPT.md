# Marquee — THE IMPLEMENTATION PROMPT

**Project 08 of 8 · codename *Marquee* · design system **HOUSE LIGHTS** · repo `marquee`**
**Written 2026-09-08. This document is self-contained: you need no other file to build the app.**

You are reading the single brief for building Marquee from an empty folder to three deployed
artifacts. Everything you need — tokens, wireframes, algorithms with golden values, API shapes,
CI YAML, acceptance criteria — is inlined below. Where this file disagrees with a memory,
a habit, or another document, **this file wins**.

---

## 0. Reconciliations already applied (read this first)

The planning documents behind this brief contradicted each other in a handful of places. Every
conflict has been settled here, once. Do not re-litigate them; do not "fix" them back.

| # | Conflict | Settled as | Why |
|---|---|---|---|
| R1 | CI Java version: one doc said Temurin **21** (copied from the Capacitor recipe used by the other seven projects), another said **17** | **Temurin 17** everywhere in this repo | This is a Flutter + AGP project, not Capacitor. 17 is the version proven by the reference Flutter release pipelines (Mangayomi, Kazumi) with this Flutter/AGP/Gradle triple. `compileOptions`/`kotlinOptions` are pinned to `JavaVersion.VERSION_17` to match. If a future AGP demands 21, change `setup-java`, `compileOptions`, `kotlinOptions` and this row in one commit |
| R2 | `minSdk`: the shared portfolio recipe says **24**; the product goal says Android **8.0+** | **`minSdk = 26`** | GOAL is the product contract: "Android 8.0+ (minSdk 26), arm64-v8a primary". 24 is a Capacitor default and does not apply |
| R3 | Some notes claim `docs/TESTING.md` and `docs/DEPLOYMENT.md` are unwritten or stop mid-file | **Both exist and are complete.** Ignore any note, checklist item or README line claiming otherwise | Those notes are stale. Every golden table, budget gate, checklist and workflow they describe is reproduced below anyway, so you are not blocked either way |
| R4 | Scoring: should `x264` and `H264` be normalised to one codec token? | **No. They are different tokens.** The comparator is case-insensitive **exact token equality** | An x264 BluRay encode and a generic-H264 WEB-DL are different provenance. The frozen golden scores (§6.4) are computed with them distinct. If you ever normalise them, every number in §6.4 changes and **must** be updated in the same commit |
| R5 | Android package identity: one doc used `com.rahul.marquee`, an earlier draft used a vendor-style id under a `marquee` org | **`com.rahul.marquee`** is the `applicationId`, the `namespace`, and the Kotlin package (`android/app/src/main/kotlin/com/rahul/marquee/`) | An `applicationId` can never change after the first install, so it is settled once, here — and it must match the portfolio convention `com.rahul.<repo>` that projects 01–07 already use (`com.rahul.nocturne`, `com.rahul.jyoti`, `com.rahul.barometer`, …). `flutter create --org com.rahul --project-name marquee --platforms=windows,android .` produces exactly this: no namespace rewrite, no Kotlin directory move, no rename step before the first tag |
| R6 | Worker feature set: the deployment runbook's implementation was smaller than the architecture contract (no subtitle-file route, no per-IP cap, no auth gate on `/download`, no TMDB route) | **Build the superset** in §7.6 — allow-list + param sorting + `no-store` + `Api-Key` stripping **plus** the `/api/subtitle-file` route, the `Authorization` requirement on `/api/download` and `/api/infos/user`, the per-IP soft cap, and the optional `GET /api/tmdb/*` route. **§7.6 is the normative listing and DEPLOYMENT §4.3 is byte-identical to it** — change both in one commit or not at all | The Lite tier cannot fetch the `.srt` without the subtitle-file route (the temporary link's CORS posture is unverified), and the auth gate is what stops Lite spending the Worker IP's shared anonymous pool |
| R7 | Budgets differ between documents (APK 45 vs 55 MB; Lite JS 60 vs 120 KB gz; Lighthouse perf 95 vs 90) | **The looser number is the CI gate; the tighter number is the target.** APK gate 55 MB / target 45. Lite JS gate 120 KB gz / target 60. Lighthouse perf gate ≥ 90 / target ≥ 95, accessibility **= 100** either way | A gate you cannot pass on a shared runner is not a gate. Track the target in the PR description; fail the build on the gate |
| R8 | `design/preview.html` — the visual contract | It exists at `design/preview.html`. **Treat §3 and §4 of this file as the normative spec**; use the preview to check yourself, not to discover the design | The preview and §3/§4 were generated from the same token source. If they ever disagree, §3/§4 wins and the preview gets regenerated |

---

## 1. Role and mission

### 1.1 Who you are

You are a principal engineer shipping a personal, free, open-source media player alone. You write
pure logic first with golden tests, then give it a face. You do not add a dependency you cannot
justify in one sentence. You do not ship a spinner. You do not ship a red banner. You finish
things: every phase below ends with something a stranger can download and run.

### 1.2 The product, in one paragraph

**Marquee is a cinema that dims for you.** It is one Flutter codebase that ships a Windows `.exe`
and an Android APK over the same engine — libmpv (ffmpeg + libass) via `media_kit` — so an MKV with
HEVC video, AC-3 audio and an ASS subtitle track plays identically on both, with no codec packs and
no "unsupported format". The moment a file is opened it is fingerprinted with the OpenSubtitles
*moviehash* (128 KiB of I/O, ~40 ms), looked up hash-first on OpenSubtitles.com, the best candidate
is downloaded, written beside the file and attached — before the first frame is shown. A hash hit
means the subtitle was uploaded for that exact release, so it is already in sync; a filename-only
hit is labelled honestly and a per-file sync rule fixes it in 50 ms steps. The whole identification
chain is staged as an academy leader counting 3-2-1, so **the loading indicator is the truth about
what the app is doing**. A third, mandatory tier — **Marquee Lite** — is a small Vite + TypeScript
web player on GitHub Pages that performs the same ritual for whatever the browser can decode,
through a Cloudflare Worker that holds the API key, and is honest about what it cannot play.

**The one-sentence pitch:** *Drop any film on Windows or Android, and by the time the leader counts
3-2-1 it has been fingerprinted, its subtitles found and threaded, and the walls are already glowing
with its colour.*

### 1.3 The quality bar

Three adjectives: **Dim · Warm · Honest.**

- **If it looks like a generic dashboard, start over.** No cards-on-grey, no pill buttons everywhere,
  no gradient hero, no icon-plus-label toolbar. Marquee is a *room*: a beam, walls that receive
  light, a sky that knows the time, a working academy leader as the loading indicator, and a film
  gate as the seek bar.
- **If a screenshot could be mistaken for VLC, Plex or Kodi, it has drifted.** Those are a black
  rectangle with a progress bar.
- **If it looks like retro-cinema kitsch, start over.** No popcorn, curtains, red velvet, art-deco
  fonts, fake scratches or chasing bulbs. Crimson is a 1 px trim line and a ticket stub. Nothing more.
- **If it looks like skeuomorphic hardware, start over.** No bevels, gloss, brass knobs, wood.
  Controls are small luminous marks. Light is functional: **if an element glows, it is on.**
- **Loud is a bug.** One accent per screen. Errors are a stalled leader numeral and one plain
  sentence — never a red banner, never a spinner, never an error code in the UI.
- Every UI state is a lighting state. Motion is lighting, not movement: things dim, warm, sweep and
  settle. They do not bounce or slide.

And it must be genuinely usable in the dark: every control reachable by keyboard on Windows, by
thumb on Android (≥ 44 × 44 px, the film gate 56 px), every text token ≥ 4.5 : 1 on its surface,
`prefers-reduced-motion` honoured — with the leader still stalling honestly.

---

## 2. Non-negotiables

### 2.1 Repo, hosting, identity

| Thing | Value |
|---|---|
| GitHub repo | **`marquee`**, public (public is the price of Pages + unlimited Actions minutes) |
| Licence of our code | **MIT** (`LICENSE` at the root) |
| Web URL | `https://<owner>.github.io/marquee/` (GitHub Pages, sub-path `/marquee/`) |
| Worker URL | `https://marquee-proxy.<subdomain>.workers.dev` (Cloudflare Workers, Free plan) |
| Android `applicationId` / namespace | **`com.rahul.marquee`** — permanent, never changes (R5); portfolio convention `com.rahul.<repo>` |
| Android Kotlin package dir | `android/app/src/main/kotlin/com/rahul/marquee/` (produced directly by `flutter create --org com.rahul`) |
| Flutter project name | `marquee` (so `pubspec.yaml` `name: marquee`) |
| Windows artifact | `marquee-<version>-windows-x64.zip` (portable; extract and run `marquee.exe`) |
| Android artifacts | `marquee-<version>-arm64-v8a.apk` (primary) + `armeabi-v7a` + `x86_64`, **split-per-ABI, never a universal APK** |

### 2.2 Stack — exact packages and versions

**Native tier (Windows 11 x64 + Android 8.0+), Flutter:**

| Layer | Package / version | Notes |
|---|---|---|
| Framework | **Flutter stable `3.47.0`** (pinned in CI and `.fvmrc`) | Pin the exact version; never `channel: stable` unpinned. Move it only in a deliberate commit |
| Dart SDK | `^3.9.0` | |
| Player core | **`media_kit ^1.2.6`**, **`media_kit_video ^2.0.1`**, **`media_kit_libs_video ^1.0.7`** | libmpv = ffmpeg + libass. MIT wrapper over LGPL natives |
| DB | **`drift ^2.34.4`** + `drift_dev ^2.34.0` + **`sqlite3_flutter_libs ^0.5.0`** | Typed SQL, migrations, `NativeDatabase.memory()` for tests. **Not `isar`** |
| State | **`flutter_riverpod ^3`** | `AsyncValue` maps 1:1 onto the leader's phase/stall model |
| HTTP | **`http ^1.2.0`** + `package:http/testing.dart` `MockClient` | |
| Secrets | **`flutter_secure_storage ^9.2.0`** | JWT only. The password is never stored |
| Colour | **`material_color_utilities ^0.11.0`** | `QuantizerCelebi` + `Hct` for the bias light. **Not `palette_generator`** (discontinued) |
| Files | **`file_picker ^8.0.0`** | SAF on Android, native dialog on Windows |
| Windows chrome | **`window_manager ^0.5.2`** + **`flutter_acrylic ^1.1.4`** | Frameless window; Mica in the Lobby only |
| Device | **`wakelock_plus ^1.2.0`**, **`screen_brightness ^2.0.0`** | Keep-awake during playback only; per-app brightness restored on exit |
| Motion / vector | **`flutter_animate ^4.5.2`**, **`flutter_svg`** | |
| Sound | **`flutter_soloud`** | Room tone + synthesised sweep / 2-pop / detent |
| Determinism | **`clock ^1.1.1`** | `withClock(Clock.fixed(…))` in every test that shows time |
| Paths | **`path_provider ^2.1.0`** | |
| Dev | `flutter_test`, `integration_test`, `build_runner ^2.4.0`, `flutter_lints ^5.0.0`, `flutter_native_splash ^2.4.0`, `flutter_launcher_icons ^0.14.0` | |
| Shaders | Flutter `FragmentProgram.fromAsset` (GLSL 460 → Impeller) | `assets/shaders/beam.frag`, `grain.frag` |

**Web tier ("Marquee Lite"), in `web/`:**

| Layer | Choice | Notes |
|---|---|---|
| Build | **Vite 8 + TypeScript 5 strict**, `vanilla-ts` template | **No framework.** One screen with a `<video>`, a leader and a sheet; React would cost ~45 KB gz for nothing |
| Styling | Hand-written CSS + `src/styles/tokens.css` (generated) | No Tailwind here |
| ASS/SSA | **`jassub ^2.5.16`**, dynamic `import()` only when an `.ass`/`.ssa` attaches | ~1.2 MB WASM must never be on the landing page |
| SRT | own `srt2vtt.ts` → `<track>` via Blob URL | ~60 lines, no dependency |
| Stretch decode | **`movi-player ^0.4.0`** (Apache-2.0) *or* **`mediabunny ^1.55`** (MPL-2.0), dynamic import behind a button | Never on the critical path |
| PWA | **`vite-plugin-pwa` 1.x** (Workbox), `registerType: 'autoUpdate'` | |
| Storage | **IndexedDB**, own ~80-line promise wrapper, one object store per entity | No Dexie |
| Sound | **Howler.js** + Web Audio synthesis | |
| Fonts | **Fontsource** variable, self-hosted, Latin subset | Never hotlink Google Fonts in a production build |
| Test | Vitest (`happy-dom`) + `@testing-library/dom` + Playwright + `@axe-core/playwright` | |
| Lint | **Biome** (covers `web/` and `worker/`) | `dart format` + `flutter_lints` cover Dart |

**Proxy tier, in `worker/`:** Cloudflare Workers (Free plan), TypeScript, **zero runtime
dependencies**, single `src/index.ts`. Tested with `@cloudflare/vitest-pool-workers`.

### 2.3 The free-only rule

Nothing in this project may cost money and nothing may ask for a card. GitHub (public repo, Pages,
Actions, Releases), Cloudflare Workers Free (100 000 req/day, 10 ms CPU, hard-fails with error 1027,
**never bills**), an OpenSubtitles free consumer key + free user account, an optional Subdl free key
(the *user's* own), an optional TMDB free non-commercial token. **If any step demands a payment
method, stop and re-plan** — do not work around it. (If Cloudflare ever demands a card, Lite loses
OpenSubtitles and becomes a sidecar-only local player; that is a recorded scope change, not a hack.)

### 2.4 Licence rules (hard)

1. **Our code is MIT.** Bundled dependencies must be OSI: MIT / Apache-2.0 / BSD / ISC / MPL /
   Unlicense / CC0. **AGPL and GPL are banned** in anything we link statically or bundle.
2. **libmpv / ffmpeg / libass are LGPL and are dynamically linked.** That is what lets the app stay
   MIT. Therefore:
   - Android: ship the **`default`** media_kit native flavour (ffmpeg `--disable-gpl
     --enable-version3`, mpv `-Dgpl=false`). **Never the `encoders-gpl` flavour** — it would make the
     app GPLv3.
   - Windows: ship the `libmpv-2.dll` that `media_kit_libs_windows_video` provides (from
     `media-kit/libmpv-win32-video-cmake`, an LGPL build). If it is ever refreshed, only from a
     **`mpv-dev-lgpl-x86_64-*`** package — the plain package is a GPL build and would relicense the app.
   - Ship LGPL notice texts and links to both build-script repos in the Ticket Office About block.
3. **Fonts are OFL 1.1:** Big Shoulders Display, Geist, Geist Mono, Noto Sans. Icons are **Lucide
   (ISC)**. Sounds are **CC0** (freesound CC0 filter / Kenney). Licence texts live in `LICENSES/`.
4. **Port MIT `parse-torrent-title` to Dart/TS.** Never `guessit-js` (LGPL-3.0).
5. **TMDB** is optional and non-commercial: render the TMDB logo **and the exact notice sentence**
   wherever artwork appears, cap the artwork cache at **180 days** (enforced in code, swept at
   startup), and never apply any ML/LLM to TMDB data (there is no LLM in this app, so this is
   satisfied by construction).
6. **Credit "Subtitles by OpenSubtitles.com"** in the Lobby footer and the Ticket Office.
7. Every README ships an **Attribution** section listing data, font, native-library and sound credits.

### 2.5 Privacy (hard)

- **No analytics, no telemetry, no crash reporting, no remote config, no accounts of our own, no
  install id, and no "anonymous usage statistics" toggle** — because there is nothing to toggle.
- What may ever leave the device: the 16-hex moviehash, the file size, a filename-derived query
  string, the chosen `file_id`, and the user's own OpenSubtitles JWT. **Never** the file, never a
  frame, never a path, never a device identifier.
- The Worker **logs nothing and stores nothing**: no `console.*`, no KV, no D1, no Analytics Engine
  binding. A Biome `noConsole` rule scoped to `worker/` fails the build on a `console.log`.
- A CI grep fails the build on `analytics|sentry|posthog|gtag|firebase` anywhere in the tree.
- Diagnostics are local and opt-in only: a `--verbose` flag on Windows dumps mpv's log to
  `%LOCALAPPDATA%\Marquee\mpv.log`, and errors offer "Copy details" to the clipboard for a
  hand-filed issue. Nothing is ever sent anywhere automatically.

### 2.6 Offline (hard)

The native tier is offline **by construction**: playback, the library, resume points, sync offsets,
embedded tracks, sidecar subtitles and every previously fetched subtitle work with the radio off.
Only the subtitle search and download need a network, and their failure is a *stall with a named
next action*, never a dead end. Lite is a PWA: the shell precaches, a previously fetched subtitle
re-attaches from IndexedDB offline, and the leader stalls at "2" with
*"You're offline — playing without new subtitles."*

### 2.7 Non-goals — do not build these

No streaming, torrents, IPTV, DLNA/UPnP, Chromecast. No media server. No accounts of our own, no
cloud sync. **No transcoding, ever.** No LLM features of any kind (identification is hash → filename
grammar → TMDB `/find`; "smart" means deterministic). No scraping of sites without an API. No
Play Store or Microsoft Store listing, no code-signing certificates. No iOS/macOS/Linux builds.
**No light theme during playback** — the Auditorium is dark-only by design.

### 2.8 Folder layout (create exactly this)

```
marquee/
├── pubspec.yaml                   # the Flutter app IS the repo root
├── analysis_options.yaml          # flutter_lints + the engine-purity rules
├── LICENSE                        # MIT (our code)
├── LICENSES/                      # LGPL-2.1, LGPL-3.0, ISC, OFL texts + build-script links
├── README.md                      # quickstart, screenshots, keyboard table, Attribution
├── CHANGELOG.md
├── lib/
│   ├── main.dart                  # ProviderScope, MediaKit.ensureInitialized(), window bootstrap
│   ├── app.dart                   # routes (Lobby/Threading/Auditorium/Booth/TicketOffice), theme
│   ├── engine/                    # PURE DART — no `package:flutter/...` imports, ever
│   │   ├── hash.dart              # moviehash                        (§6.2)
│   │   ├── filename.dart          # parse-torrent-title port         (§6.3)
│   │   ├── scoring.dart           # candidate ranking                (§6.4)
│   │   ├── threading.dart         # the leader state machine         (§6.5)
│   │   ├── tickets.dart           # quota → ticket-strip view model  (§6.6)
│   │   ├── timecode.dart          # folio strings                    (§6.7)
│   │   ├── sync_rule.dart         # 50 ms detents, clamp, memory     (§6.8)
│   │   ├── detents.dart           # chapter / 5-min gate detents     (§6.9)
│   │   ├── bias_light.dart        # 5-stop colour extraction         (§6.10)
│   │   ├── srt.dart               # SRT parse / shift / emit         (§6.11)
│   │   └── models/                # the immutable data classes       (§5.1)
│   ├── api/
│   │   ├── opensubtitles.dart     # REST v1: sorted params, headers, 401/406/410/429 → typed failures
│   │   ├── subdl.dart             # fallback: keyed search, ANONYMOUS zip download
│   │   ├── tmdb.dart              # optional /find + image URLs, 180-day cache cap
│   │   └── net.dart               # retry/backoff, Retry-After, X-RateLimit-* parsing
│   ├── db/
│   │   ├── database.dart          # @DriftDatabase, schemaVersion, migrations
│   │   ├── tables.dart            # the eight tables (§5.2)
│   │   └── daos/
│   ├── player/
│   │   ├── engine.dart            # media_kit Player/VideoController lifecycle, mpv property bridge
│   │   ├── tracks.dart            # embedded audio/subtitle listing + switching
│   │   └── screenshot.dart        # throttled frame grab → bias light (does the top-80% crop)
│   ├── platform/
│   │   ├── files.dart             # picker, SAF persisted grants, "is this folder writable?"
│   │   ├── pip.dart               # MethodChannel('marquee/pip')        → Kotlin
│   │   ├── mediastore.dart        # MethodChannel('marquee/mediastore') → Kotlin
│   │   └── window.dart            # frameless window, Mica, title-bar drag (Windows)
│   ├── state/                     # Riverpod providers (§5.4)
│   ├── ui/
│   │   ├── lobby/ threading/ auditorium/ booth/ ticket_office/
│   │   └── components/            # marquee_sign, bulb, beam, leader, ticket_strip, film_gate,
│   │                              # sync_rule, candidate_row, folio, booth_sheet, transport_mark
│   └── theme/tokens.dart          # GENERATED by scripts/tokens.mjs — never hand-edited
├── assets/
│   ├── fonts/                     # BigShouldersDisplay-Variable.ttf, Geist-Variable.ttf,
│   │                              # GeistMono-Variable.ttf, NotoSans-Regular.ttf, NotoSans-Bold.ttf
│   ├── shaders/                   # beam.frag, grain.frag
│   ├── icons/                     # Lucide SVG subset (ISC)
│   └── sounds/                    # projector-loop.ogg, ticket-tear.ogg (CC0)
├── android/                       # `flutter create` output, committed (NOT Capacitor)
│   └── app/src/main/kotlin/com/rahul/marquee/
│       ├── MainActivity.kt        # + PiP callbacks, predictive back
│       ├── PipChannel.kt          # ~60 lines
│       └── MediaStoreChannel.kt   # ~150 lines
├── windows/                       # `flutter create` output, committed
├── test/                          # unit, db, widget, goldens, fixtures
│   ├── flutter_test_config.dart   # font loading, 0.5% golden tolerance, fixed clock
│   ├── engine/ db/ widgets/ theme/ a11y/ goldens/
│   └── fixtures/{media,os,hashes.json}
├── integration_test/              # player, subtitles, seek, keyboard, house, perf (real libmpv)
├── tool/                          # check_coverage.dart, check_licences.dart, check_no_secrets.sh
├── web/                           # Marquee Lite
│   ├── index.html · vite.config.ts · package.json · biome.json · playwright.config.ts
│   ├── src/
│   │   ├── main.ts · config.ts
│   │   ├── engine/                # osHash.ts, srt2vtt.ts, scoring.ts, filename.ts, capability.ts,
│   │   │                          # tickets.ts, timecode.ts, syncRule.ts, threading.ts, types.ts, api.ts
│   │   ├── ui/                    # lite.ts, leader.ts, gate.ts, booth.ts, noPrint.ts
│   │   ├── storage/idb.ts
│   │   └── styles/tokens.css      # GENERATED
│   ├── public/                    # manifest icons, LICENSES/
│   └── e2e/                       # Playwright specs incl. visual/ and perf/
├── worker/
│   ├── src/index.ts · wrangler.toml · package.json
│   └── test/{worker.test.ts,contract.test.ts,fixtures/}
├── scripts/
│   ├── tokens.mjs                 # one token source → tokens.css + tokens.dart
│   ├── make-fixtures.sh           # bit-exact ffmpeg media fixtures
│   └── check-parity.mjs           # Dart ↔ TS test-name parity
├── design/{preview.html,cue-sheet.json}
├── docs/                          # GOAL, RESEARCH, DESIGN, ARCHITECTURE, PLAN, TESTING, DEPLOYMENT,
│                                  # and this file
├── tools/libmpv-windows.sha256    # provenance lock for the shipped DLL
└── .github/workflows/
    ├── ci.yml · pages.yml · worker.yml · release.yml · contract.yml
```

**Two structural laws, enforced by tests:**

1. **Nothing in `lib/engine/` may import `package:flutter/…` or Riverpod.** A test greps the folder
   and fails the build. This is what keeps the Dart and TypeScript engines swappable and lets them
   share one set of golden tables.
2. **UI widgets never call `lib/api` or `lib/db` directly.** Only providers do.

---

## 3. Design and aesthetics — the complete frontend brief

This section is the whole design system. Build from it; check yourself against
`design/preview.html`.

### 3.1 Identity

**Name:** the design system is **HOUSE LIGHTS**; the app is **Marquee**.

**One-liner:** *A single-screen cinema at night that dims for you.* Drop a film and the house lights
go down, the projector beam finds the screen, an academy leader counts 3-2-1 while the file is hashed
and its subtitles are threaded, and the walls glow with the colour of whatever is playing. Every UI
state is a lighting state; chrome is replaced by light.

**Adjectives:** Dim · Warm · Honest.

**It must never look like:**

| Anti-pattern | What that means concretely |
|---|---|
| **Retro-cinema kitsch** | No popcorn, curtains, red-velvet gradients, art-deco fonts, fake scratches, chasing bulbs. Crimson is a 1 px trim line and a ticket stub. Grain lives in the Lobby at 4 % and never touches the picture |
| **"YouTube ambient mode in a dark player"** | Marquee is a room, not a black rectangle with a progress bar. The beam, the walls, the sky, the working leader and the film gate are all *functional* |
| **An editorial paper document** | No cream page ground in playback, no hairline tables, no serif anywhere. Condensed caps + a quiet grotesk on near-black |
| **Skeuomorphic hardware** | No bevels, gloss, brass knobs, wood. Controls are small luminous marks (Teenage-Engineering glyph language), not rendered objects |
| **Loud** | Never more than one accent per screen, never a red error banner over the picture, never a spinner |

**Wordmark:** `MARQUEE` in Big Shoulders Display 900 with 7 bulbs beneath. **App icon:** a single lit
bulb on the crimson-trimmed marquee box.

### 3.2 Colour — two rooms, two palettes

**Auditorium (dark) is the default and the only palette during playback.** A light theme over a
moving picture is a contradiction (glare, halation, subtitle contrast) — that is the justification
for a dark-only playback surface. **Matinee (light)** exists for the **Lobby, Subtitle Booth and
Ticket Office only**, follows `prefers-color-scheme` or the user's pin, and is never applied while a
file is open. Opening a file always switches to Auditorium via the HOUSE-DOWN animation.

| Token | Auditorium | Usage | Contrast (bg / surface / surface-2) |
|---|---|---|---|
| `--bg` | `#07060A` | Auditorium black — page ground and the wall behind the picture. Warm-violet black. Only the letterbox behind the video itself is `#000` | — |
| `--bg-elevated` | `#120E15` | Booth — sheets, dialogs, lobby floor | — |
| `--surface` | `#1B1620` | Velvet — cards, poster rail, candidate rows | — |
| `--surface-2` | `#26202B` | Velvet lit — hover/pressed, seek-strip base, film-gate track | — |
| `--ink` | `#F3E9DA` | Screen white — primary text, marquee letters, timecodes | 16.8 · 14.8 · 13.2 |
| `--ink-muted` | `#A89C8C` | Release names, fps, meta | 7.5 · 6.6 · 5.9 |
| `--ink-faint` | `#8C8276` | Labels, tick numerals, placeholders. **Never body text on `--surface-2`** — use ≥ 18 px there | 5.4 · 4.7 · 4.2 |
| `--accent` | `#FFC56E` | Tungsten bulb — bulbs, aisle lights, active controls, the beam colour, primary fills | 13.0 on bg |
| `--accent-ink` | `#1A1006` | Text on tungsten fills; also text on `--danger` fills | 12.0 on accent |
| `--accent-2` | `#A3252F` | Curtain crimson — the 1 px marquee trim, ticket stubs, low-quota strip. **Non-text on dark** | 2.8 (decorative) |
| `--accent-2-lit` | `#E0525C` | Crimson brightened for text/glyphs on dark ("2 tickets left") | 5.3 · 4.7 · 4.2 (≥ 18 px on surface-2) |
| `--success` | `#5FD48A` | Exit-sign green — MATCH bulb, "attached", "saved beside file" | 10.8 · 9.5 · 8.5 |
| `--warning` | `#F5A05F` | Sodium orange — quota nearly out, `CHECK SYNC`, hwdec fallback | 9.7 · 8.5 · 7.6 |
| `--danger` | `#E5484D` | Undecodable print, 429/406, expired link | 5.2 · 4.5 · 4.1 (≥ 18 px on surface-2) |
| `--border` | `#2A2330` | 1 px seams: sheet top edge, rail dividers | decorative |
| `--border-strong` | `#3D3446` | Pressed/active seams, input underlines | decorative |
| `--focus` | `#FFD68A` | Focus ring (2 px + 2 px offset); also the bias-light fallback tint | 14.7 on bg |

| Token | Matinee | Contrast |
|---|---|---|
| `--bg` | `#F1E8D8` (cream lobby wall) | — |
| `--bg-elevated` | `#F8F2E6` | — |
| `--surface` | `#E8DECB` | — |
| `--surface-2` | `#DDD1BC` | — |
| `--ink` | `#2A2226` | 12.8 · 11.6 · 10.3 |
| `--ink-muted` | `#5E5350` | 6.1 · 5.6 · 4.9 |
| `--ink-faint` | `#605651` | 5.9 · 5.3 · 4.7 |
| `--accent` | `#7F4800` (dark tungsten) | 6.1 · 5.6 · 4.9 |
| `--accent-ink` | `#FFF6E6` | 6.9 on accent |
| `--accent-2` / `--accent-2-lit` | `#A3252F` / `#A3252F` (crimson carries text in Matinee) | 6.0 |
| `--success` / `--warning` / `--danger` | `#186639` / `#8A4B00` / `#A8231C` | 5.8 / 5.6 / 5.9 |
| `--border` / `--border-strong` / `--focus` | `#D6CAB5` / `#B9AB93` / `#7A4A00` | focus 6.2 |

In Matinee the marquee bulbs are **off** (letters painted `--ink`, box `--surface-2`), the beam and
dust are not drawn, and the sky band is at full strength — it is daylight.

**Derived / semantic tokens**

| Token | Value | Notes |
|---|---|---|
| `--picture-bg` | `#000000` | Only ever behind the `<video>`/texture. Never a page ground |
| `--wall-glow` | runtime | 5-stop radial gradient from bias-light sampling; falls back to `--focus` at 6 % alpha |
| `--bulb-halo` | `0 0 6px 1px color-mix(in oklch, var(--accent) 55%, transparent)` | The only glow allowed. Lit bulbs and aisle lights only |
| `--booth-glass` | `color-mix(in oklch, var(--bg-elevated) 78%, transparent)` + `backdrop-filter: blur(24px)` | Sheets over a **paused** frame only |
| `--sky-dawn/day/dusk/night` | `#3A2A2E` / `#2A2E3A` / `#2F2438` / `#0B0A10` (Auditorium, ~6 % saturation) · `#F5C9A8` / `#C9D6E8` / `#C8A9D6` / `#1A1622` (Matinee, full strength) | Lobby sky band, chosen by local clock |
| `--house` | `1` → `0` | The single number that drives every lighting change |
| `--grain-opacity` | `0.04` (Matinee `0.03`) | Lobby and sheets only; **`0` in the Auditorium** |

**Gradient / material budget.** Exactly one gradient family exists: the **sky band** (linear, 4
stops) and the **wall glow** (radial, from the sampled frame). No gradient buttons, no gradient text,
no crimson gradients. **One light source:** every shadow falls *down* (the projector is above and
behind the viewer) and every glow is tungsten.

### 3.3 Typography

| Role | Family | Source | Weights | Where |
|---|---|---|---|---|
| `--font-display` | **Big Shoulders Display** | `@fontsource-variable/big-shoulders-display` (web) · `assets/fonts/BigShouldersDisplay-Variable.ttf` (Flutter). OFL 1.1 | variable wght; use 500 / 700 / 900 | Marquee title, leader numerals, big timecode, section heads in caps |
| `--font-body` | **Geist** | `@fontsource-variable/geist` · `Geist-Variable.ttf`. OFL 1.1 | 400 / 500 / 600 | All UI copy, buttons, settings |
| `--font-mono` | **Geist Mono** | `@fontsource-variable/geist-mono` · `GeistMono-Variable.ttf`. OFL 1.1 | 400 / 500; `tabular-nums` always; `ss01` slashed zero for hashes | Folio, timecodes, moviehash, fps, sub-delay, quota, cue sheet |
| Subtitles | **Noto Sans** | `assets/fonts/NotoSans-Regular.ttf` + `-Bold.ttf`. OFL | 400 / 700 | Rendered by **libass/JASSUB only** — never a brand font on the picture |

**Forbidden here:** Fraunces, Bebas Neue, any serif, any second grotesk. A CI check greps every
`font-family` in `tokens.css` and `pubspec.yaml` and fails on anything outside those four.

**Type scale** (base 16 px):

| Token | rem | px | Use |
|---|---|---|---|
| `--text-xs` | 0.75 | 12 | Mono meta, tick numerals — never smaller |
| `--text-sm` | 0.875 | 14 | Secondary UI, candidate meta |
| `--text-base` | 1 | 16 | Body, buttons, list rows |
| `--text-lg` | 1.125 | 18 | Sheet titles, desktop folio |
| `--text-xl` | 1.375 | 22 | Card titles, big mono readouts |
| `--text-2xl` | 1.75 | 28 | Section heads (display, caps, +0.06 em) |
| `--text-3xl` | 2.25 | 36 | Marquee on phone |
| `--text-4xl` | `clamp(3rem, 6vw, 4rem)` | 48–64 | Marquee on desktop, leader numerals on phone |
| `--text-5xl` | `clamp(5rem, 14vw, 9rem)` | 80–144 | Leader numerals on desktop, the idle `MARQUEE` sign |

`--leading-tight: 1.05` (display) · `--leading-body: 1.5`.

**Letter-spacing.** Display caps `+0.06em` at ≤ 2xl, `+0.02em` at 3xl and above (condensed faces
close up as they grow). Geist body `0`. Small labels: `text-transform: uppercase; font-size:
var(--text-xs); letter-spacing: 0.08em; font-weight: 500; color: var(--ink-faint)`. Mono `0` with
`font-variant-numeric: tabular-nums lining-nums` **always on**, so timecodes, hashes and delay values
never jitter. Leader numerals are optically centred **2 % above** geometric centre.

**Scripts.** Subtitles may be any script; libass falls back through Noto Sans only. On Android
`sub-font-provider=none`, so **only bundled fonts exist** — an "Indic subtitles" pack (Noto Sans
Devanagari/Tamil) is a later download into the same fonts directory. The UI never displays user
subtitle text, so Geist's Latin coverage is sufficient. Language names appear as ISO code in mono
(`EN · HI · TA`) plus the English exonym in Geist.

### 3.4 Spacing, radius, elevation, layout

| Token | Value |
|---|---|
| `--space-1 … --space-12` | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 80 · 96 px (8-pt grid with a 4 px half-step) |
| `--radius-sm` | 4 px — bulb boxes, tickets, chips |
| `--radius-md` | 8 px — cards, candidate rows, inputs |
| `--radius-lg` | 12 px — sheets (top corners), posters |
| `--radius-xl` | 20 px — the picture's bezel in the Lobby preview only |
| `--radius-full` | 9999 px — the tungsten Open disc and bulbs. **Nothing else is a pill** |
| `--shadow-1` | `inset 0 1px 0 rgba(255,255,255,.04), 0 2px 6px rgba(0,0,0,.5)` — rows, chips |
| `--shadow-2` | `inset 0 1px 0 rgba(255,255,255,.05), 0 8px 24px rgba(0,0,0,.55)` — cards, popovers |
| `--shadow-3` | `inset 0 1px 0 rgba(255,255,255,.06), 0 24px 56px rgba(0,0,0,.65)` — sheets |
| Matinee shadows | flat alphas: `0 1px 2px rgba(42,34,38,.12)` / `0 6px 18px …16` / `0 18px 40px …22` |
| Borders | **1 px seams only.** No element has a border on all four sides except the focus ring; inputs are underline-only |
| Layout | phone 20 px margins, 4 columns; desktop max 1280 px, 12 columns, 24 px gutters. The video is always centred and **never overlapped by chrome** |
| Targets | ≥ 44 × 44 px; film gate 56 px on phone (40 px desktop); edge dimmers 48 px wide |

### 3.5 Motion language

**Principle: motion is lighting, not movement.** Things dim, warm, sweep and settle. Translate is
≤ 8 px except sheets (which rise on the one spring). **Type never scales.**

| Token | Value | Use |
|---|---|---|
| `--dur-fast` | 120 ms | Bulb/hover states, controls returning on touch |
| `--dur-base` | 240 ms | Control reveal, row selection, sheet content |
| `--dur-slow` | 480 ms | View changes, control fade-out |
| `--dur-house` | **900 ms** | Any change of lighting state — Marquee-specific |
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | Everything entering |
| `--ease-in-out` | `cubic-bezier(0.65, 0, 0.35, 1)` | Crossfades, sky |
| `--ease-house` | `cubic-bezier(0.7, 0, 0.3, 1)` | The dimmer curve — slow at both ends |
| `--ease-spring` | `linear(0, 0.006, 0.025 2.8%, 0.101 6.1%, 0.539 18.9%, 0.721 25.3%, 0.849 31.5%, 0.937 38.1%, 0.968 41.8%, 0.991 45.7%, 1.006 50.1%, 1.012 55.4%, 1.011 62.6%, 1.006 71.7%, 1)` | CSS approximation of the one spring |
| Spring (JS / Flutter) | **stiffness 380, damping 32, mass 1** | Film-gate thumb, edge dimmers, sheet rise |

**The twelve named animations — implement each exactly:**

| # | Name | Property | From → To | Duration / easing | Notes |
|---|---|---|---|---|---|
| 1 | `house-down` | `--house` (0–1) driving wall luminance, sky opacity, bulb intensity, beam cone width | house 1 → 0; sky 1 → 0; bulbs 1 → 0.08 ("embers"); beam cone 12° → 38° | 900 ms `--ease-house` | **One** custom property tweened with `@property` on web; **one** `AnimationController` on Flutter feeding a `ColorTween` plus shader uniforms. A grep must prove there is no second tween |
| 2 | `house-up` | same, reversed | 0 → 1 | 900 ms `--ease-house` | Fires on leaving the Auditorium; the video fades out in the first 300 ms |
| 3 | `bulb-warmup` | per-letter `opacity` + halo alpha | 0 → 1.1 → 1.0 | 320 ms `--ease-out`, overshoot to 110 % for 2 frames | 60 ms stagger, left → right, **capped at 24 letters** (1.44 s) |
| 4 | `leader-sweep` | conic-gradient mask angle | 0° → 360° | 1000 ms linear per numeral, then a **66 ms black flash** | Driven by the real promise chain. A rejected promise **freezes the sweep at its current angle** |
| 5 | `aisle-reveal` / `aisle-hide` | `opacity` + `translateY` | 0/8 px → 1/0 · reverse | 120 ms `--ease-out` in · 480 ms `--ease-in-out` out after **2400 ms** idle | The folio survives auto-hide at 40 % opacity |
| 6 | `booth-rise` | sheet `translateY` 100 % → 0; content `opacity` 0 → 1 | | spring 380/32 (~420 ms); content 240 ms `--ease-out` delayed 120 ms | Drag-dismiss follows the finger 1:1; snaps on velocity > 300 px/s |
| 7 | `bias-lerp` | 5 gradient colour stops | previous sample → new sample | 600 ms linear (**1200 ms** under reduced motion) | Sampled every 500 ms desktop / 1000 ms Android |
| 8 | `beam-sway` + `dust-drift` | shader uniforms `angle`, `time` | ±1.5° sine over 9 s; 0.3 px/frame drift | continuous at 30 fps | Paused on `visibilitychange` **and during playback**. Reduced motion: static beam, no dust |
| 9 | `ticket-tear` | `clip-path` on the last ticket + `translateY(-12px) rotate(-6deg)`, opacity 1 → 0 | | 240 ms `--ease-out` | Medium haptic. **The strip count decrements *after* the tear completes** |
| 10 | `gate-snap` | film-gate thumb `x` | release position → nearest chapter/frame | spring 380/32 | Light haptic tick on landing |
| 11 | `sync-rule-snap` | ruler `translateX` | drag position → nearest 50 ms detent | 120 ms `--ease-out` | Selection haptic per detent |
| 12 | `match-bulb` | exit-sign bulb opacity + halo | 0 → 1 | 240 ms `--ease-out`, after the 2-pop | Fires **only** when `moviehash_match === true` |

**Reduced motion** (`prefers-reduced-motion: reduce` / `MediaQuery.disableAnimations`): beam static
at idle width, no dust, no parallax, no sky drift; bulbs and the leader become 240 ms opacity
crossfades (**the leader still shows the numeral and still stalls honestly**); sheets use 200 ms
opacity + 8 px translate; bias light is still allowed (it is colour, not motion) but lerps over
1200 ms; `house-down` becomes a 240 ms crossfade; auto-hide still works (it is a fade). A Flutter
test asserts that with `disableAnimations` **zero repeating tickers** remain alive.

### 3.6 The five signature interactions — step by step

#### 3.6.1 House lights down (the gif everyone posts)

1. A file is dropped, picked, or a Lobby card is tapped. **The Lobby does not navigate yet.**
2. `--house` tweens 1 → 0 over **900 ms** on `--ease-house`: the sky goes to black, the marquee bulbs
   fade to embers (0.08), wall luminance drops to 4 %, room tone ducks −12 dB.
3. At **300 ms** the beam swings from its idle 12° cone to fill the screen area (shader uniform
   `width`, same curve).
4. At **600 ms** the view transition starts (`document.startViewTransition` on web / a `Hero` on the
   picture element in Flutter): the tapped card's poster grows into the letterboxed picture position
   over 480 ms `--ease-out`.
5. The Threading leader begins on top of the dark room. Leaving the player reverses everything.
- **Sound:** a 900 ms sine sweep 200 → 60 Hz at −24 dB, synthesised — no asset. **Haptic:** none
  (the room is the feedback).
- **Why it delights:** the app visibly *makes room* for the film, and it costs one custom property.

#### 3.6.2 The leader — identification staged as the academy countdown

1. **"3" sweeps** (1000 ms linear) while the 128 KiB moviehash is read. The 16-hex hash prints
   beneath it in Geist Mono as it resolves (`8e245d9679d31e12`), then file size and container fps.
2. **"2" sweeps** while the subtitle search runs. On a hit with `moviehash_match === true`: a **33 ms
   1 kHz 2-pop at −18 dB**, the exit-sign **MATCH** bulb lights `--success`, medium haptic. On a
   filename-only hit the bulb stays dark and the row reads **`BY NAME · CHECK SYNC`** in `--warning`.
3. **"1" sweeps** while the download runs and the `.srt` is written beside the file. A ticket tears
   off the strip.
4. **66 ms black flash**, then the first frame; controls show once for 2400 ms.
5. **Any failure stalls the sweep on its numeral — no fake progress.** The fallback list (filename
   search → Subdl → manual pick → "Skip subtitles") slides in *beneath* the numeral as rows, without
   leaving the leader. A 429/406 stops "2" and the ticket strip explains the quota in one sentence.
- **Physics:** the sweep is a conic-gradient mask; each numeral is a promise, so a fast hit finishes
  in ~1.2 s total and a slow network shows exactly where it is waiting.
- **Why it delights:** the loading indicator is *true*, and it is the most cinematic object in film
  history.

The leader is drawn as: a circle with `radial-gradient(circle at 50% 50%, var(--bg-elevated) 0 96%,
transparent 96%)` and `inset 0 0 0 1px var(--border)`; two inset rings at 8 % and 22 %; a crosshair
of 1 px `--border` lines overshooting the circle by 6 %; the sweep as
`conic-gradient(from -90deg, color-mix(in oklch, var(--accent) 15%, transparent) 0deg <angle>,
transparent <angle>)`; a 1 px "hand" from centre to top rotated by the same angle with a
`linear-gradient(180deg, var(--accent), transparent)`; and the numeral in Big Shoulders 900,
`clamp(4rem, 15cqw, 8rem)`, tabular. **Stalled state:** numeral turns `--warning`, hand drops to
0.3 opacity, angle stops moving.

#### 3.6.3 Film gate seek with chapter detents

1. The seek bar is a **56 px strip of 35 mm film**: base `--bg-elevated` with a 1 px `--border`;
   the film body is `--surface` inset 14 px top and bottom; sprocket perforations are
   `repeating-linear-gradient(90deg, transparent 0 7px, var(--surface-2) 7px 10px, transparent 10px
   17px)` in 4 px strips at 5 px from each edge; the buffered range is `--surface-2`; the played
   range is `color-mix(in oklch, var(--accent) 20%, var(--surface-2))`; chapter marks are 1 px
   `--border-strong` verticals.
2. The playhead is **the frame in the gate**: a lit 16:9 window with a 1 px `--accent` edge, carrying
   the target timecode in 10 px mono that fades in only while dragging.
3. Dragging pulls a thumbnail through the gate (web: a hidden cloned `<video>` + canvas; native: a
   cached JPEG strip built by a second muted `hwdec=no` player after open — **if it stalls for > 3 s,
   silently fall back to a timecode-only gate**). The folio shows the target timecode live.
4. Detents at chapters (from mpv `chapter-list`) or every 5 minutes: crossing one gives a selection
   tick and the gate edge flashes to 100 % for one frame (`.gate.is-detent` → border `#fff`,
   background `color-mix(in oklch, var(--accent) 26%, transparent)`).
5. Release snaps to the nearest detent within a **6 px capture radius** using the 380/32 spring, with
   a light haptic. Dragging **up** off the strip switches to **FINE** (1/8 gain; the label `FINE`
   appears in mono; detents disabled) — VLC precision without a second control.
6. **Buffering** is the gate frame flickering at 2 Hz (`steps(1, end)` animation). Never a spinner.
7. **First run only:** the gate slides 12 px right and back once over `--dur-base` with the hint
   "drag the gate". Remember that it fired.

#### 3.6.4 The sync rule (subtitle delay)

1. Beside the gate sits a small mono readout `SYNC +0.00`. Tap it (or press `J`/`K`) and a ruler
   appears above the controls: mono numerals from `−2.00` to `+2.00`, a tick every 50 ms (majors
   taller and `--ink-faint`), **sliding horizontally under a fixed tungsten caret** at 50 %. The
   caret is a 1 px `--accent` line with `--bulb-halo` and a 7 px round cap.
2. Drag the ruler; it snaps to 50 ms detents with a selection haptic. `J`/`K` step ∓50 ms;
   `Shift` steps 500 ms. The value is written live to mpv `sub-delay` (native) or re-emits the
   shifted VTT (web) and prints in the folio as `SUB +0.35`.
3. The offset is remembered **per moviehash** and shown as a small `±0.35` chip beside the title in
   the Lobby rail.
4. Reset is a long-press on the readout (or `Shift+J+K`): the ruler glides home on the spring.
- **A golden regression to avoid:** the caret is fixed and the **ruler** moves. A screenshot showing
  a moved caret is a bug.

#### 3.6.5 Marquee warm-up and the ticket strip

1. When identification returns feature details, the film's title is spelled onto the lobby marquee
   letter by letter (`bulb-warmup`, 60 ms stagger, capped at 24 letters). It stays lit as
   **NOW SHOWING** until another film replaces it. At local night the bulbs carry a **0.5 % random
   flicker** (seeded RNG — tests pass `Random(8)`); by day they are off and the letters are painted.
2. Each subtitle download **tears one ticket** from the perforated strip (`ticket-tear`, medium
   haptic, a short paper-rip at −20 dB). The strip reads `7 OF 10 TONIGHT · RESETS 00:00 UTC` — from
   the real API response, never a constant. At **2 left** the strip turns crimson
   (`repeating-linear-gradient(180deg, var(--accent-2) 0 4px, rgba(0,0,0,.5) 4px 5px)`, label in
   `--accent-2-lit`) and offers "Sign in at the ticket office (free, more tickets)" or "Use the
   Subdl slot".
3. An unknown file: the marquee spells the cleaned filename and **one bulb stays dark**.
- **Why it delights:** the sign remembers what you watched, and the app's ugliest constraint becomes
  a small ritual instead of an error.

### 3.7 Textures, materials and how to build each one

| Element | Web recipe | Flutter recipe |
|---|---|---|
| **Beam** | A `div` with `background: radial-gradient(130% 100% at 50% -14%, color-mix(in oklch, var(--accent) 15%, transparent) 0%, color-mix(in oklch, var(--accent) 6%, transparent) 34%, transparent 66%)`, `clip-path: polygon(46% -6%, 54% -6%, calc(50% + var(--beam-w)) 108%, calc(50% - var(--beam-w)) 108%)`, `mix-blend-mode: screen`. `--beam-w` animates 16 % → 62 % as `--house` falls. Optional OGL/GLSL-ES upgrade | `assets/shaders/beam.frag` (GLSL 460 → Impeller): soft cone in `--accent` at 8–14 % alpha, **3-octave value noise**, ~200 dust sprites. Uniforms: `angle`, `width`, `time`, `house`, plus the 5 bias stops. **DPR capped 1.5 desktop / 1.0 Android.** Paused during playback and on `visibilitychange` |
| **Beam fallback** | The static radial gradient above with no dust | On `FragmentProgram` failure or reduced motion: a `CustomPainter` radial gradient. **Never throw** |
| **Dust** | A `<canvas>` with ~200 sprites drifting 0.3 px/frame at 30 fps; hidden entirely in Matinee and reduced motion | Part of `beam.frag` |
| **Grain** | `background-image: url("data:image/svg+xml,…feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch'…")` at `background-size: 140px 140px`, `mix-blend-mode: overlay`, `opacity: var(--grain-opacity)` | A 256 px tiled noise PNG (generated, CC0) or `grain.frag` |
| **Grain scope** | **Lobby and sheets only. `--grain-opacity: 0` in the Auditorium.** Never over the picture, never in reduced motion | same |
| **Sky band** | Absolutely positioned, `inset: 0 0 auto 0; height: 46%`, `linear-gradient(180deg, var(--sky-a) 0%, var(--sky-b) 52%, transparent 100%)`, `opacity: calc(0.14 + 0.86 * var(--house))` | `Container` with a `LinearGradient`, opacity driven by `houseProvider` |
| **Wall glow (bias light)** | Three positioned divs: left `radial-gradient(78% 62% at 100% 46%, var(--glow-l), transparent 72%)` at 38 % width, right mirrored, top `radial-gradient(62% 120% at 50% 100%, var(--glow-t), transparent 74%)` at 34 % height. Stop alphas ramp **14 % → 8 % → 4 % → 2 % → 0 %** | `CustomPainter` with a `RadialGradient` from the 5 stops; the beam shader reads the same stops so the cone picks up the film's colour |
| **Booth glass** | `background: var(--booth-glass); backdrop-filter: blur(24px);` + a 1 px `--border` top edge. **Only over a paused frame — never over moving video** | `BackdropFilter` + `ImageFilter.blur(24)` |
| **Bulb** | 5 px circle, `--radius-full`, `background: var(--accent)`, `box-shadow: var(--bulb-halo)`, `opacity: calc(0.08 + 0.92 * var(--house))`. Off state: `--surface-2` with a 1 px `--border-strong` ring. Green (exit sign): `--success` with a matching halo | same values in a small `Bulb` widget |
| **Crimson trim** | A 1 px `--accent-2` line under the marquee box, `opacity: calc(0.3 + 0.7 * var(--house))` | 1 px `Container` |
| **Marquee box** | `background: color-mix(in oklch, var(--bg-elevated) 70%, transparent)`, 1 px `--border`, `--radius-sm`, `--shadow-2`, centred, `width: min(760px, 100%)` | same |

### 3.8 Iconography

Lucide (ISC) at **1.5 px stroke, 20 px**, coloured `--ink-muted` idle / `--accent` active. The subset:
`play`, `pause`, `captions`, `audio-lines`, `maximize-2`, `picture-in-picture-2`, `repeat` (A–B),
`gauge` (speed), `settings-2`, `ticket`, `ear`, `x`, `arrow-left`, `search`.

**Skip marks are text-marks, not icons:** `◀10` and `10▶` set in Geist Mono. Transport marks are
**glyph-plus-halo, never buttons with backgrounds** — the only filled control in the whole app is the
play/pause mark and the Open disc.

**No illustration. No bitmap assets.** The room is drawn by light. The only pictorial elements — the
marquee, the film strip, the leader — are CSS/SVG/shader. The only imagery is TMDB posters (optional)
or frame grabs from the user's own file. No stock photography anywhere.

### 3.9 Sound and haptics

All sound is optional, **off during playback**, respects the OS silent switch, and hangs off one
"Sounds" bulb in the Ticket Office. Web: Howler.js sprites + Web Audio synthesis. Flutter:
`flutter_soloud`.

| Event | Sound | Source |
|---|---|---|
| Lobby room tone | 16-bit projector-motor loop, −30 dB, high-passed 120 Hz, starts on first gesture, mutable | CC0 (freesound CC0 filter "projector loop" / Kenney) |
| House lights down | 900 ms sine sweep 200 → 60 Hz at −24 dB | synthesised, no asset |
| 2-pop (hash match / subtitle attached) | 1 kHz sine, 33 ms, −18 dB | synthesised |
| Detent (gate chapter, sync rule) | 4 ms filtered-noise click | synthesised |
| Ticket tear | short paper rip, −20 dB | CC0 or synthesised noise burst |
| Sheet rise / dismiss | none | — |

**Haptics (native only — the web tier has none):** `lightImpact` when controls reveal;
`selectionClick` per gate detent, sync-rule detent and frame-step; `mediumImpact` on hash match, on
subtitle attach, and on ticket tear; **`heavyImpact` never**; a notification vibrate **only** on
quota exhaustion. Never vibrate during playback for anything else. One "Haptics" bulb, default on
for phone.

### 3.10 Accessibility rules (all are release gates)

- **Contrast:** every text token ≥ 4.5 : 1 on its allowed surfaces per the §3.2 tables.
  `--ink-faint` and `--danger` are **≥ 18 px** on `--surface-2`. `--accent-2` is **never a text
  colour on dark** — use `--accent-2-lit`. Controls over the picture always sit on the wall
  (`--bg`), **never on the video**, and use `--ink`/`--accent` on `#000` (≥ 13 : 1).
- **Subtitle default style:** Noto Sans, white, **2 px black outline + 40 % shadow** (libass
  `BorderStyle=1`), asserted by reading back the mpv `sub-*` properties.
- **Focus:** a 2 px `--focus` ring at 2 px offset on **every** interactive element including
  transport marks and the gate; visible in both palettes; never removed on `:focus-visible`.
- **Targets:** ≥ 44 × 44 px; gate 56 px on phone; edge dimmers 48 px wide. Aisle lights are
  decorative and non-interactive.
- **Screen readers:** the leader announces **once per phase** ("Reading file", "Searching subtitles",
  "Downloading English subtitles", "Subtitles attached, in sync") via `aria-live="polite"` /
  `SemanticsService.announce` — **never per sweep frame**. The marquee announces the final title
  once, not per bulb. The film gate is `role="slider"` with `aria-valuetext` as a timecode. The sync
  rule is a slider with `aria-valuetext="plus 0.35 seconds"`. Toggle bulbs are `role="switch"`. The
  ticket strip has `aria-label="7 of 10 downloads left tonight"`. Decorative bulbs, beam and dust are
  `aria-hidden` / excluded from semantics.
- **Keyboard:** everything reachable; the `?` cue sheet lists every shortcut and is **generated from
  `design/cue-sheet.json`**, which is the single source of truth (a test fails if the JSON and the
  app disagree in either direction). `Esc` always goes exactly one lighting state up.
- **Language:** UI in English; subtitle language names as ISO code + English exonym.

### 3.11 Android chrome

- **Edge-to-edge:** `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`; transparent
  status and navigation bars with **light icons in the Auditorium, dark icons in the Matinee Lobby**.
  `SafeArea` for the marquee (top) and controls (bottom); in landscape the picture extends under the
  cutout (`LayoutMode.shortEdges`).
- **Playback:** `SystemUiMode.immersiveSticky` while controls are hidden; keep-screen-on via
  `wakelock_plus`; per-app brightness via `screen_brightness`, **restored on dispose**.
- **Predictive back:** `android:enableOnBackInvokedCallback="true"`; the Booth sheet and the
  Threading screen register back callbacks so the system preview shows the room, not a blank page.
  The horizontal scrub gesture starts **24 px inside** the left/right edges so it never fights the
  back gesture.
- **Splash:** `flutter_native_splash` with background `#07060A` and a single lit bulb (72 dp)
  centred; Android 12+ `windowSplashScreenAnimatedIcon` uses the bulb with a 300 ms warm-up.
- **Adaptive icon:** foreground = the marquee box (crimson 1 px trim, one lit bulb, `M` in Big
  Shoulders 900 in `--ink`) on a transparent layer; background `#07060A`; **monochrome layer = the
  bulb silhouette** (themed icons must stay legible at 48 dp).
- **Status/nav colours:** `#07060A` everywhere the system tints, matching `theme_color` in the web
  manifest.

### 3.12 The token file (generate, never hand-write)

`scripts/tokens.mjs` owns one source of truth and emits **both** `web/src/styles/tokens.css` and
`lib/theme/tokens.dart`. CI runs `node scripts/tokens.mjs && git diff --exit-code` on both outputs,
so a hand edit fails the build.

```css
/* web/src/styles/tokens.css — GENERATED by scripts/tokens.mjs. Do not edit. */
:root {
  /* ---- Auditorium (default, dark) ---- */
  --bg: #07060A;
  --bg-elevated: #120E15;
  --surface: #1B1620;
  --surface-2: #26202B;
  --ink: #F3E9DA;
  --ink-muted: #A89C8C;
  --ink-faint: #8C8276;
  --accent: #FFC56E;
  --accent-ink: #1A1006;
  --accent-2: #A3252F;
  --accent-2-lit: #E0525C;
  --success: #5FD48A;
  --warning: #F5A05F;
  --danger: #E5484D;
  --border: #2A2330;
  --border-strong: #3D3446;
  --focus: #FFD68A;

  /* semantic / derived */
  --picture-bg: #000000;
  --wall-glow: radial-gradient(60% 60% at 50% 50%, color-mix(in oklch, var(--focus) 6%, transparent), transparent);
  --bulb-halo: 0 0 6px 1px color-mix(in oklch, var(--accent) 55%, transparent);
  --booth-glass: color-mix(in oklch, var(--bg-elevated) 78%, transparent);
  --glass-blur: 24px;
  --sky-dawn: #3A2A2E; --sky-day: #2A2E3A; --sky-dusk: #2F2438; --sky-night: #0B0A10;
  --house: 1;                 /* 1 = house up, 0 = dark */
  --grain-opacity: 0.04;      /* lobby + sheets only; 0 in the auditorium */

  /* ---- Typography ---- */
  --font-display: "Big Shoulders Display Variable", "Big Shoulders Display", Impact, "Arial Narrow", sans-serif;
  --font-body: "Geist Variable", Geist, system-ui, "Segoe UI", sans-serif;
  --font-mono: "Geist Mono Variable", "Geist Mono", ui-monospace, Consolas, monospace;
  --text-xs: 0.75rem;  --text-sm: 0.875rem; --text-base: 1rem;
  --text-lg: 1.125rem; --text-xl: 1.375rem; --text-2xl: 1.75rem; --text-3xl: 2.25rem;
  --text-4xl: clamp(3rem, 6vw, 4rem);
  --text-5xl: clamp(5rem, 14vw, 9rem);
  --leading-tight: 1.05;
  --leading-body: 1.5;
  --tracking-display: 0.06em;
  --tracking-display-lg: 0.02em;
  --tracking-label: 0.08em;

  /* ---- Spacing ---- */
  --space-1: 4px;  --space-2: 8px;  --space-3: 12px; --space-4: 16px;
  --space-5: 20px; --space-6: 24px; --space-7: 32px; --space-8: 40px;
  --space-9: 48px; --space-10: 64px; --space-11: 80px; --space-12: 96px;

  /* ---- Radius ---- */
  --radius-sm: 4px; --radius-md: 8px; --radius-lg: 12px; --radius-xl: 20px; --radius-full: 9999px;

  /* ---- Elevation (one light source, above and behind) ---- */
  --shadow-1: inset 0 1px 0 rgba(255,255,255,.04), 0 2px 6px rgba(0,0,0,.5);
  --shadow-2: inset 0 1px 0 rgba(255,255,255,.05), 0 8px 24px rgba(0,0,0,.55);
  --shadow-3: inset 0 1px 0 rgba(255,255,255,.06), 0 24px 56px rgba(0,0,0,.65);

  /* ---- Motion ---- */
  --dur-fast: 120ms; --dur-base: 240ms; --dur-slow: 480ms; --dur-house: 900ms;
  --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --ease-house: cubic-bezier(0.7, 0, 0.3, 1);
  --ease-spring: linear(0, 0.006, 0.025 2.8%, 0.101 6.1%, 0.539 18.9%, 0.721 25.3%, 0.849 31.5%, 0.937 38.1%, 0.968 41.8%, 0.991 45.7%, 1.006 50.1%, 1.012 55.4%, 1.011 62.6%, 1.006 71.7%, 1);
  --spring-stiffness: 380; --spring-damping: 32; --spring-mass: 1;

  /* ---- Layout ---- */
  --page-max: 1280px; --gutter: 24px; --margin-phone: 20px;
  --target-min: 44px; --gate-height: 56px; --controls-idle: 2400ms;

  color-scheme: dark;
}

/* Matinee — Lobby, Booth, Ticket Office only; never while a file is open */
[data-theme="matinee"] {
  --bg: #F1E8D8; --bg-elevated: #F8F2E6; --surface: #E8DECB; --surface-2: #DDD1BC;
  --ink: #2A2226; --ink-muted: #5E5350; --ink-faint: #605651;
  --accent: #7F4800; --accent-ink: #FFF6E6;
  --accent-2: #A3252F; --accent-2-lit: #A3252F;
  --success: #186639; --warning: #8A4B00; --danger: #A8231C;
  --border: #D6CAB5; --border-strong: #B9AB93; --focus: #7A4A00;
  --sky-dawn: #F5C9A8; --sky-day: #C9D6E8; --sky-dusk: #C8A9D6; --sky-night: #1A1622;
  --bulb-halo: none;
  --shadow-1: 0 1px 2px rgba(42,34,38,.12);
  --shadow-2: 0 6px 18px rgba(42,34,38,.16);
  --shadow-3: 0 18px 40px rgba(42,34,38,.22);
  --grain-opacity: 0.03;
  color-scheme: light;
}

@property --house { syntax: "<number>"; inherits: true; initial-value: 1; }

@media (prefers-reduced-motion: reduce) {
  :root { --dur-house: 240ms; --ease-house: var(--ease-in-out); --ease-spring: var(--ease-out); }
}
```

The Dart mirror exposes `Tokens.bg`, `Tokens.accent`, … as `Color`; `Tokens.durHouse =
Duration(milliseconds: 900)`; `Tokens.easeHouse = Cubic(0.7, 0, 0.3, 1)`; `Tokens.spring =
SpringDescription(mass: 1, stiffness: 380, damping: 32)`; and a `Tokens.textScale` map. Fonts are
registered in `pubspec.yaml` as `Big Shoulders Display`, `Geist`, `Geist Mono`, `Noto Sans`.

---

## 4. Screens

Legend: `▓` lit tungsten · `░` velvet surface · `▒` booth glass · `·` bulbs · `[ ]` touch target.
Wireframes are portrait phone unless labelled.

### 4.1 Lobby (Home / Now Showing)

**Purpose:** the room you come home to. It remembers what you last watched, tells you the time of
day with its sky, and gives you exactly two ways in: drop a file on the doors, or press Open.

```
PHONE (portrait)                              DESKTOP (Windows, frameless, Mica in Lobby only)
┌──────────────────────────────┐              ┌───────────────────────────────────────────────────────────┐
│ sky band (time of day) ····· │              │ ····· THE THIRD MAN ····· 1949 ·····            · · ·     │  <- marquee box = title bar
│ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │              │ ───────────── crimson 1px trim ───────────────────────────│
│ ┃  ·  THE THIRD MAN  ·     ┃ │  marquee     │ sky band                                                  │
│ ┃      1949 · NOW SHOWING  ┃ │              │                                                           │
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │              │   ░░░░░░░   ░░░░░░░   ░░░░░░░   ░░░░░░░   ░░░░░░░         │
│ ───── crimson 1px trim ───── │              │   ░poster░  ░poster░  ░poster░  ░poster░  ░poster░        │
│                              │              │   ░ 2:3  ░  ░      ░  ░      ░  ░      ░  ░      ░        │
│  ~~~~~~ horizon 62% ~~~~~~~  │              │   ▓▓▓░░░░   ▓▓▓▓▓░░   ░░░░░░░   ▓░░░░░░   ░░░░░░░  <- resume sprocket
│  ░░░░░░░ ░░░░░░░ ░░░░░░░ ░░  │  velvet rail │   The Third Man  Chungking…  Paddington  …                │
│  ░ 3:4 ░ ░ 3:4 ░ ░ 3:4 ░ ░░  │  snap-scroll │   1949 · 1h33 · MKV · EN ✓ · ±0.35                        │
│  ░     ░ ░     ░ ░     ░ ░░  │              │                                                           │
│  ▓▓▓░░░░ ▓▓▓▓▓░░ ░░░░░░░ ░░  │  resume      │              ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐                │
│  Third Man Chungk… Paddi…    │              │              │  drop a print here  ·  or  Open │         │  <- beam idle cone behind
│                              │              │              └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                │
│         ┌ ─ ─ ─ ─ ─ ┐        │  doors/drop  │                                                  ♪ ◐ ⚙    │  <- room tone, theme, settings
│         │  ▌ ▐   ▌ ▐ │  [▓▓] │  Open disc   │ Subtitles by OpenSubtitles.com · TMDB logo + notice       │
└──────────────────────────────┘              └───────────────────────────────────────────────────────────┘
```

**The candidate list is drawn in scoring order and is never filtered.** Those four rows are the frozen fixture `test/fixtures/os/candidates-third-man.json` in the only order the scorer can produce (§6.4): **A** `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE`, hash-matched, 12 431 dl → **1414.09** · **D** the same release with no hash, 51 000 dl → **414.71** · **C** `The.Third.Man.1949.BluRay-AMIABLE`, 902 dl, HI, 25 fps → **232.96** · **B** `The.Third.Man.1949.1080p.WEB-DL.H264-NTb`, 4 102 dl, HI → **63.61**. D ranking above B is exactly the case **R4** protects: `x264` and `H264` are different tokens, so a same-group BluRay encode beats a WEB-DL even with no hash. Drawing B above C or D shows a state the scorer cannot produce — the same order must hold in `design/preview.html`, in the widget goldens and in DESIGN §9.2.

**Component tree**

```
Lobby
├── SkyBand            (time-of-day gradient, opacity = 0.14 + 0.86·house)
├── Beam               (idle 12° cone; widens on drag-over and on house-down)
├── Dust               (canvas / shader; hidden in Matinee + reduced motion)
├── Grain              (opacity var(--grain-opacity))
├── LobbyTop
│   ├── MarqueeSign  ── BulbRow ×2 · MarqueeTitle (display 900) · MarqueeMeta (year · NOW SHOWING)
│   │                    └── crimson 1px trim (::after)
│   └── SkyLine       (label "DUSK · 19:42 · THE HOUSE IS OPEN" · label "7 PRINTS")
├── LobbyMid
│   ├── RailHead      (label "Now showing & recent" · mono hint "DRAG · TAP TO PROJECT")
│   ├── Rail          role=list, horizontal snap-scroll
│   │   └── NowShowingCard ×n
│   │        ├── Poster (TMDB w342/w500) OR frame-grab at 25 % luminance
│   │        ├── ResumeSprocketTrack (fill = position/duration)
│   │        ├── Title (display) · Meta (year · runtime · container)
│   │        └── Chips: `EN ✓` · `±0.35` · `PRINT MISSING`
│   ├── EmptyState    (one sentence, replaces the rail)
│   └── Doors         (drop target = the whole dark area; dashed --border-strong frame)
└── LobbyFoot
    ├── AttributionLine ("Subtitles by OpenSubtitles.com" + LGPL + OFL + MIT)
    ├── LampBulbs      (room tone · theme · ticket office — each a role=switch bulb)
    └── OpenDisc       (64 px tungsten, --radius-full, bottom-right thumb zone)
```

Desktop adds a `?` cue-sheet overlay and a two-layer parallax (walls ±6 px, screen 0) capped at ≤ 1°.

**States**

| State | Rendering |
|---|---|
| **Empty** | Marquee reads `MARQUEE`; the rail is replaced by one sentence — *"The house is empty. Drop a film on the doors, or press Open."*; the beam idles |
| **Loading library** | Cards render as 25 %-lit frames with a 240 ms shimmer. **No spinner** |
| **Error (file gone)** | The card dims to 40 % with `PRINT MISSING` in mono and a `Locate` link |
| **Success** | A card's resume sprocket track fills |
| **Drag-over** | The beam widens; the doors outline brightens to `--accent` |

**Gestures.** Horizontal snap-scroll on the rail; **tap a card = house lights down**; long-press a
card = context menu (Play from start · Find subtitles · Remove); pull-down on the rail = rescan
library (Android); predictive back exits the app.

**Transition out:** `house-down` (900 ms) → view transition of the tapped poster into the letterboxed
picture position → Threading.

### 4.2 Threading (Identify and Subtitle)

**Purpose:** to be honest. This screen is the loading indicator, and it never lies about which phase
it is in.

```
PHONE (portrait, dimmed room)                 DESKTOP
┌──────────────────────────────┐              ┌───────────────────────────────────────────────────────────┐
│ REEL 01 · THREADING          │  folio       │ REEL 01 · THREADING                            Skip subs │
│                              │              │                                                           │
│          ╭────────╮          │              │      ╭──────────╮      EN ✓MATCH BluRay.x264-AMIABLE [▓]  │
│         ╱    ▓▓    ╲         │  leader      │     ╱     ▓▓     ╲     ░ 12 431 dl · 23.976 fps · not HI  │
│        │     ▓▓     │        │  sweep       │    │      ▓▓      │    ░ EN  BluRay.x264-AMIABLE 51 000 dl│
│        │  ▓▓▓▓▓▓▓▓  │        │  numeral 2   │    │   ▓▓▓▓▓▓▓▓   │    ░ HI  BluRay-AMIABLE 902 dl · 25fps│
│         ╲          ╱         │              │     ╲            ╱     ░ EN  WEB-DL.H264-NTb 4 102 dl · HI│
│          ╰────────╯          │              │      ╰──────────╯      ░ Also from Subdl ─────────────────│
│  8e245d9679d31e12 · 1.42 GB  │  mono        │  8e245d9679d31e12 · 1.42 GB · 23.976 fps                  │
│  23.976 fps                  │              │                                                           │
│ ──────────────────────────── │              │  ▐ 7 OF 10 TONIGHT ▐▐▐▐▐▐▐ · resets 00:00 UTC             │
│ ░ ● MATCH  EN  x264-AMIABLE  │  candidates  └───────────────────────────────────────────────────────────┘
│ ░   12 431 dl · 23.976 · —HI │
│ ░   EN  x264-AMIABLE · 51 000│
│ ░   HI  BluRay-AMIABLE · 25  │
│ ░   EN  WEB-DL-NTb · 4 102 dl│
│ ──────────────────────────── │
│ ▐ 7 OF 10 TONIGHT ▐▐▐▐▐▐▐    │  ticket strip
│ [ Skip subtitles ]           │
└──────────────────────────────┘
```

**Component tree**

```
Threading
├── Beam (wide, --beam-w 52%)
├── Folio        ("REEL 01 · THREADING")           + SkipLink ("Skip subtitles")
├── ThreadGrid   (desktop: 360px leader | 1fr candidates; phone: stacked)
│   ├── LeaderWrap
│   │   ├── Leader   (rings · crosshair · conic sweep · hand · numeral 3/2/1)
│   │   ├── PhaseLabel (uppercase label in --accent, aria-live=polite)
│   │   └── HashLine   (mono: `8e245d9679d31e12 · 1.42 GB · 23.976 fps`, ss01 slashed zero)
│   └── Candidates   role=radiogroup
│       ├── CandidateRow ×n  (language code mono · MATCH bulb · release name · downloads tabular ·
│       │                     fps · HI ear glyph; the auto-picked row is lit and aria-checked)
│       ├── SubdlSection     (only when enabled and reached)
│       ├── ManualSearchField (appears on stall)
│       └── SentenceBanner   (one plain sentence; never a red fill)
└── TicketStrip  (perforated tickets · mono label · sr-only aria-label)
```

**States**

| State | Rendering |
|---|---|
| **Hashing** | Numeral "3" sweeping; phase label "Reading the print"; hash dots resolving into hex |
| **Searching** | "2" sweeping; "Searching subtitles" |
| **Downloading** | "1" sweeping; "Downloading English subtitles"; a ticket tears |
| **Match** | Green MATCH bulb + the 2-pop; the top row lit |
| **By name** | `BY NAME · CHECK SYNC` in `--warning`; the MATCH bulb stays dark |
| **Stalled** | The sweep is **frozen at its current angle**, the numeral turns `--warning`, and the fallback rows slide in beneath it. Never a reset to 0, never a jump to full |
| **Quota** | The strip turns crimson: *"No tickets left tonight — sign in for more, or use the Subdl slot."* |
| **Offline** | "2" stalls: *"You're offline — playing without new subtitles."* with "Play without subtitles" lit |
| **File < 128 KiB** | **No error at all.** "3" completes normally, the hash is skipped, "2" starts with a filename query |

**Gestures.** Tap any row overrides the auto-pick (and cancels an in-flight download); swipe down /
predictive back = skip; on desktop `Esc` skips and `Enter` accepts.

### 4.3 Auditorium (Player)

**Purpose:** watch the film. Chrome exists only while you need it.

```
PHONE (landscape, controls shown)                          DESKTOP (frameless; folio = title bar)
┌────────────────────────────────────────────────┐         ┌───────────────────────────────────────────────────────────┐
│ REEL 01 · 01:12:44 · −01:28:19        ● ✓     ▏│         │ REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19    · · ·    │
│▕                                              ▏│         │                                                           │
│▕▓        ┌────────────────────────────┐      ▓▏│ edge    │  wall glow  ┌───────────────────────────────────┐  wall   │
│▕▓        │                            │      ▓▏│ dimmers │             │                                   │  glow   │
│▕▓        │        the picture (#000)  │      ▓▏│ bright/ │             │          the picture (#000)       │         │
│▕▓        │      subtitles by libass   │      ▓▏│ volume  │             │        subtitles by libass        │         │
│▕         └────────────────────────────┘       ▏│         │             └───────────────────────────────────┘         │
│  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  │ aisle   │  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  │
│ ▯▯▯▯▯▯▯▯▯▯▯▯[▓▓▓]▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯ │ gate    │ ▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯[▓▓▓▓]▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯ │
│ [◀10] [ ▶ ] [10▶]  SYNC +0.00  [CC] [♪] [⛶] [⧉]│         │ [◀10][ ▶ ][10▶] SYNC +0.00 [CC][♪][1.0×][A–B][⛶][?] SAVED│
└────────────────────────────────────────────────┘         └───────────────────────────────────────────────────────────┘
Portrait phone: the picture sits at the top (16:9, letterboxed #000), wall glow around it, folio
above, gate + controls in the bottom 22 % (thumb zone).
```

**Component tree**

```
Auditorium
├── Walls ×3          (bias-light radial gradients: left, right, top)
├── Folio             (REEL · title · timecode · −remaining · SUB ±x.xx suffix)  [+ 3 window bulbs on Windows]
├── PicArea
│   └── Picture (#000)  ── libass/JASSUB subtitle layer · EdgeDimmer L/R · SkipFlash (−10/+10) · GateFlash
├── AisleLights       (row of 5 px tungsten dots brightening toward the pointer/thumb)
├── Controls          (auto-hide after 2400 ms)
│   ├── SyncRule      (ruler above the gate, hidden until invoked)
│   ├── FilmGate      role=slider  (strip · buffered · played · chapters · perforations · frame-in-gate)
│   └── Transport     [◀10] [play/pause filled] [10▶] · SYNC readout · spacer ·
│                     [CC] [♪] [speed] [A–B] [fullscreen] [PiP (Android)] [? (desktop)] · ExitSign bulb
├── BoothSheet        (rises to 70 %, see §4.4)
└── CueSheet          (desktop `?` overlay, mono two-column, generated from cue-sheet.json)
```

**States**

| State | Rendering |
|---|---|
| **Idle-hidden** | All chrome gone after 2400 ms; the folio remains at 40 % opacity |
| **Paused** | Aisle lights hold at 60 %, the beam narrows 10 %, the wall glow **freezes** (no sampling, no CPU) |
| **Buffering** | The gate's frame flickers at 2 Hz. **No spinner** |
| **No subtitle** | The CC mark is hollow |
| **Error** | The picture area goes to `--bg` with one sentence in `--ink` and actions beneath. **Never a red banner** — a widget test scans the rendered frame and fails if pixels within ΔE 10 of `--danger` cover > 2 % |
| **PiP (Android)** | All chrome removed; the folio text goes into the PiP title |

**Gestures (Android):** single tap = toggle controls; double-tap the left/right third = ∓10 s (the
gate visibly jumps and a `−10`/`+10` flash appears); long-press = 2× while held (the folio reads
`2.0×`); vertical drag on the left edge = brightness, right edge = volume, drawn as vertical filament
bars with a mono readout; horizontal drag anywhere on the picture = scrub with the gate following
(starting 24 px inside the edges); pinch = fit/fill; predictive back = house lights up.

**Keyboard (Windows) — the full map, mirrored in `design/cue-sheet.json`:**

| Key | Action | Key | Action |
|---|---|---|---|
| `Space` | Play / pause | `J` / `K` | Sync ∓50 ms (`Shift` = 500 ms) |
| `←` / `→` | ∓5 s | `,` / `.` | Frame step |
| `Shift+←` / `Shift+→` | ∓30 s | `L` | A–B loop |
| `↑` / `↓` | Volume | `[` / `]` | Speed (pitch-corrected) |
| `F` | Fullscreen | `P` | Picture-in-picture |
| `S` | Subtitle tracks | `?` | Cue sheet |
| `A` | Audio tracks | `Esc` | Back one lighting state |

### 4.4 Subtitle Booth (sheet)

**Purpose:** everything about subtitles, over a paused frame, without leaving the film.

```
PHONE (rises to 70 %, booth glass over the paused frame)   DESKTOP (popover 420 px, anchored to CC)
┌──────────────────────────────┐                          ┌──────────────────────────┐
│  (paused frame visible)      │                          │ TRACKS                   │
│ ▒▒▒▒▒▒▒▒▒▒ ─── ▒▒▒▒▒▒▒▒▒▒▒▒ │  handle                  │ ● EN  Marquee · synced ✓ │
│ ▒ TRACKS                    ▒│                          │   EN  embedded (PGS)     │
│ ▒ ● EN  Marquee · synced ✓  ▒│  attached                │   Off                    │
│ ▒   EN  embedded (PGS)      ▒│                          │ ─────────────────────── │
│ ▒   Off                     ▒│                          │ STYLE  A  A  A  ▢ outline│
│ ▒ ───────────────────────── ▒│                          │ POSITION  ▁ ▂ ▃          │
│ ▒ STYLE   A  A  A   outline ▒│  live on the frame       │ ─────────────────────── │
│ ▒ POSITION  ▁  ▂  ▃         ▒│                          │ SYNC ─2.00 ─1.00 ▲ +1.00 │
│ ▒ ───────────────────────── ▒│                          │ ─────────────────────── │
│ ▒ SYNC  ─1.00  ▲ +0.00 +1.00▒│  sync rule               │ Find another print  ▐7▐  │
│ ▒ ───────────────────────── ▒│                          └──────────────────────────┘
│ ▒ [ Find another print ]  ▐7▐│  re-search + tickets
└──────────────────────────────┘
```

**Components:** track list (external / embedded / off, each row with a dot, a title and a status
chip such as `synced ✓` in `--success` or `BITMAP` for PGS); style presets (size S/M/L, outline
on/off — applied **live** via mpv `sub-font-size`/`sub-border-size` or JASSUB overrides); position
(bottom / lower-third / top); the sync rule; a search field + "Find another print" (re-runs the
filename and Subdl rungs **without closing the sheet**); the ticket count; a link to language and HI
preferences.

**States:** *Loading* (rows shimmer 240 ms) · *Empty* (only embedded/off plus "Find a print") ·
*Quota* (the button reads "No tickets — Subdl slot") · *Success* (the row gains `synced ✓`).

**Gestures:** the drag handle follows the finger 1:1; velocity > 300 px/s dismisses; predictive back
closes; the body scrolls internally; **the sheet never exceeds 70 % so the frame stays visible**.

### 4.5 Ticket Office (account, settings, attribution)

**Purpose:** the one settings screen. It is also where the licence trail is *typeset*, not hidden.

```
PHONE                                          DESKTOP (two columns)
┌──────────────────────────────┐               ┌───────────────────────────────────────────────────────────┐
│ ‹ TICKET OFFICE              │               │ ‹ TICKET OFFICE                                           │
│ ░ OPENSUBTITLES              │               │ ░ OPENSUBTITLES             ░ PROJECTION                  │
│ ░ signed in as rahul  ▐7▐▐▐▐ │  ticket strip │ ░ signed in · ▐7 OF 10▐▐▐▐  ░ Hardware decode   auto-safe │
│ ░ resets 00:00 UTC · sign out│               │ ░ Languages  EN · HI · TA   ░ Interpolation     off       │
│ ░ Languages  EN · HI · TA    │               │ ░ Hearing-impaired  prefer  ░ Shaders (Win)    Anime4K ▾  │
│ ░ Hearing-impaired   prefer  │               │ ░ Save beside file   on     ░ Subtitle font    Noto Sans  │
│ ░ Save beside file      on   │               │ ░ Subdl slot  key ····· on  ░ Indic fonts     download    │
│ ░ Subdl slot   key ····· on  │               │ ░ AMBIENCE                  ░ ABOUT                       │
│ ░ AMBIENCE                   │               │ ░ Room tone on · Bias light on · Beam on · Matinee auto   │
│ ░ Room tone            on    │               │ ░ Sounds on · Haptics on                                  │
│ ░ Bias light (Android) off   │               │ ░ Subtitles by OpenSubtitles.com                          │
│ ░ Beam                 on    │               │ ░ [TMDB logo] This product uses TMDB and the TMDB APIs but│
│ ░ Matinee lobby      auto    │               │ ░ is not endorsed, certified, or otherwise approved by TMDB│
│ ░ Sounds · Haptics    on     │               │ ░ libmpv · ffmpeg · libass — LGPL notices + source links  │
│ ░ ABOUT · attribution        │               │ ░ Fonts: Big Shoulders, Geist, Noto Sans (OFL) · MIT app  │
└──────────────────────────────┘               └───────────────────────────────────────────────────────────┘
```

**Components:** sign-in row (underline-only username/password inputs; on submit the ticket stub
"tears" in; **the JWT goes to secure storage and the password is never kept**); ticket strip;
language chips (max 3, ordered); toggle bulbs (lit = on, `role="switch"`); select rows; **Export
library** / **Import library** (a single JSON file — this is the entire backup story); the
attribution block; version + licence line.

**States:** *Signed out* → the strip reads `ANONYMOUS · 5 PER DAY PER IP` in `--ink-muted`;
*Signing in* → the stub outline draws over 480 ms; *401 expired* → the row reads "Ticket expired —
sign in again" in `--warning`; *Error* → one sentence under the form in `--danger` and the field
underline turns `--danger`.

### 4.6 Marquee Lite landing and the No Print card (web only)

```
LITE LANDING (web, Auditorium)                 NO PRINT (web)
┌──────────────────────────────┐               ┌──────────────────────────────┐
│ ····· MARQUEE LITE ·····     │               │ REEL 01 · THREADING          │
│                              │               │            ·  (beam narrows  │
│      ╲    beam idle    ╱     │               │            ·   to a pinpoint)│
│   ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐    │               │ ░ This print can't be        │
│   │   DROP A FILM HERE   │   │               │ ░ projected here.            │
│   │      or  [ Open ]     │  │               │ ░ MKV · HEVC · AC-3          │
│   └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │               │ ░ This browser has no AC-3   │
│ This browser can play:       │  honest line  │ ░ decoder.                   │
│ MP4/H.264 · WebM/VP9/AV1 ·   │  from         │ ░ [ Try the WebCodecs path ] │
│ HEVC ✓ · AC-3 ✗ · MKV partial│  canPlayType  │ ░ [ Open in Marquee for      │
│ Open in Marquee for Windows  │               │ ░   Windows / Android ]      │
│ / Android →                  │               └──────────────────────────────┘
└──────────────────────────────┘
```

**Rules for this screen:** the drop frame is keyboard-operable (focusable, `Enter`/`Space` opens the
picker) and a real `<input type="file">` exists — **drag-and-drop is never the only way in**. The
capability line is computed, never hard-coded. The No Print card names the **exact** missing decoder
in one sentence and offers exactly two actions. If `window.VideoDecoder` is undefined the line ends
`· WebCodecs unavailable` and the "Try the WebCodecs path" button is **absent from the DOM**, not
merely hidden. No element on this card may use `--danger` as a background.

### 4.7 Navigation map

```
Lobby ──tap card / drop / Open──► Threading ──flash──► Auditorium ──CC──► Booth (sheet, 70 %)
  ▲                                   │                     │                  │
  │                                   └── skip ─────────────┘                  │
  └──────────── house-up (Esc / predictive back) ───────────┴──────────────────┘
Lobby ──⚙──► Ticket Office ──‹──► Lobby
```

`Esc` (and predictive back) always goes **exactly one lighting state up**. Leaving the Auditorium
runs `house-up`, disposes the `Player`, and restores system brightness.

---

## 5. Data model

### 5.1 Dart engine models (`lib/engine/models/`)

Immutable, `const`-constructible, with `fromJson`/`toJson` where they cross an API or DB boundary.
**No Flutter imports.**

```dart
// ─────────────────────────── identity & media ───────────────────────────

/// 16 lowercase hex chars. A value type so it can never be confused with a path.
extension type const MovieHash(String value) {
  static final _re = RegExp(r'^[0-9a-f]{16}$');
  bool get isValid => _re.hasMatch(value);
}

enum MediaOrigin { localPath, contentUri, commandLine, browserFile }

class MediaFile {
  final int? id;                    // drift row id, null before insert
  final String locator;             // Windows path OR Android content:// URI
  final String displayName;         // basename — the filename parser's input
  final int sizeBytes;
  final MovieHash? moviehash;       // null when sizeBytes < 131072
  final MediaOrigin origin;
  final String? container;          // 'matroska', 'mov,mp4,...' from mpv `file-format`
  final int? durationMs;
  final double? fps;                // mpv `container-fps` — used by scoring (§6.4)
  final int? width, height;
  final String? videoCodec, audioCodec;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  const MediaFile({ /* … */ });
}

class Chapter { final int index; final double startSeconds; final String? title; }

class ResumePoint {                 // one per MovieHash — survives a move or rename
  final MovieHash hash; final int positionMs; final int durationMs; final DateTime at;
  double get fraction => durationMs == 0 ? 0 : positionMs / durationMs;
  bool get finished => fraction > 0.97;
}

// ─────────────────────────── filename grammar ───────────────────────────

enum NameConfidence { high, medium, low }   // low ⇒ send the RAW filename as `query`
enum FeatureKind { movie, episode }

class ParsedName {
  final String title;               // cleaned: dots/underscores → spaces, trimmed
  final int? year;
  final int? season, episode;
  final String? resolution;         // '1080p'
  final String? source;             // 'BluRay' | 'WEB-DL' | 'WEB' | 'HDTV' | 'DVDRip'
  final String? videoCodecToken;    // VERBATIM token: 'x264' ≠ 'H264'  (R4)
  final String? group;              // 'AMIABLE'
  final bool remastered, proper, extended;
  final FeatureKind kind;
  final NameConfidence confidence;
  final String raw;                 // the original filename, for `query=<raw>`
  const ParsedName({ /* … */ });
}

// ─────────────────────────── subtitle providers ─────────────────────────

enum SubtitleProvider { openSubtitles, subdl, embedded, sidecar }

class FeatureDetails {
  final String featureType;         // 'Movie' | 'Episode'
  final String? title; final int? year;
  final int? seasonNumber, episodeNumber;
  final int? imdbId;                // 41959  (== tt0041959)
  final int? tmdbId;                // 1092
  const FeatureDetails({ /* … */ });
}

class SubtitleCandidate {
  final SubtitleProvider provider;
  final String id;                  // OS: files[0].file_id as String; Subdl: the `url` path
  final String language;            // ISO 639-1 lowercase: 'en'
  final String? release;            // 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE'
  final int downloadCount;
  final bool hearingImpaired;
  final bool moviehashMatch;
  final bool machineTranslated, aiTranslated;
  final double? fps;
  final DateTime? uploadDate;
  final FeatureDetails? feature;
  const SubtitleCandidate({ /* … */ });
}

/// Output of scoring.dart — never mutates the candidate.
class ScoredCandidate {
  final SubtitleCandidate candidate;
  final double score;
  final List<String> reasons;       // ['hash +1000','group +200','fps +40','downloads +4.09']
  final bool autoPick;              // ALWAYS false for machine/AI translated
  const ScoredCandidate({ /* … */ });
}

/// What is actually attached to the player right now.
sealed class SubtitleTrackRef { const SubtitleTrackRef(); }
class NoSubtitle       extends SubtitleTrackRef { const NoSubtitle(); }
class EmbeddedSubtitle extends SubtitleTrackRef { final int mpvTrackId; final String? language, title; }
class ExternalSubtitle extends SubtitleTrackRef {
  final String path;                // sidecar beside the file, or app storage
  final String language;
  final SubtitleProvider provider;
  final bool syncedByHash;          // true ⇒ green MATCH bulb; false ⇒ 'BY NAME · CHECK SYNC'
  final String? release;
}

class SyncOffset { final MovieHash hash; final int delayMs; }   // +ve = subtitles appear later

// ─────────────────────────── quota / tickets ────────────────────────────

enum TicketState { anonymous, nLeft, twoLeft, exhausted, vip, unknown }

class Quota {
  final int? remaining;             // from /download or /login
  final int? total;                 // login `allowed_downloads` — NEVER a constant
  final DateTime? resetUtc;
  final bool signedIn, vip;
  final String? level;              // 'Sub leecher'
  TicketState get state => !signedIn ? TicketState.anonymous
      : vip ? TicketState.vip
      : remaining == null ? TicketState.unknown
      : remaining! <= 0 ? TicketState.exhausted
      : remaining! <= 2 ? TicketState.twoLeft
      : TicketState.nLeft;
  const Quota({ /* … */ });
}

class TicketStrip {                 // pure view model produced by tickets.dart (§6.6)
  final String text;                // '7 OF 10 TONIGHT · RESETS 00:00 UTC'
  final String? sentence;           // the one-line explanation, or null
  final String ariaLabel;
  final TicketState state;
  final bool pendingTear;           // the count decrements AFTER ticket-tear completes
}

// ─────────────────────────── the leader ─────────────────────────────────

enum LeaderPhase { idle, hashing, searching, downloading, flash, done }

sealed class LeaderEvent { const LeaderEvent(); }
class Stalled extends LeaderEvent {
  final LeaderPhase at;
  final ThreadingFailure failure;
  final List<FallbackAction> next;  // filenameSearch, subdl, manualSearch, skip, signIn, retry
}

enum ThreadingFailure {
  fileTooSmall,      // < 128 KiB — NOT an error: skip the hash, go straight to filename search
  offline, timeout, noResults, unauthorized /*401*/, quotaExhausted /*406*/,
  rateLimited /*429*/, linkExpired /*410*/, writeFailed, decodeFailed, cancelled,
}

class ThreadingState {
  final LeaderPhase phase;
  final double sweep;               // 0..1, drives the conic-gradient mask
  final MovieHash? hash;
  final ParsedName? parsed;
  final List<ScoredCandidate> candidates;
  final ScoredCandidate? picked;
  final SubtitleTrackRef attached;
  final Quota quota;
  final LeaderEvent? event;         // non-null ⇒ the sweep is FROZEN at `sweep`
}

// ─────────────────────────── ambience & settings ────────────────────────

class BiasStops {                   // §6.10; null ⇒ keep --focus at 6 %
  final List<int> argb;             // exactly 5, by population then darkened duplicates
  final DateTime sampledAt;
}

enum LibraryScanMode { none, folders, mediaStore }

class Settings {
  final List<String> languages;     // max 3, ISO 639-1, ordered by preference
  final bool preferHearingImpaired;
  final bool saveBesideFile;
  final bool subdlEnabled;          // the user's own key, in secure storage
  final bool tmdbEnabled;
  final bool roomTone, biasLight, beam, sounds, haptics;
  final ThemeMode lobbyTheme;       // auto | auditorium | matinee — playback is ALWAYS auditorium
  final String hwdec;               // 'auto-safe' | 'no'
  final String? glslShaderPreset;   // Windows only, e.g. 'anime4k-clamp'
  final LibraryScanMode scanMode;
  const Settings({ /* … */ });
}
```

### 5.2 drift schema (`lib/db/tables.dart`, `schemaVersion: 1`)

| Table | Columns | Notes |
|---|---|---|
| `media_files` | `id` PK · `locator` **UNIQUE** · `display_name` · `size_bytes` · `moviehash` (nullable, **INDEXED**) · `origin` · `container` · `duration_ms` · `fps` · `width` · `height` · `video_codec` · `audio_codec` · `added_at` · `last_played_at` | `locator` is a Windows path or a `content://` URI. The same film at a new path **updates** the row, never duplicates it |
| `hash_cache` | PK (`moviehash`, `language`) · `provider` · `file_id` · `release` · `sidecar_path` · `synced_by_hash` · `fetched_at` | **The ticket-saver.** Consulted before any network call on every open. A hit costs **0** downloads. If `sidecar_path` no longer exists on disk, the row is invalidated — a cached path that is gone must never report a hit |
| `resume_points` | PK `moviehash` · `position_ms` · `duration_ms` · `at` | Keyed by hash so a moved/renamed file still resumes. A position within 30 s of the end stores as "finished" (position 0) so the sprocket fills instead of resuming on the credits |
| `sync_offsets` | PK `moviehash` · `delay_ms` | One row per hash (not per path); rewriting is idempotent. Surfaces as the `±0.35` Lobby chip |
| `folders` | `id` PK · `locator` · `grant_blob` (SAF persisted tree URI) · `last_scan_at` | Windows: plain paths. Android: persisted tree URIs that survive a reboot |
| `artwork` | PK `tmdb_id` · `poster_path` · `backdrop_path` · `accent_argb` · `fetched_at` · `expires_at` | `expires_at = fetched_at + 180 days`, **enforced**, swept at startup (TMDB terms cap caching at 6 months) |
| `search_cache` | PK `query_key` · `body_json` · `fetched_at` | **24 h TTL on search responses only.** `query_key` is the alphabetically-sorted query string, so it matches the exact request the client would have made. The *download* cache (the sidecar) never expires |
| `app_state` | PK `key` TEXT · `value_json` TEXT | The key/value store for state the other seven tables have no shape for. Three keys at v1.0.0: **`settings`** (the serialised `Settings` from §5.1), **`window_bounds`** (`{x,y,w,h,maximized}` — the Windows window must reopen where it closed) and **`seen_gate_nudge`** (`true` after the film-gate nudge has fired once). **No `shared_preferences`** — one store, one migration path, one export |

That is **eight** tables. `app_state` is read and written through a small typed facade, never raw, and its three keys are part of the export/import format so a restore brings the window geometry and the nudge flag back with everything else. A test round-trips both through a simulated restart.

**drift is code-generated.** `lib/db/database.g.dart` is produced by
`dart run build_runner build --delete-conflicting-outputs`, is **gitignored**, and is regenerated in
CI after `flutter pub get` and before `flutter analyze` (§11.2, §11.4).

Indexes: `media_files(moviehash)`, `hash_cache(moviehash, language)` (the PK), `resume_points`
(PK), `artwork(expires_at)`. A Lobby rail page over 5 000 rows must render in under one frame.

**Migrations:** `drift_dev` schema snapshots live in `test/db/schemas/`. A migration test asserts
`verifySelfIntegrity()` passes and **every existing row survives** — a migration that would drop
user data fails the test.

**Nothing sensitive lives in drift.** A test greps the serialised DB bytes and fails on a password,
an `Api-Key`, or a JWT: the JWT lives in `flutter_secure_storage` only.

### 5.3 TypeScript types (`web/src/engine/types.ts`)

The single source for the web tier. The Worker must stay dependency-free, so it carries its own copy
of the wire types, kept honest by a CI diff check.

```ts
// ── wire shapes: exactly what api.opensubtitles.com/api/v1 returns (only the fields we read) ──

export interface OsFile { file_id: number; cd_number?: number; file_name?: string }

export interface OsFeatureDetails {
  feature_type: 'Movie' | 'Episode' | string
  title?: string; year?: number
  season_number?: number | null; episode_number?: number | null
  imdb_id?: number | null; tmdb_id?: number | null
}

export interface OsSubtitleAttributes {
  language: string | null            // 'en'
  download_count: number
  new_download_count?: number
  hearing_impaired: boolean
  machine_translated: boolean
  ai_translated: boolean
  fps: number | null
  release: string | null
  upload_date?: string
  moviehash_match?: boolean          // ABSENT unless the search included a moviehash
  files: OsFile[]
  feature_details: OsFeatureDetails
}

export interface OsSearchResponse {
  total_pages: number; total_count: number; page: number
  data: Array<{ id: string; type: 'subtitle'; attributes: OsSubtitleAttributes }>
}

export interface OsLoginResponse {
  token: string
  base_url: string                   // 'api.opensubtitles.com' | 'vip-api.opensubtitles.com'
  status: number
  user: { allowed_downloads: number; level: string; user_id: number; ext_installed?: boolean; vip: boolean }
}

export interface OsDownloadResponse {
  link: string                       // TEMPORARY: store the FILE, never this URL (410 after expiry)
  file_name: string
  requests: number
  remaining: number
  message?: string
  reset_time?: string                // '08 hours and 16 minutes' — human text, never parsed
  reset_time_utc: string             // ISO — the only reset value the UI trusts
}

// ── engine types (mirror the Dart classes 1:1 so the goldens are shared) ──

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

export interface ScoredCandidate { candidate: Candidate; score: number; reasons: string[]; autoPick: boolean }

export interface ParsedName {
  title: string; year: number | null
  season: number | null; episode: number | null
  resolution: string | null; source: string | null
  videoCodecToken: string | null; group: string | null
  remastered: boolean; proper: boolean; extended: boolean
  kind: 'movie' | 'episode'
  confidence: 'high' | 'medium' | 'low'
  raw: string
}

export type TicketState = 'anonymous' | 'n-left' | 'two-left' | 'exhausted' | 'vip' | 'unknown'
export interface Quota { remaining: number | null; total: number | null; resetUtc: string | null
                         signedIn: boolean; vip: boolean; level: string | null }
export interface TicketStrip { text: string; sentence: string | null; ariaLabel: string
                               state: TicketState; pendingTear: boolean }

export type LeaderPhase = 'idle' | 'probing' | 'hashing' | 'searching' | 'downloading' | 'flash' | 'done'
export type ThreadingFailure =
  | 'file-too-small' | 'offline' | 'timeout' | 'no-results' | 'unauthorized' | 'quota-exhausted'
  | 'rate-limited' | 'link-expired' | 'undecodable' | 'no-codec' | 'cancelled'

export interface ThreadingState {
  phase: LeaderPhase; sweep: number             // 0..1; FROZEN while `failure` is set
  hash: MovieHash | null; parsed: ParsedName | null
  candidates: ScoredCandidate[]; picked: ScoredCandidate | null
  quota: Quota; failure: ThreadingFailure | null
  next: Array<'filename-search' | 'subdl' | 'manual' | 'skip' | 'sign-in' | 'webcodecs' | 'retry'>
}

// ── web-only: what the browser can actually play ──

export interface CodecSupport { label: string; ok: boolean; via: 'native' | 'webcodecs' | 'none' }
export interface Capability {
  line: string     // 'MP4/H.264 ✓ · WebM/VP9 ✓ · AV1 ✓ · HEVC ✗ · AC-3 ✗ · MKV partial'
  codecs: CodecSupport[]
  webCodecsAvailable: boolean
}

// ── Worker contract ──

export interface WorkerError {
  error: 'sign-in-required' | 'forbidden-origin' | 'not-found' | 'method-not-allowed'
       | 'rate-limited' | 'bad-link' | 'too-large' | 'upstream'
  sentence: string                   // what Lite prints under the stalled leader. Never a code
  retryAfterSeconds?: number
}

// ── IndexedDB records (web tier) ──

export interface CachedSubtitle {             // key: `${hash}|${lang}`
  hash: MovieHash; language: string; provider: Provider
  release: string | null; syncedByHash: boolean
  vttText: string                             // stored already converted, so offline reattach is instant
  bytes: number; fetchedAt: number
}
export interface StoredOffset { hash: MovieHash; delayMs: number }
export interface LiteSession { jwt: string | null; jwtExpiresAt: number | null; quota: Quota
                               languages: string[]; preferHearingImpaired: boolean }
```

**The JWT in `LiteSession` is encrypted at rest:** generate a **non-extractable AES-GCM key** with
WebCrypto, keep it in its own IndexedDB store, and seal the token with it. A "this session only"
switch keeps the token in memory instead and never writes it.

### 5.4 State management

**Native — Riverpod, eight providers:**

| Provider | Type | Holds | Rebuilt by |
|---|---|---|---|
| `settingsProvider` | `AsyncNotifier<Settings>` | Languages, HI preference, ambience bulbs, hwdec, scan mode | Ticket Office writes; persisted to drift |
| `playerProvider` | `Provider<PlayerEngine>` | The single `media_kit` `Player` + `VideoController`; disposed on leaving the Auditorium | never — it *is* the resource |
| `playbackProvider` | `StreamNotifier<PlaybackState>` | position, duration, buffering, tracks, chapters, fps, paused, speed | `player.stream.*` merged and **throttled to 10 Hz** (the folio only needs whole seconds — never rebuild at 60 Hz) |
| `threadingProvider` | `AsyncNotifier<ThreadingState>` | The leader state machine | `open(file)`, fallback taps |
| `quotaProvider` | `Notifier<Quota>` | Last known remaining/total/resetUtc | every `/download` and `/login` response |
| `libraryProvider` | `StreamNotifier<List<LobbyCard>>` | drift `watch()` over `media_files ⋈ resume_points ⋈ artwork ⋈ sync_offsets` | DB writes — reactive, no manual refresh |
| `biasLightProvider` | `Notifier<BiasStops?>` | The current five stops | the 500/1000 ms sampler; paused with playback |
| `houseProvider` | `Notifier<double>` | `--house` 1 → 0 — **the single value that drives the whole lighting change** | route transitions |

`houseProvider` deserves the emphasis: one number tweened over 900 ms drives wall luminance, sky
opacity, bulb intensity **and** the beam's cone width simultaneously. One `AnimationController` feeds
it; every affected widget watches it. That is the entire house-lights system, and a grep must prove
there is no second tween.

**Web — no store library.** One `AppState` object, one `EventTarget` for change notification, and DOM
updates by writing CSS custom properties (`--house`, `--wall-0…4`) and `el.textContent`. Total state
code ≈ 120 lines. **No router:** Lite is one page with three overlays (leader, booth sheet, No Print
card) toggled with `el.hidden`.

### 5.5 Export / import format

The Ticket Office's **Export library** writes one JSON file the user saves anywhere. This is the
whole backup story (there are no accounts and no cloud sync), and it must exist before v1.0.0
because a lost keystore can force an Android uninstall.

```jsonc
{
  "format": "marquee.library.v1",
  "exportedAt": "2026-09-08T15:44:00.000Z",
  "app": { "version": "1.0.0", "platform": "windows" },
  "mediaFiles": [ { "locator": "D:\\Films\\The Third Man (1949).mkv", "displayName": "…",
                    "sizeBytes": 1524000000, "moviehash": "8e245d9679d31e12", "container": "matroska",
                    "durationMs": 9663000, "fps": 23.976, "addedAt": "…", "lastPlayedAt": "…" } ],
  "resumePoints": [ { "hash": "8e245d9679d31e12", "positionMs": 4364400, "durationMs": 9663000, "at": "…" } ],
  "syncOffsets":  [ { "hash": "8e245d9679d31e12", "delayMs": 350 } ],
  "hashCache":    [ { "hash": "8e245d9679d31e12", "language": "en", "provider": "opensubtitles",
                      "fileId": "1234567", "release": "…", "sidecarPath": "…", "syncedByHash": true } ],
  "settings": { "languages": ["en","hi"], "preferHearingImpaired": false, "saveBesideFile": true }
}
```

**Import rules:** merge, never replace — a row whose `moviehash` already exists keeps the *newer*
`at`; unknown fields are ignored; an unknown `format` is refused with one sentence. Secrets (the JWT,
the Subdl key) are **never** exported. Run the restore drill once before v1.0.0: export, uninstall,
reinstall from the Release, import, and confirm the rail, the resume positions and one `±0.35` badge
all come back.

---

## 6. Engine and algorithms

Everything in this section is **pure**: no Flutter, no Riverpod, no DOM, no `dart:io` beyond a
`RandomAccessFile` handle passed in. Every algorithm has golden values here; those values are the
test suite. Write the Dart and the TypeScript from the same tables so the two tiers can never drift —
`scripts/check-parity.mjs` compares the `test('…')` names in `test/engine/*_test.dart` against
`web/src/engine/*.test.ts` and fails CI when one side has a case the other lacks.

### 6.1 The subtitle matching ladder — the feature, in one picture

Six rungs. Every rung is procedural; nothing is a heuristic that cannot be unit-tested.

```
open file
 ├─ RUNG 0a  sidecar beside it?  <name>.<lang>.srt / .ass       → attach · 0 requests · 0 tickets
 ├─ RUNG 0b  hash_cache hit (moviehash + language)?             → re-attach   · 0 requests · 0 tickets
 ├─ RUNG 1   moviehash (128 KiB of I/O)      [< 128 KiB ⇒ skip silently to rung 3]
 ├─ RUNG 2   GET /subtitles?moviehash=H&languages=…             SEARCH IS UNLIMITED AND FREE
 │             hit with attributes.moviehash_match == true      → score → auto-pick rank 1
 ├─ RUNG 3   parse filename → GET /subtitles?query=…&year=&season_number=&episode_number=
 │             (confidence 'low' ⇒ query=<RAW filename>: the server runs guessit better than we do)
 ├─ RUNG 4   Subdl (the user's own key)      search keyed · download ANONYMOUS
 ├─ RUNG 5   manual search field (the user types a title)
 └─ RUNG 6   "Skip subtitles" — embedded tracks are still available
                ↓ (a candidate is chosen)
        quota.remaining > 0 ?  ── no ──► crimson strip, sign-in / Subdl offer, NO request made
                ↓ yes
        POST /download {file_id, sub_format:'srt'}   ← THE ONLY CALL THAT SPENDS A TICKET
                ↓  (410 ⇒ exactly one retry for a fresh link)
        write <video>.<lang>.srt beside the file  (or app storage if not writable)
                ↓
        hash_cache.put(hash, lang, path, syncedByHash)
                ↓
        Player.setSubtitleTrack(SubtitleTrack.uri(path))
```

**Ladder invariants — each is an acceptance criterion:**

- **Rungs 0–1 and every search are free.** Only the download spends a ticket, and **never more than
  one per open without an explicit tap**.
- **`hash_cache` is checked before the network on every single open.** Re-watching a film costs zero
  downloads forever.
- **The bulb tells the truth.** `moviehash_match == true` → green MATCH + 2-pop. Anything else →
  `BY NAME · CHECK SYNC` in `--warning`. There is no third, optimistic state.
- **`machine_translated`/`ai_translated` candidates are listed but never auto-picked**
  (`autoPick: false`).
- **A stall is a stall.** Every rung failure freezes the leader numeral at its current sweep and
  slides the next rung in as a row. No rung silently retries more than once.
- **The list is ordered, never filtered.** Every candidate stays visible so a tap can override the
  auto-pick. The language filter is applied *before* scoring.

### 6.2 moviehash (`hash.dart` / `osHash.ts`)

**Spec** (public, `opensubtitles.github.io/oshash/`):

```
hash = (fileSize + Σ le_u64(first 64 KiB) + Σ le_u64(last 64 KiB)) mod 2⁶⁴
```

printed as **16 lowercase hex digits, zero-padded**. Files **< 128 KiB are rejected by the service** —
that is not an error in Marquee, it is a branch. Cost: 131 072 bytes of I/O and 16 384 additions —
under 40 ms on any disk, which is why the leader's "3" is a real phase and not theatre.

```dart
// lib/engine/hash.dart
// Dart VM ints are 64-bit two's complement and WRAP on overflow — exactly the arithmetic
// the spec asks for. `toUnsigned(64)` stops a negative wrap from printing a '-'.
class FileTooSmall implements Exception { final int size; const FileTooSmall(this.size); }
class HashUnavailable implements Exception { final Object cause; const HashUnavailable(this.cause); }

const int kChunk = 65536;
const int kMinSize = 2 * kChunk;   // 131072

Future<MovieHash> movieHashOf(RandomAccessFile raf, int sizeBytes) async {
  if (sizeBytes < kMinSize) throw FileTooSmall(sizeBytes);

  Future<int> chunkSum(int offset) async {
    await raf.setPosition(offset);
    final bytes = await raf.read(kChunk);
    if (bytes.length != kChunk) throw StateError('short read at $offset');
    final bd = ByteData.sublistView(bytes);
    var s = 0;
    for (var i = 0; i < kChunk; i += 8) {
      s += bd.getUint64(i, Endian.little);   // wraps at 2^64 — intended
    }
    return s;
  }

  final head = await chunkSum(0);
  final tail = await chunkSum(sizeBytes - kChunk);   // NOT aligned to a chunk boundary
  final h = (sizeBytes + head + tail).toUnsigned(64);
  return MovieHash(h.toRadixString(16).padLeft(16, '0'));
}
```

```ts
// web/src/engine/osHash.ts
// JS numbers cannot hold 64 bits, so BigInt + an explicit mask.
// Blob.slice() + arrayBuffer() reads ONLY the two chunks; a 40 GB file never enters memory.
const CHUNK = 65536, MIN = 2 * CHUNK, MASK = 0xffff_ffff_ffff_ffffn

export async function osHash(file: Blob): Promise<MovieHash> {
  if (file.size < MIN) throw new RangeError('FILE_TOO_SMALL')
  const sum = async (b: Blob): Promise<bigint> => {
    const dv = new DataView(await b.arrayBuffer())
    let s = 0n
    for (let i = 0; i < CHUNK; i += 8) s = (s + dv.getBigUint64(i, true)) & MASK
    return s
  }
  const [head, tail] = await Promise.all([
    sum(file.slice(0, CHUNK)),
    sum(file.slice(file.size - CHUNK)),
  ])
  const h = (BigInt(file.size) + head + tail) & MASK
  return h.toString(16).padStart(16, '0') as MovieHash
}
```

**Golden vectors — these seven are the test:**

The published spec ships **two** vectors, not one: `breakdance.avi` (V1) and **`dummy.rar`, 4 295 033 890 bytes → `61f7751fc2a72bfb`**. The second is the one that matters — its size exceeds 2³², so it is the only published vector that exposes 64-bit overflow and large-file seek bugs — but it is a 4 GB download. **V7 covers that failure mode synthetically**; `dummy.rar` stays here as the external cross-check anyone can run by hand once.

| # | Input | Arithmetic | Expected |
|---|---|---|---|
| V1 | `breakdance.avi`, 12 909 756 bytes (one of the **two** published vectors; fetched to a temp dir by `make-fixtures.sh`, **never committed**) | — | `8e245d9679d31e12` — if the download fails the test **skips with a printed warning**, never silently passes |
| V2 | 131 072 bytes of `0x00` | `131072 + 0 + 0 = 0x20000` | `0000000000020000` — proves zero-padding and that exactly 128 KiB is **accepted** |
| V3 | 131 072 bytes of `0xFF` | each chunk = 8192·(2⁶⁴−1) ≡ −8192 (mod 2⁶⁴); `131072 − 8192 − 8192 = 114688` | `000000000001c000` — proves the wrap is unsigned |
| V4 | 200 000 bytes of `0x00` | tail offset = `200000 − 65536 = 134464`, **not** a multiple of 65 536 | `0000000000030d40` |
| V5 | 131 071 bytes | — | Dart throws `FileTooSmall`; TS rejects with `FILE_TOO_SMALL`. **Neither ever reaches the UI as an error** |
| V6 | every file in `test/fixtures/media/` | — | the value frozen in `test/fixtures/hashes.json` (a regression lock on the fixture generator) |
| V7 | a **stub** source (fake `RandomAccessFile` / `Blob`) reporting `size = 4 294 967 296` (2³²) whose two 64 KiB chunks are all `0x00` — no 4 GB file, no download | `4294967296 + 0 + 0` | `0000000100000000` — **the large-file vector.** The only one that catches 32-bit truncation in `raf.setPosition(size − 65536)` / `Blob.slice(size − CHUNK)` and a `Number` leak in the TS path |

Additional required tests: a 4 GiB sparse file hashes in **< 100 ms** and reads **exactly 131 072
bytes** (assert with a counting `RandomAccessFile` spy — this guards against anyone "optimising" the
reader into a whole-file stream); a file deleted between `open()` and the second read wraps as
`HashUnavailable`, Threading skips to filename search, and the leader **does not stall**; a hash whose
top bit is set formats as 16 lowercase hex with no leading `−` and no `0x`; and the Dart and TS
results for the same fixture bytes are byte-identical strings.

**Threading contract:** `FileTooSmall` / `FILE_TOO_SMALL` **never surfaces as an error UI.**
`threading.dart` catches it, sets `hash = null`, and enters `searching` with a filename query — the
leader's "3" completes normally because reading the file *did* succeed.

### 6.3 Filename grammar (`filename.dart` / `filename.ts`)

A Dart/TypeScript port of MIT **`parse-torrent-title`**, extended for anime brackets. **Never
`guessit-js`** (LGPL-3.0 would infect a bundled web app). OpenSubtitles' own `query=<raw filename>`
runs guessit server-side and is the fallback when our confidence is `low`.

```
parse(filename):
  raw   := filename
  name  := strip the extension                            # '.srt'/'.ass' ⇒ REJECT, not a video
  name  := replace [._] with ' ' ONLY between word chars  # keeps 'S02E04', 'x264', 'WEB-DL'
  tokens:= split on spaces, keeping bracket groups intact

  # 1. anime bracket form:  [Group] Title - 12 (1080p) [HASH]
  if tokens[0] matches ^\[(\w+)\]$:
      group    := that
      episode  := first bare integer after a ' - ' separator
      kind     := episode ; confidence := high
      drop any trailing [8-hex] CRC group

  # 2. quality boundary — everything after the FIRST quality token is metadata, not title
  QUALITY := resolution | source | codec | audio | 'PROPER' | 'REPACK' | 'REMASTERED'
           | 'EXTENDED' | 'UNRATED' | 'HDR' | '10bit' | a 4-digit year followed by a QUALITY token
  cut     := index of first QUALITY token   (or end)

  # 3. year — the LAST 19xx/20xx token strictly before `cut`
  year := last match of /^(19|20)\d{2}$/ in tokens[0..cut)   ; remove it from the title span

  # 4. season/episode, in priority order
  S/E  := /^S(\d{1,2})E(\d{1,3})$/i | /^(\d{1,2})x(\d{1,3})$/ | /Season (\d+).*Episode (\d+)/i
  kind := (S/E found or bare anime episode) ? episode : movie

  # 5. metadata from tokens[cut..]
  resolution      := /^(\d{3,4}p|4K|2160p)$/i
  source          := BluRay|BDRip|BRRip|WEB-DL|WEBRip|WEB|HDTV|DVDRip|REMUX|CAM|TS
  videoCodecToken := VERBATIM matched token from x264|x265|H264|H265|HEVC|AVC|XviD|DivX|AV1|VP9
  group           := token after the LAST '-' in the ORIGINAL name, unless it is a codec/resolution
                     or contains a dot; the anime form has already set it
  flags           := remastered / proper / extended

  title := tokens[0..cut) minus year, joined, trimmed, whitespace collapsed

  confidence :=
      high    if year or S/E present AND title has ≥ 1 alphabetic token
      medium  if title has ≥ 2 tokens and at least one QUALITY token was found
      low     otherwise                    # ⇒ search with query=<raw>, let guessit do it server-side
```

**Worked example** — `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv`:

| Step | Value |
|---|---|
| after extension + separator normalisation | `The Third Man 1949 1080p BluRay x264-AMIABLE` |
| first QUALITY token | `1080p` at index 4 → `cut = 4` |
| year (last 19xx/20xx before cut) | `1949` |
| title span minus year | `The Third Man` |
| resolution / source / codec token / group | `1080p` / `BluRay` / `x264` / `AMIABLE` |
| kind / confidence | `movie` / `high` |

**Golden table — all eight rows must reproduce exactly** (unlisted fields are `null`, never `''`):

| Filename | title | year | S/E | res | source | codec | group | note |
|---|---|---|---|---|---|---|---|---|
| `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv` | The Third Man | 1949 | — | 1080p | BluRay | x264 | AMIABLE | the house film |
| `Chungking.Express.1994.REMASTERED.1080p.BluRay.x265-RARBG.mkv` | Chungking Express | 1994 | — | 1080p | BluRay | x265 | RARBG | `remastered: true` |
| `Paddington.2014.720p.WEB-DL.H264-NTb.mkv` | Paddington | 2014 | — | 720p | WEB-DL | H264 | NTb | |
| `Severance.S02E04.1080p.WEB.H264-NTb.mkv` | Severance | — | 2 / 4 | 1080p | WEB | H264 | NTb | `kind: episode` |
| `The Third Man (1949).mkv` | The Third Man | 1949 | — | — | — | — | — | spaces + parentheses |
| `[SubsPlease] Frieren - 12 (1080p) [ABCD1234].mkv` | Frieren | — | — / 12 | 1080p | — | — | SubsPlease | anime form; trailing CRC bracket discarded |
| `movie.mkv` | movie | — | — | — | — | — | — | **`confidence: 'low'`** → Threading sends `query=movie.mkv` (the raw name) |
| `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.en.srt` | — | — | — | — | — | — | — | `.srt` is **not a video** → rejected by the picker filter *before* parsing |

Two more required cases: `Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-TERMINAL.mkv` → `title:
'Blade Runner 2049'`, `year: 2017` (a year inside the title is not stolen by the year rule); and a
name whose last dash segment is a codec (`…-x265`) → `group: null`, `codec: 'x265'`.

**Path handling:** parse only the basename. When the basename is `confidence: 'low'`, parse the
**parent directory name** as a second attempt and use it when it scores higher (`D:\Films\The Third
Man (1949)\video.mkv`).

### 6.4 Candidate scoring (`scoring.dart` / `scoring.ts`) — the frozen weights

```dart
double score(SubtitleCandidate c, ParsedName? n, double? containerFps, bool preferHI) {
  var s = 0.0; final why = <String>[];
  if (c.moviehashMatch)                            { s += 1000; why.add('hash +1000'); }
  final r = c.release == null ? null : parseName(c.release!);   // reuse §6.3 on the release name
  if (n != null && r != null) {
    if (eqi(r.group, n.group))                     { s +=  200; why.add('group +200'); }
    if (eqi(r.source, n.source))                   { s +=  100; why.add('source +100'); }
    if (eqi(r.resolution, n.resolution))           { s +=   50; why.add('res +50'); }
    if (eqi(r.videoCodecToken, n.videoCodecToken)) { s +=   20; why.add('codec +20'); }
  }
  if (containerFps != null && c.fps != null) {
    final same = (c.fps! - containerFps).abs() <= 0.01;
    s += same ? 40 : -40;                           why.add(same ? 'fps +40' : 'fps -40');
  }
  s += c.hearingImpaired ? (preferHI ? 30 : -30) : 0;
  if (c.machineTranslated || c.aiTranslated)       { s -= 500; why.add('machine -500'); }
  s += math.log(math.max(c.downloadCount, 1)) / math.ln10;      // log10 — the tie-breaker
  return s;
}
```

**`eqi` is a case-insensitive EXACT token comparison (R4).** `x264` and `H264` are therefore
**different codecs** — an x264 BluRay encode and a generic-H264 WEB-DL are different provenance.
If you ever normalise them, every number below changes and **must be updated in the same commit**.

**Worked example** — file `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv`, container fps 23.976,
HI **not** preferred:

| # | Release | hash | dl | HI | fps | Arithmetic | Score | Rank |
|---|---|---|---|---|---|---|---|---|
| A | `…1080p.BluRay.x264-AMIABLE` | ✔ | 12 431 | — | 23.976 | 1000+200+100+50+20+40+log₁₀(12431)=4.09 | **1414.09** | **1 · auto-pick** |
| D | `…1080p.BluRay.x264-AMIABLE` | ✘ | 51 000 | — | 23.976 | 200+100+50+20+40+4.71 | **414.71** | 2 |
| C | `…1949.BluRay-AMIABLE` | ✘ | 902 | ✔ | 25 | 200+100−40−30+2.96 | **232.96** | 3 |
| B | `…1080p.WEB-DL.H264-NTb` | ✘ | 4 102 | ✔ | 23.976 | 50+40−30+3.61 | **63.61** | 4 |
| E | any, `machine_translated: true` | ✔ | 99 999 | — | 23.976 | 1000−500+… | **< 1414** | last, `autoPick: false` |

Read row C against row B: the fixture is authored so the test *documents* that a release-group match
beats an fps mismatch. If the product decision ever flips (an fps mismatch should sink a candidate
below a same-fps WEB-DL), change the fps penalty to **−250** and update this table in the same commit.

Also assert: ties break on `download_count`; the auto-pick is rank 1 **unless** `autoPick == false`;
the list keeps **every** candidate (ordered, never filtered); the language filter runs before scoring;
Subdl candidates always carry `moviehashMatch: false` (that provider has no hash search at all) and
can therefore never light the MATCH bulb; and with HI **preferred**, C and B each gain +60 relative
to the others (−30 becomes +30) without changing A's rank.

### 6.5 The leader state machine (`threading.dart` / `threading.ts`)

The academy countdown is not decoration wrapped around a spinner: **each numeral is a promise**, and
the conic sweep is driven by that promise's progress.

```
[*] ──► idle
idle          ──open(file)──────────────────────────────────► hashing
hashing       ──hash ready────────────────────────────────► searching
hashing       ──FileTooSmall (SILENT — no error UI)───────► searching
searching     ──candidates ranked, auto-pick, quota > 0───► downloading
searching     ──no results / offline / 429 / timeout──────► stalledSearch
downloading   ──sidecar written + hash_cache updated──────► flash
downloading   ──406 quota / 401 expired / 410 link / write failed──► stalledDownload
flash         ──66 ms black flash, controls shown 2400 ms─► done
stalledSearch ──fallback chosen (filename / Subdl / manual)► searching
stalledSearch ──"Skip subtitles"──────────────────────────► done
stalledDownload ──retry once (410) or after sign-in───────► downloading
stalledDownload ──"Play without subtitles"────────────────► done
done ──► [*]
```

**Rules the tests assert:**

- `sweep` advances **only** while the current phase's future is pending. On rejection it **freezes at
  its current value** and `failure` is set — it never jumps to 1.0 and never resets to 0.
- Each phase has a **deadline**: hashing **2 s**, searching **8 s**, downloading **15 s**. Exceeding
  it is `timeout`, which is a stall, not a crash.
- A stall publishes `next[]` — the fallback rows that slide in under the numeral. The order is fixed:
  `filename-search → subdl (if enabled) → manual → skip`, with `sign-in` **inserted first** on
  `unauthorized` / `quota-exhausted`.
- **Exactly one automatic retry exists in the whole machine:** a `410` on the download link re-issues
  `POST /download` once. Everything else waits for a human.
- Fallback rows must be visible **within 500 ms** of the failure.
- The phase is announced once to screen readers, never per frame.
- Cancelling (predictive back / `Esc`) resolves to `done` with `NoSubtitle` — **playback still
  starts**.
- Libmpv opens the file **concurrently** with the leader's phases, so the hash costs no wall-clock
  time.

### 6.6 Quota → ticket strip (`tickets.dart` / `tickets.ts`)

A pure function of the last `/download` response (or the login payload) plus the injected clock.
**The total is never a constant** — OpenSubtitles' own help articles say 10 in one place and 20 in
another, so print whatever `user.allowed_downloads` came back with.

Fixed clock for these goldens: `2026-09-06T15:44Z`.

| Input | Strip text | Colour | State | aria-label |
|---|---|---|---|---|
| `{requests: 3, remaining: 7, reset_time_utc: "2026-09-07T00:00:00.000Z"}` with `allowed_downloads: 10` | `7 OF 10 TONIGHT · RESETS 00:00 UTC` | `--ink` | `n-left` | "7 of 10 downloads left tonight" |
| `remaining: 2` | same text **+** "Sign in at the ticket office (free, more tickets)" or "Use the Subdl slot" | strip `--accent-2`, text `--accent-2-lit` | `two-left` | "2 of 10 downloads left tonight" |
| `remaining: 0` **or** HTTP **406** | `NO TICKETS LEFT TONIGHT · RESETS 00:00 UTC` + "No tickets left tonight — sign in for more, or use the Subdl slot" | `--accent-2` / `--accent-2-lit` | `exhausted` | "No downloads left tonight" |
| signed out (no JWT) | `ANONYMOUS · 5 PER DAY PER IP` | `--ink-muted` | `anonymous` | "Anonymous: 5 downloads per day per network" |
| `allowed_downloads: 20` from login | `7 OF 20 TONIGHT` — **20, not 10** | | `n-left` | trusts the login response, never a constant |
| `allowed_downloads: 1000, vip: true` | `7 OF 1000 · VIP`; subsequent calls use `base_url` from login | | `vip` | |
| HTTP **429** with `Retry-After: 2` | strip unchanged; the leader's "2" stalls; sentence "OpenSubtitles asked us to wait 2 s" | `--warning` | — | announced once |
| HTTP **410** on the link | "That print expired — fetching a fresh link", then exactly one `/download` retry; the `remaining` shown is **the retry's** | `--warning` | — | |

`pendingTear` exists so a widget test can prove the count decrements **after** the `ticket-tear`
animation, not before.

### 6.7 Folio timecodes (`timecode.dart` / `timecode.ts`)

Position **floors** to whole seconds, remaining **ceils**, so the two always add up to the duration
and the folio never shows an off-by-one. Always `HH:MM:SS`, never wrapping at 24 h, **U+2212 (−)
not a hyphen**, tabular figures.

```
folio(pos, dur) = fmt(floor(pos)) + ' · −' + fmt(ceil(dur) − floor(pos))
fmt(s)          = HH:MM:SS with HH unbounded  (12:30:00 stays 12:30:00)
dur == null     → fmt(floor(pos)) + ' · —'          // live / stream
```

| position s | duration s | Folio |
|---|---|---|
| 4364.4 | 9663 | `01:12:44 · −01:28:19` (the wireframe value) |
| 0 | 9663 | `00:00:00 · −02:41:03` |
| 9663 | 9663 | `02:41:03 · −00:00:00` |
| 59.999 | 61 | `00:00:59 · −00:00:02` |
| 3599.2 | 3600 | `00:59:59 · −00:00:01` |
| 45 000 | 45 000 | `12:30:00 · −00:00:00` (never wraps at 24 h) |
| 45 | unknown | `00:00:45 · —` |

Suffixes append, never replace: `2.0×` while long-pressing, `A–B` while looping, `SUB +0.35` when an
offset is set. Threading folio: `REEL 01 · THREADING`. Auditorium desktop folio: `REEL 01 · THE THIRD
MAN · 01:12:44 · −01:28:19` — the title uppercased and condensed to 40 chars with `…`.

### 6.8 Sync rule (`sync_rule.dart` / `syncRule.ts`)

```
DETENT = 0.05 s ; RANGE = ±2.00 s
snap(v)          = clamp(round(v / DETENT) * DETENT, -2.0, +2.0)   // ROUND, not floor
step(v, k)       = snap(v + (k.shift ? 0.50 : 0.05) * (k.isK ? +1 : -1))
reset()          = 0.00
apply(native, v) = (player.platform as NativePlayer).setProperty('sub-delay', v.toStringAsFixed(2))
apply(web,    v) = re-emit the VTT blob with every cue shifted by v, clamped at 00:00:00.000
persist(hash, v) = sync_offsets upsert   // restored on the next open of the SAME moviehash
```

**Sign convention: positive means the subtitles appear later.**

| Action | From | To | Folio |
|---|---|---|---|
| drag to +0.37 | 0 | **+0.35** | `SUB +0.35` |
| drag to +0.376 | 0 | **+0.40** (nearest, **not** floor — this assertion catches a `truncate()`) | `SUB +0.40` |
| drag to +2.40 | 0 | +2.00 (clamped) | `SUB +2.00` |
| `K` | +0.35 | +0.40 | |
| `J` | +0.35 | +0.30 | |
| `Shift+K` | +0.35 | +0.85 | |
| long-press readout / `Shift+J+K` | +0.85 | 0.00 | readout `SYNC +0.00`, folio suffix removed |
| reopen the same moviehash | — | the remembered value (+0.35) | Lobby card shows the `±0.35` badge |
| reopen a different hash | — | 0.00 | |

### 6.9 Chapter and seek detents (`detents.dart`)

```
detents := mpv `chapter-list` start times, else [0, 300, 600, …, duration]
captureRadiusPx := 6                             // at the gate's RENDERED width
snapTarget(releasePx, gateWidthPx, duration):
    secondsPerPx := duration / gateWidthPx
    nearest      := argmin over detents of |d / secondsPerPx − releasePx|
    return |nearest_px − releasePx| <= 6 ? nearest : releasePx * secondsPerPx
FINE mode (drag up off the strip): detents disabled, 1/8 gain — 80 px of finger = 10 px of gate
```

Fixture: gate 800 px, duration 9663 s (12.08 s/px), chapters at 0 / 1800 / 4200 / 7200 s.

| Release at px | Nearest detent | Result |
|---|---|---|
| 152 | 149.0 px (1800 s) | 3.0 px away → **snaps to 1800 s** with the 380/32 spring, light haptic + selection tick |
| 160 | 149.0 px | 11 px away → **no snap** → seek to 1932.6 s |
| 0 | 0 | 0 s |
| 800 | 7200 s is at 596 px | 9663 s (the end; no snap to a detent further than 6 px) |
| any, FINE | — | detents disabled; 80 px of drag = 10 px of gate = 120.8 s |

### 6.10 Bias light (`bias_light.dart`)

The walls glow with the colour of whatever is playing. This is the second-most-visible thing in the
app after the leader and it must cost almost nothing: **≤ 2 ms of CPU every 500 ms** on desktop,
1000 ms on Android (opt-in there until you measure it — §9 step 4.9).

Pipeline, native:

```
every N ms while playing AND visible:
  1. bytes := await player.screenshot(format: 'image/jpeg')    // media_kit; includes libass subs
  2. codec := await ui.instantiateImageCodec(bytes, targetWidth: 64, targetHeight: 36)
     rgba  := (await codec.getNextFrame()).image.toByteData(format: rawRgba)
     // the DECODER does the downscale — never touch a full-res frame
  3. crop  := top 80 % of rows      // subtitles burn into the bottom fifth and would drag every
                                    // stop toward white. The crop happens in player/screenshot.dart,
                                    // NOT inside the pure function
  4. stops := extractStops(rgba, 64, 29)
  5. tween := lerp previous → stops over 600 ms (1200 ms under reduced motion)
```

The pure part:

```dart
// lib/engine/bias_light.dart — material_color_utilities: QuantizerCelebi + Hct (Apache-2.0)
const int _kLetterboxTone = 8;      // L* below this is letterbox/black-crush, not "the film's colour"
const double _kMinKeptFraction = 0.05;

BiasStops? extractStops(Uint8List rgba, int w, int h, {DateTime? at}) {
  // 1. sample at most 2304 pixels, evenly
  final stride = math.max(1, (w * h) ~/ 2304);
  final kept = <int>[];
  var sampled = 0;
  for (var p = 0; p < w * h; p += stride) {
    sampled++;
    final i = p * 4;
    final argb = 0xFF000000 | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    if (Hct.fromInt(argb).tone >= _kLetterboxTone) kept.add(argb);   // drop the black bars
  }
  if (kept.length < sampled * _kMinKeptFraction) return null;        // an all-black frame

  // 2. quantize, then order by POPULATION (not by Score's "suitability" ranking —
  //    we want what is on screen, not what makes a pretty Material palette)
  final q = QuantizerCelebi().quantize(kept, 16);
  final byCount = q.colorToCount.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = byCount.take(3).map((e) => e.key).toList();
  while (top.length < 3) top.add(top.last);                          // monochrome frames

  // 3. five stops: three real ones, then two darkened duplicates that carry the gradient out
  //    to the edge of the wall. Both are guaranteed darker than stop 2.
  final s3 = _atTone(top[0], math.min(_tone(top[0]) * 0.35, _tone(top[2]) - 10));
  final s4 = _atTone(top[1], math.min(_tone(top[1]) * 0.25, _tone(top[2]) - 14));
  return BiasStops(argb: [top[0], top[1], top[2], s3, s4], sampledAt: at ?? clock.now());
}

double _tone(int argb) => Hct.fromInt(argb).tone;
int _atTone(int argb, double tone) {
  final c = Hct.fromInt(argb);
  return Hct.from(c.hue, c.chroma, tone.clamp(2.0, 100.0)).toInt();
}
```

**Golden** — `test/fixtures/media/frame-bias.png` (64 × 36; 60 % `#FFC56E`, 30 % `#A3252F`,
10 % `#5FD48A`):

| Stop | Source | HCT tone | Assertion |
|---|---|---|---|
| 0 | tungsten, 60 % of pixels | ≈ 83 | ΔE2000 < 5 from `#FFC56E` |
| 1 | crimson, 30 % | ≈ 34 | ΔE2000 < 5 from `#A3252F` |
| 2 | exit-green, 10 % | ≈ 78 | ΔE2000 < 5 from `#5FD48A` |
| 3 | `_atTone(tungsten, min(83·0.35, 78−10))` | 29 | `< tone(stop 2)` |
| 4 | `_atTone(crimson, min(34·0.25, 78−14))` | 8.5 | `< tone(stop 2)` |

Edge cases the golden pins down: an **all-black letterbox frame → `null`**, and the widget simply
keeps `--focus` at 6 % alpha; a frame that is 95 % black with a 5 % tungsten highlight → the black is
dropped by the tone filter and **stop 0 is tungsten** (the "dark scene with a single lamp" case,
which is the entire point of the effect).

**Render:** five stops become one radial gradient painted on the wall **around** the picture, never
on it; alphas ramp 14 % → 8 % → 4 % → 2 % → 0 %, lerped over 600 ms. The beam shader reads the same
stops as uniforms so the cone picks up the film's colour. **Paused → the glow freezes** (no sampling,
no CPU).

**Web tier:** identical output, different plumbing — `video.requestVideoFrameCallback()` →
`drawImage` into a 64 × 36 `OffscreenCanvas` → `getImageData` → the same algorithm from
`@material/material-color-utilities` (the official JS port, so the tiers agree within the ΔE
tolerance) → five CSS custom properties on `:root`, transitioned by CSS. Sampling stops on
`visibilitychange` and while paused. A cross-origin frame would taint the canvas — impossible here,
because the source is always a `File` the user picked (`blob:` same-origin).

### 6.11 SRT → WebVTT and delay (`srt.dart` / `srt2vtt.ts`)

Native playback never needs this (libmpv reads SRT directly and `sub-delay` handles the offset). It
exists for two jobs: the web tier's `<track>`, and the opt-in "save beside file with the offset baked
in".

```
strip UTF-8 BOM → normalise CRLF to LF → split on blank lines → parse blocks
timestamps: 00:00:01,000 --> 00:00:02,500      # comma → dot
sort cues by start; renumber 1..n              # a real file had cue 2 before cue 1
keep <i> <b> <u> (VTT supports them); strip <font …> to its text
{\an8} at the start of a cue → append ' line:0' to the cue settings
shift(ms): every start/end += ms, CLAMPED at 00:00:00.000; overlaps preserved (VTT allows them)
emit: 'WEBVTT\n\n' + blocks
```

`sample-crlf-bom.srt` (BOM + CRLF + cue 2 before cue 1 + an `<i>` cue + a final cue with no trailing
blank line) must convert **byte-for-byte** to:

```
WEBVTT

1
00:00:01.000 --> 00:00:02.500
First line

2
00:01:02.500 --> 00:01:04.000
<i>Second</i> cue
second line
```

A delay of `+0.35 s` shifts *every* cue by +350 ms (`00:01:02.850 --> 00:01:04.350`) and never
produces a negative start.

**Security:** subtitle files are user- and network-supplied text. They go to libass/JASSUB or into a
`<track>` — **never to `innerHTML`**. The parser is a state machine over lines: no `eval`, all
patterns anchored, each cue capped at 10 000 characters so there is no backtracking hazard on
unbounded input.

### 6.12 Capability probe (`capability.ts`, web only)

Marquee Lite's honesty line. Two probes, in this order, producing one sentence the user can act on:

```ts
const PROBES = [
  ['MP4/H.264', 'video/mp4; codecs="avc1.42E01E, mp4a.40.2"'],
  ['WebM/VP9',  'video/webm; codecs="vp9, opus"'],
  ['AV1',       'video/webm; codecs="av01.0.05M.08"'],
  ['HEVC',      'video/mp4; codecs="hvc1.1.6.L93.B0"'],
  ['AC-3',      'audio/mp4; codecs="ac-3"'],
] as const

// 1. <video>.canPlayType(t) === 'probably' | 'maybe'                       → via: 'native'
// 2. else, if window.VideoDecoder && await VideoDecoder.isConfigSupported() → via: 'webcodecs'
// 3. else ✗ — and the No Print card names the exact missing piece
//    ("This browser has no AC-3 decoder")
// MKV is NEVER probed: Chrome plays some H.264 MKVs and fails silently on others, so the line
// always reads 'MKV partial'. That is policy, not a measurement.
```

| Probe | Stubbed result | Line fragment |
|---|---|---|
| MP4/H.264 | `probably` | `MP4/H.264 ✓` |
| WebM/VP9 | `probably` | `WebM/VP9 ✓` |
| AV1 | `probably` / `""` | `AV1 ✓` / `AV1 ✗` |
| HEVC | `""` then `isConfigSupported → {supported:true}` | `HEVC ✓ (WebCodecs)` |
| HEVC | both negative | `HEVC ✗` |
| AC-3 | `""` | `AC-3 ✗` |
| MKV | never probed | `MKV partial`, always |
| `window.VideoDecoder` undefined | | the line ends `· WebCodecs unavailable`; the "Try the WebCodecs path" button is **not rendered at all** |

The probe runs during the leader's "3", so it costs no extra wait. Per-browser e2e certainties:
Chrome → contains `MP4/H.264 ✓` and `WebM/VP9 ✓`; Firefox → contains `AC-3 ✗`; all → contain
`MKV partial`.

---

## 7. Data sources and APIs

### 7.1 OpenSubtitles.com REST v1 — the only mandatory API

**Base:** `https://api.opensubtitles.com/api/v1`. A VIP login returns `base_url:
vip-api.opensubtitles.com`, which the client must then use for subsequent calls.

**Headers on every request — omitting either of the first two is a 403:**

```
Api-Key: <consumer key>
User-Agent: Marquee v1.0.0            (native)  /  Marquee-Web v1.0.0  (injected by the Worker)
Accept: application/json
Content-Type: application/json        (POST only)
Authorization: Bearer <jwt>           (when signed in)
```

**Three gateway rules discovered by live probe. All three are implemented in `net.dart` and in the
Worker:**

1. **Query parameters must be sorted alphabetically.** An unsorted query gets a `301` to the
   canonical sorted URL, wasting a round trip and (in a browser) re-triggering CORS.
2. `moviehash_match=include` is the **default** — the canonical redirect strips it. Send it anyway
   for clarity; do **not** depend on `only`, which could not be verified.
3. The gateway answers CORS preflight `OPTIONS` with **403 and no `Access-Control-Allow-Headers`**,
   and the mandatory `Api-Key` header *always* triggers a preflight. **A browser can therefore never
   call this API directly** — which is the entire reason the Worker exists.

**Endpoints:**

| Call | Response | Cost |
|---|---|---|
| `GET /subtitles?languages=en&moviehash=<h>&moviehash_match=include&order_by=download_count` | `{total_pages, total_count, page, data[{id, type, attributes}]}` | **Free — search is unlimited** (subject to rate limiting) |
| `GET /subtitles?episode_number=&languages=&query=&season_number=&year=` (**sorted!**) | same | Free |
| `POST /login {username, password}` | `{token, base_url, status, user{allowed_downloads, level, user_id, vip}}` | Free, rate-limited |
| `POST /download {file_id, sub_format:"srt"}` + `Authorization` | `{link, file_name, requests, remaining, reset_time, reset_time_utc}` | **Spends one ticket** |
| `GET <link>` | the `.srt` bytes — **temporary**, `410` once expired | Free |
| `GET /infos/user` + `Authorization` | the current quota **without spending one** | Free |

**Quota reality.** Anonymous: 5 per 24 h **per IP** — shared with everyone behind that IP, so
useless in practice. A free registered account is documented as both "20 per day" and "from 10 for
regular users" in two different help articles, so **the app trusts the login/download response and
never a constant**. VIP goes up to 1000.

**Rate limiting.** No per-second figure is documented anywhere reachable, so `net.dart` is purely
**reactive**: read `X-RateLimit-Limit` / `-Remaining` / `-Reset`; on `429` honour `Retry-After`
(default 2 s), retry **once**, then stall the leader with *"OpenSubtitles asked us to wait N s."*
**Never a fixed sleep, never a retry storm.**

**Caching.** Search responses → `search_cache` for 24 h, keyed by the sorted query string. Download
**links** are never cached (they expire). The `.srt` **file** is cached forever as a sidecar plus a
`hash_cache` row.

**Attribution.** "Subtitles by OpenSubtitles.com" in the Lobby footer and the Ticket Office.

### 7.2 Subdl — optional fallback (rung 4)

```
GET https://api.subdl.com/api/v1/subtitles
    ?api_key=<the USER'S own key>&file_name=…|imdb_id=…&languages=EN&type=movie
→ results carry a `url` path
Download: https://dl.subdl.com/subtitle/{url}   ← MUST be requested ANONYMOUSLY (no api_key on that host)
```

A free key buys 2 000 *search* requests/day and **no download quota**; downloads are 300/day/IP
anonymous. The payload is a **zip**: unzip in memory and take the single `.srt` (or the largest one).

**Zip hardening (required):** entries size-capped at **2 MB**, path-traversal names (`../`, absolute
paths, backslashes) **rejected**, only the first `.srt`/`.ass` read, and **nothing is ever written
from a zip-supplied path**. A test feeds a zip containing `../evil.srt` and asserts rejection.

Subdl has no hash search, so every Subdl candidate scores with `moviehashMatch: false` and can never
light the MATCH bulb.

### 7.3 TMDB — optional posters only

```
GET /find/{imdb_id}?external_source=imdb_id        // imdb_id arrives free in OpenSubtitles' feature_details
→ movie_results[0].{id, poster_path, backdrop_path}
Images: https://image.tmdb.org/t/p/{w342|w500|w780}{path}
```

Bearer read token; informally ~40 req/s; honour 429.

**Three terms are enforced in code, not in a comment:**
1. The **TMDB logo and the exact notice** — *"This product uses TMDB and the TMDB APIs but is not
   endorsed, certified, or otherwise approved by TMDB"* — render in the Lobby footer and the Ticket
   Office whenever TMDB is enabled.
2. `artwork.expires_at = fetched_at + 180 days`, with a **startup sweep** that deletes expired rows.
   No cache older than 6 months, ever.
3. No ML/LLM feature exists anywhere in Marquee, so the "no AI use of TMDB content" clause is
   satisfied by construction.

Disabling TMDB in the Ticket Office must remove **every** network call to it *and* the logo.

**How each tier reaches TMDB.** Native builds call `api.themoviedb.org` directly with the token
injected at build time (`--dart-define=TMDB_READ_TOKEN=…`). **Lite goes through the Worker's
`GET /api/tmdb/*` route** (§7.6) so the token stays server-side — that route is the only reason
Lite has posters at all. With no token configured on either side, both tiers fall back to the
25 %-luminance frame grab and neither makes a single TMDB request.

### 7.4 What leaves the device, and nothing else

| Leaves | Goes to | When |
|---|---|---|
| the 16-hex moviehash | OpenSubtitles (directly from native; via the Worker from Lite) | on a search |
| the file size | " | " |
| a filename-derived query string | " | rung 3 only |
| the chosen `file_id` | " | on a download |
| the user's own OpenSubtitles JWT | " | when signed in |
| an `imdb_id` | TMDB (directly from native; via the Worker's `/api/tmdb/*` route from Lite, so the token never reaches the browser) | only when TMDB is enabled |

**Never:** the file, a frame, a path, a device identifier, an install id, a crash report.

### 7.5 Error handling — every failure has a sentence

**House rule: errors are a stalled leader numeral and one plain sentence. Never a red banner, never
a spinner, never a code, never a stack trace in the UI.**

| Failure | Detected as | UI | Next action |
|---|---|---|---|
| File < 128 KiB | `FileTooSmall` | *(nothing)* — "3" completes, "2" starts | Filename search, silently |
| Offline | `SocketException` / `TypeError: Failed to fetch` | "2" stalls | "Play without subtitles" (lit) · retry on reconnect |
| No results (any rung) | `total_count == 0` | "2" stalls, fallback rows slide in | filename → Subdl → manual → skip |
| `401` expired JWT | status | Ticket Office row: "Ticket expired — sign in again" in `--warning` | one-tap re-login; the pending download resumes |
| `406` quota | status | Strip goes crimson: "No tickets left tonight — sign in for more, or use the Subdl slot" | Sign in · Subdl · skip |
| `429` | status + `Retry-After` | "OpenSubtitles asked us to wait 2 s" | one automatic retry, then a manual button |
| `410` expired link | status on the `link` | "That print expired — fetching a fresh link" | exactly one automatic `POST /download` retry; the shown `remaining` is the retry's |
| Sidecar write failed | `FileSystemException` / SAF failure | "Couldn't write beside the file — saved in app storage instead" | attaches anyway; the Booth row says where it went |
| Undecodable file | mpv error / no video track after 5 s | Picture area → `--bg` with "This print can't be projected." + container/codec in mono | "Open another file" · (web) "Open in Marquee for Windows / Android" |
| No browser codec (web) | capability probe | No Print card naming the exact missing decoder | "Try the WebCodecs path" (only if `VideoDecoder` exists) · release links |
| Missing library file | `stat` fails on scan | Card dims to 40 %, `PRINT MISSING` in mono | "Locate" · "Remove" |
| Worker origin rejected | `403 forbidden-origin` | "This build isn't allowed to talk to the subtitle service." | only ever seen on a fork — the sentence says to set `ALLOWED_ORIGIN` |
| Shader / GL context lost | `FragmentProgram` failure, `webglcontextlost` | Static radial-gradient beam, no dust; nothing else changes | silent; logged nowhere |
| Unexpected Dart error | `FlutterError.onError` / `PlatformDispatcher.onError` | one sentence + "Copy details" (to clipboard, for a manual issue) | **never auto-reported** |

**Two structural rules:** no exception crosses a provider boundary un-typed (`lib/api` maps every
HTTP status to a `ThreadingFailure` before it reaches state), and **nothing retries more than once
automatically**.

### 7.6 The Worker — `marquee-proxy` (mandatory for the web tier)

Native builds do **not** use the Worker: they ship the key via `--dart-define` and call the API
directly. The Worker's 100 000 requests/day is only ever spent by Lite.

**Routes**

| Method + path | Forwarded to | Notes |
|---|---|---|
| `OPTIONS *` | — | Answered by the Worker itself: `204` + CORS when the Origin is allowed, `403` **with no CORS headers** otherwise. **This is the whole reason the Worker exists** |
| `GET /api/subtitles` | `/subtitles` | Params re-sorted alphabetically before forwarding |
| `POST /api/login` · `POST /api/logout` | `/login` · `/logout` | Body streamed through; **never logged, never stored**; `no-store` |
| `GET /api/infos/user` | `/infos/user` | Requires `Authorization` |
| `POST /api/download` | `/download` | **Requires `Authorization`.** Without it → `401 {error:'sign-in-required'}` rather than spending the shared anonymous 5/day/IP pool on the Worker's IP |
| `GET /api/subtitle-file?link=<urlencoded>` | the temporary link | Host must match `opensubtitles.com`, `*.opensubtitles.com` or `*.opensubtitles.org`; content type must be `text/*` or `application/*`; **2 MB cap**; streamed back with CORS. Exists because the temporary link's own CORS posture is unverified |
| `GET /api/utilities/guessit` | `/utilities/guessit` | Allow-listed but optional — keep or delete once day-1 check #4 answers whether it exists |
| `GET /api/tmdb/*` | `https://api.themoviedb.org/3/*` | **Optional, only when the `TMDB_READ_TOKEN` secret is set** (unset → `404 {error:'not-found'}`). A *separate* upstream from `UPSTREAM_BASE`. The `Authorization: Bearer` is built server-side from the var and **never** forwarded from the client. `private, max-age=3600`. This is how Lite gets the Lobby posters that ARCHITECTURE §9.3 and DESIGN §9.1 draw |
| anything else | — | `404 {error:'not-found', sentence:'That endpoint is not proxied.'}` |

**This listing is the single source of truth for the Worker, and DEPLOYMENT §4.3 is byte-identical
to it.** If you change one, change the other in the same commit.

**Invariants — each is a test:**

- `OS_API_KEY` never appears in **any** response body, header or error. A test greps the raw
  serialised response *and* anything written to `console` during the request.
- Origin allow-list: `env.ALLOWED_ORIGIN` (`https://<owner>.github.io`) plus `http://localhost:*` for
  dev. Everything else is `403` **before any upstream fetch**. **No `Origin` header at all → 403**
  (curl and native builds must not route through the proxy).
- A `403` for a rejected origin carries **no** CORS headers — a 403 with `Allow-Origin: *` would
  defeat the allow-list. Its body is still the `WorkerError` JSON
  `{error:'forbidden-origin', sentence:"This build isn't allowed to talk to the subtitle service."}`,
  so Lite has a sentence to print under the stalled leader (ARCHITECTURE §12). **Every** error this
  Worker returns is `WorkerError`-shaped JSON — there is no plain-text error body anywhere.
- `Authorization` is forwarded verbatim and never inspected, logged or persisted. **Nothing else**
  from the client is forwarded: no cookies, no `X-Forwarded-*`, and a client-supplied `Api-Key` is
  **stripped**.
- Upstream status codes pass through unchanged (401/406/410/429 must reach the client so the leader
  can stall correctly), and so do `Retry-After`, `X-RateLimit-Limit`, `-Remaining`, `-Reset`.
- `Cache-Control`: `private, max-age=300` on `GET /api/subtitles`; **`no-store`** on login, logout,
  download and subtitle-file (a cached download link would hand one visitor another visitor's ticket).
  `Set-Cookie` is deleted from every response.
- Path traversal (`/api/../../admin`, `/api/subtitles/../../x`) is normalised and then matched
  against the allow-list → `404`. `/`, `/health` → `404`. `PUT`/`PATCH`/`DELETE` → `405`.
- Per-IP soft cap: **60 requests/minute** via a Cache API counter keyed on `cf-connecting-ip`; over
  it → `429` with `{error:'rate-limited', sentence:"Too many requests from your network — try again
  in a minute."}`. This protects the free allocation from one misbehaving client.
- **No logging.** No `console.*`, no Analytics Engine binding, no KV, no D1 — and **no
  `[observability]` block set to `true`** in `wrangler.toml`: Workers Logs retains request metadata
  server-side, which is exactly what §2.5 forbids. A Biome `noConsole` rule scoped to `worker/` fails
  the build, and TESTING P17 greps `wrangler.toml` for the forbidden blocks.
- Response bodies are **streamed** (`new Response(res.body, res)`), never buffered — the 10 ms CPU
  limit is generous only if nothing calls `arrayBuffer()`.

**`worker/wrangler.toml`**

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

The secret is set once, locally, from `worker/`: `npx wrangler secret put OS_API_KEY`. It is
write-only from then on, survives redeploys, and is **never** in git, never in `wrangler.toml`, and
never in a `VITE_*` variable (that prefix is inlined verbatim into the public bundle). A second,
**optional** secret — `npx wrangler secret put TMDB_READ_TOKEN` — turns on the `/api/tmdb/*` route;
without it that route answers `404 {error:'not-found'}` and Lite falls back to frame grabs.

**`worker/src/index.ts`**

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

**Verify it right after the first deploy:**

```bash
W=https://marquee-proxy.<subdomain>.workers.dev

# 1. Preflight from the real origin -> 204 with CORS headers
curl -i -X OPTIONS "$W/api/subtitles" -H "Origin: https://<owner>.github.io" \
  -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: authorization"

# 2. Wrong origin -> 403, and NO Access-Control-Allow-Origin in the response
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
curl -i -X POST "$W/api/download" -H "Origin: https://<owner>.github.io" \
  -H "Content-Type: application/json" -d '{"file_id":123}'

# 7. subtitle-file with an off-host link -> 403 {"error":"bad-link",...}
curl -i "$W/api/subtitle-file?link=https%3A%2F%2Fevil.example%2Fx.srt" \
  -H "Origin: https://<owner>.github.io"

# 8. TMDB route -> 200 with the token set, 404 {"error":"not-found",...} without it;
#    the token never appears in the body either way.
curl -s "$W/api/tmdb/find/tt0041959?external_source=imdb_id" \
  -H "Origin: https://<owner>.github.io" | head -c 200
```

**Budget:** expected traffic is a few hundred requests a day. The free plan's 100 000/day
**hard-fails with error 1027 rather than billing**, and there is no card on the account. The origin
allow-list is what stops someone else spending the quota.

### 7.7 Content-Security-Policy for Lite

```
default-src 'self';
connect-src 'self' https://marquee-proxy.<subdomain>.workers.dev https://api.themoviedb.org https://image.tmdb.org;
img-src 'self' data: blob: https://image.tmdb.org;
media-src 'self' blob:;
worker-src 'self' blob:;
script-src 'self' 'wasm-unsafe-eval';
style-src 'self' 'unsafe-inline';
object-src 'none';
base-uri 'none'
```

`'wasm-unsafe-eval'` is there **only** for JASSUB. A test asserts no off-origin request leaves the
landing page.

`https://api.themoviedb.org` is in `connect-src` because the Worker's `GET /api/tmdb/*` route (§7.6)
is the *default* path for Lite's metadata but not the only one: a fork that sets no `ALLOWED_ORIGIN`
of its own can point `config.ts` straight at TMDB with the user's own token. `https://image.tmdb.org`
stays in `img-src`/`connect-src` because artwork is fetched directly — it is a public CDN with no key.
Both are optional: with no TMDB token anywhere, Lite shows frame grabs and never touches either host.

---

## 8. Platform integration

### 8.0 `pubspec.yaml` — the complete file

This is the whole manifest; the §2.2 table is the rationale for it. Paste it verbatim over what `flutter create` generates, then `flutter pub get` and
`dart run build_runner build --delete-conflicting-outputs`.

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

Three things here are easy to get wrong and expensive to notice late:

1. **`flutter_riverpod` is not optional.** It is the state layer (§2.2, §5.4) — `threadingProvider` and `houseProvider` are Riverpod providers, and §2.8's structural law (“UI widgets never call `lib/api` or `lib/db` directly, only providers do”) has no meaning without it.
2. **All four `assets:` entries are required.** `assets/icons/` (flutter_svg) and `assets/sounds/` (flutter_soloud) are not bundled unless declared, and `design/cue-sheet.json` sits outside `assets/` — without that exact line the `?` overlay has nothing to read at runtime (§3.10, §4.3, §10.7 G10).
3. **`*.g.dart` is gitignored.** drift generates `lib/db/database.g.dart`; every CI job runs `dart run build_runner build --delete-conflicting-outputs` after `flutter pub get` and **before** `flutter analyze` (§11.2, §11.4). A fresh clone that skips it fails to analyse.

### 8.1 Playback configuration (both native platforms)

```dart
// lib/player/engine.dart
await MediaKit.ensureInitialized();          // once, in main() before runApp

final player = Player(
  configuration: const PlayerConfiguration(
    libass: true,
    libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
    libassAndroidFontName: 'Noto Sans',      // the TTF's INTERNAL family name, not the filename
    bufferSize: 64 * 1024 * 1024,
    title: 'Marquee',
  ),
);
final controller = VideoController(
  player,
  configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
);

await player.open(Media(path));
await player.setSubtitleTrack(SubtitleTrack.uri(srtPath, title: 'English', language: 'en'));

// mpv property bridge (desktop extras + sub-delay on both):
final np = player.platform as NativePlayer;
await np.setProperty('sub-delay', '0.35');
await np.setProperty('glsl-shaders', 'shaders/Anime4K_Clamp_Highlights.glsl');   // Windows only
final fps = await np.getProperty('container-fps');
final chapters = await np.getProperty('chapter-list');
```

**Rules that are load-bearing, not preferences:**

- **Never set `vo: 'mediacodec_embed'`.** mpv disables subtitle rendering, the OSD and video filters
  under that video output — the symptom is "video plays, subtitles silently invisible". Keep
  media_kit's Android defaults: `vo=gpu`, `gpu-context=android`, `hwdec=auto-safe`,
  `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`, `sub-font-provider=none`. An integration
  test reads these properties back and **fails the build** if `vo` is ever anything but `gpu` while
  libass is on.
- **`libassAndroidFontName` must be the TTF's internal family name.** Get it wrong and subtitles are
  invisible on Android while working perfectly on Windows. Verify with any font inspector that the
  family really is `Noto Sans`.
- Throttle `player.stream.*` to **10 Hz** before it reaches the UI. The folio only needs whole
  seconds; rebuilding at 60 Hz burns the frame budget you need for the beam.
- Dispose the `Player` when leaving the Auditorium. A leak test opens and closes the same file 30
  times and asserts no monotonic memory growth (< 10 % over the first-open baseline) and no leaked
  `Player` (finalizer counter).

### 8.2 Android

**`android/app/src/main/AndroidManifest.xml`** — everything absent from this list is absent on
purpose (no camera, no location, no notifications, no exact alarms, no `MANAGE_EXTERNAL_STORAGE`, no
network-state snooping):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <!-- keep-screen-on during playback (wakelock_plus) -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <!-- MediaStore library scan only. SAF ("Open with", the file picker) needs NONE of these. -->
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
        android:hardwareAccelerated="true"
        android:largeHeap="true"
        android:enableOnBackInvokedCallback="true">   <!-- predictive back -->

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:supportsPictureInPicture="true"
            android:resizeableActivity="true"
            android:screenOrientation="fullUser"
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

            <!-- containers Android does not map to video/* -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="content" />
                <data android:mimeType="application/x-matroska" />
                <data android:mimeType="application/octet-stream" />
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

**`configChanges` is load-bearing:** without `orientation|screenSize|smallestScreenSize|screenLayout`
Android recreates the Activity on rotation, which restarts libmpv and loses the frame mid-film.

**`android/app/build.gradle.kts`** — merge these blocks into the file `flutter create` generates; do
not replace it:

```kotlin
import java.io.File

// Present only in CI; a local build without it still works and signs with the debug key.
val ksFile: String? = System.getenv("ANDROID_KEYSTORE_FILE")

android {
    namespace = "com.rahul.marquee"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17     // R1: Temurin 17 everywhere
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        // NEVER changes after the first install — it is the identity of every future update.
        applicationId = "com.rahul.marquee"
        minSdk = 26                          // R2: Android 8.0+
        targetSdk = 36
        versionCode = flutter.versionCode    // from --build-number
        versionName = flutter.versionName    // from --build-name
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
            // Keep R8 OFF: media_kit reaches libmpv through JNI and reflection, and a stripped
            // build fails at RUNTIME rather than at build time. Size is controlled by ABI splits.
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

`--split-per-abi` on the Flutter command line produces the three APKs. **Do not also add a
`splits { abi { … } }` block** — the two mechanisms fight.

**Two small Kotlin channels — no third-party plugin:**

| Channel | File | ~Lines | What it does |
|---|---|---|---|
| `marquee/pip` | `PipChannel.kt` | 60 | `enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(w,h)).setAutoEnterEnabled(true).build())`, plus `onPictureInPictureModeChanged` pushed back to Dart so the UI drops **all** chrome |
| `marquee/mediastore` | `MediaStoreChannel.kt` | 150 | `MediaStore.Video.Media.EXTERNAL_CONTENT_URI` query in **pages of 500** (`_ID`, `DISPLAY_NAME`, `SIZE`, `DURATION`, `WIDTH`, `HEIGHT`, `DATE_ADDED`, `RELATIVE_PATH`) → the library rail without a full-storage permission |

**Dart-side platform work:** `file_picker` for SAF `ACTION_OPEN_DOCUMENT`, and
`OPEN_DOCUMENT_TREE` + `takePersistableUriPermission` for library folders (stored in
`folders.grant_blob`, and they must still work after a reboot); `wakelock_plus` **during playback
only**; `screen_brightness` for the left edge dimmer, **restored on dispose**; `edgeToEdge` in the
Lobby and `immersiveSticky` while controls are hidden; predictive-back callbacks registered by the
Booth sheet and the Threading screen.

**Subtitle writing on Android:** if the video came from a **writable tree URI**, write the sidecar
beside it via SAF `DocumentsContract.createDocument`. If not (a plain `content://` from another app),
write to app-private storage and let the Booth row read `saved in app storage` instead of `saved
beside file` — honest, and the `hash_cache` row works identically. Never overwrite an existing
sidecar: add a `.1` suffix.

**Performance defaults on Android:** the beam shader is capped at DPR 1.0 and **paused during
playback**; bias light stays **opt-in** until you measure it (§9 step 4.9), then the default is set
by the measurement and the Ticket Office says why.

### 8.3 Windows

- `window_manager` for a **frameless window whose drag region is the marquee sign**; three bulb
  window controls (minimise / maximise / close).
- `flutter_acrylic` Mica **in the Lobby only** — the Auditorium is opaque `#07060A` so the picture is
  never composited over a translucent surface.
- A command-line argument opens a file directly: `marquee.exe "D:\films\x.mkv"` plays without passing
  through the Lobby.
- `hwdec=auto-safe` with D3D11VA; `glsl-shaders` presets (Anime4K, MIT) exposed in the Ticket Office
  through the mpv property API.
- Window size and position persist between runs.
- **The zip is the product.** No installer in v1. What must be inside: `marquee.exe`,
  `flutter_windows.dll`, **`libmpv-2.dll`**, the `data/` folder, and the MSVC runtime DLLs Flutter
  bundles (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`). The release workflow asserts
  the first four exist **before** zipping — a build missing `libmpv-2.dll` starts and then plays
  nothing.
- **The exe is unsigned.** SmartScreen will say "Windows protected your PC" on first run. Code-signing
  certificates cost money, so this is permanent: say so in the README **before** the user meets it,
  and publish the SHA-256 next to the zip as the mitigation you can afford.
- **DLL provenance is a licence matter.** `tools/libmpv-windows.sha256` pins the shipped DLL's hash
  and CI checks it. Any refresh must come from an **`-lgpl-`** package.

### 8.4 Web vs Android vs Windows — the honest differences

| Capability | Windows | Android | Marquee Lite (web) |
|---|---|---|---|
| Codec reach | Everything libmpv decodes | Everything libmpv decodes | Whatever the browser has; the capability line says so |
| ASS/SSA | libass (full typesetting) | libass (full typesetting, bundled fonts only) | JASSUB, **single-threaded** on Pages (no COOP/COEP) |
| Subtitle delay | mpv `sub-delay` | mpv `sub-delay` | re-emit the shifted VTT |
| Subtitle storage | sidecar beside the file | sidecar beside the file, or app storage | IndexedDB (converted VTT) |
| OpenSubtitles | direct, key via `--dart-define` | direct, key via `--dart-define` | **only** through the Worker |
| Library | user-chosen folders | MediaStore + SAF grants | File System Access (Chromium desktop) as progressive enhancement only |
| Bias light | `player.screenshot` every 500 ms | every 1000 ms, **opt-in** | `requestVideoFrameCallback` |
| Beam | Impeller fragment shader, DPR ≤ 1.5 | Impeller shader, DPR ≤ 1.0 | CSS gradient + clip-path (optional GLSL-ES upgrade) |
| PiP | — | yes | — |
| Haptics | — | yes | none |
| Input | keyboard-complete + mouse | gestures | keyboard + pointer |

---

## 9. Build order, with checkpoints

Effort unit: an *evening* ≈ 2 h, a *weekend day* ≈ 6 h. Total to `v1.0.0` ≈ **136 h** — the sum of
the six phase headers below (16 + 24 + 38 + 26 + 16 + 16). **Tasks marked ⚑ are the 16.5-hour Weekend
MVP fast path** (§9.8) — two full 8-hour days, not one evening plus a Saturday.

Two working agreements govern the order:
**Day 1 = live** — Phase 0 ends with Lite on GitHub Pages, the Worker deployed and a `v0.0.1`
Release carrying a Windows zip and three APKs, *before a single feature exists*.
**Engine first** — Phase 2 writes `lib/engine/` with tests and golden data *before* it gets a face;
Phase 1's screens are deliberately fed placeholder data. Phases 1 and 2 are genuinely parallel.

```
0 Setup (live on day 1) ──► 1 Design system + skeleton screens ──► 3 Polish, motion, sound ──► 5 Test & launch ──► 6 Stretch
        └───────────────► 2 Engine + core feature ──────────────►┘        └──► 4 Android packaging ──►┘
```

### 9.1 Phase 0 — repo, tooling, CI, live hosting, secrets (~16 h)

- [ ] **0.1 ⚑ Create the public repo and the licence trail.** `marquee` on GitHub; MIT `LICENSE`;
      `.gitignore` (Flutter + Node + `*.p12` + `*.jks` + `*.keystore` + `android/local.properties` +
      `android/key.properties` + `.env` + **`**/*.g.dart` and `**/*.drift.dart`** — drift's generated
      code is never committed; every CI job regenerates it with `dart run build_runner build
      --delete-conflicting-outputs` right after `flutter pub get` and **before** `flutter analyze`); `.gitattributes` (`* text=auto eol=lf`, `*.bat text
      eol=crlf`, `android/gradlew text eol=lf`, binary rules for `*.png *.ttf *.mkv *.mp4 *.webm
      *.avi`); `LICENSES/` with LGPL-2.1, LGPL-3.0, ISC and OFL texts plus links to the two media_kit
      build-script repos.
      **Verify:** the repo is public; `LICENSES/` has five files; `git log` shows one commit. *(0.5 e)*
- [ ] **0.2 Day-1 API verification spike.** Create the OpenSubtitles consumer key and a free account,
      then `curl` to settle: (a) does `GET /utilities/guessit?filename=…` exist? (b) does
      `moviehash_match=only` work? (c) what is the download `link`'s TTL (fetch, wait 5/30/120 min,
      watch for 410)? (d) is there a per-second rate limit (fire 20 searches, read `X-RateLimit-*`)?
      (e) confirm `imdb_id 41959` / `tmdb_id 1092` for *The Third Man*.
      **Verify:** five dated answers written into `docs/RESEARCH.md`; anything that changes a design
      decision is reflected in code in the same commit. *(1 e)*
- [ ] **0.3 Decide the local dev loop.** Either install Flutter SDK + **Visual Studio 2022 Build Tools
      ("Desktop development with C++")** — ~7 GB, free, the one local-toolchain exception — or commit
      to CI-only and read `flutter analyze`/test output from Actions. **Android stays CI-only
      forever either way.**
      **Verify:** either `flutter doctor` shows the Windows toolchain ✓, or `ci.yml` runs
      `flutter analyze` on every push and you have used it once. *(1 e, or 0)*
- [ ] **0.4 ⚑ Scaffold the Flutter app and prove libmpv plays something.**
      `flutter create --org com.rahul --project-name marquee --platforms=windows,android .`
      This produces **R5** directly — `namespace`/`applicationId` `com.rahul.marquee` and the Kotlin
      source already at `android/app/src/main/kotlin/com/rahul/marquee/`, so there is no rename step
      and no directory to move. Add `media_kit`, `media_kit_video`, `media_kit_libs_video`; build a
      one-screen app with a file picker and a `Video` widget.
      **Verify:** a 1080p MKV plays **with sound** on Windows (locally, or from a CI-built zip you
      download and run). *(0.5 wd)*
      *If Flutter is not installed locally:* generate `android/` and `windows/` once with a throwaway
      `workflow_dispatch` job that runs the `flutter create` line above and uploads the trees as an
      artifact; download, commit, delete the job. Everything after that is CI-built.
- [ ] **0.5 Pin the toolchain.** Commit `pubspec.lock`; pin Flutter in `.fvmrc` **and** in
      `subosito/flutter-action@v2` (`flutter-version:`, never `channel: stable` alone).
      **Verify:** `ci.yml` and `release.yml` name the same exact Flutter version. *(0.5 e)*
- [ ] **0.6 ⚑ Write `scripts/tokens.mjs`.** One source (§3.12) → `web/src/styles/tokens.css` +
      `lib/theme/tokens.dart`: colours, type scale, spacing, radii, shadows, durations, easings,
      spring constants.
      **Verify:** `node scripts/tokens.mjs && git diff --exit-code` is clean, and `Tokens.accent` in
      Dart equals `--accent` in CSS. *(1 e)*
- [ ] **0.7 ⚑ Scaffold Marquee Lite.** `npm create vite@latest web -- --template vanilla-ts`; wire
      `base: process.env.VITE_BASE_PATH ?? '/'`; Fontsource variable fonts; `tokens.css`; a landing
      page with the lit `MARQUEE` sign and a drop frame that does nothing yet.
      **Verify:** `npm run build` succeeds and the page uses **only** token variables — no hard-coded
      hex anywhere. *(0.5 e)*
- [ ] **0.8 ⚑ Go live on GitHub Pages.** Add `pages.yml` (§11.3) building inside `web/` with
      `VITE_BASE_PATH: /marquee/`; **Settings → Pages → Source: "GitHub Actions"**.
      **Verify:** `https://<owner>.github.io/marquee/` shows the lit sign **on a phone browser**, and
      `curl -s <url> | grep 'src='` shows every asset path starting with `/marquee/`. *(0.5 e)*
- [ ] **0.9 ⚑ Deploy the Worker.** `worker/src/index.ts` from §7.6; `wrangler.toml` with
      `ALLOWED_ORIGIN` and `UPSTREAM_BASE`; `npx wrangler secret put OS_API_KEY`; add `worker.yml`.
      **Verify:** all five probes in §7.6 behave as documented — 204 preflight, 403 from a wrong
      origin, 403 with no Origin, 200 JSON from the real origin with `grep -c "$OS_API_KEY"` printing
      **0**, and 404 outside the allow-list. *(1 e)*
- [ ] **0.10 Generate and register the signing key.** Run the PKCS12 keystore script **outside** the
      repo (`openssl req` + `openssl pkcs12 -export`; the key password must equal the store password).
      Add secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
      (`release`), `ANDROID_KEY_PASSWORD`, `OS_API_KEY`, `CLOUDFLARE_API_TOKEN`,
      `CLOUDFLARE_ACCOUNT_ID`, optional `TMDB_READ_TOKEN`.
      **Verify:** eight secrets listed in repo settings, and the `.p12` + passphrase live in your
      password manager **and** one offline copy. **Losing this file ends the update path for every
      installed APK.** *(0.5 e)*
- [ ] **0.11 ⚑ Write `release.yml` and cut `v0.0.1`.** The matrix in §11.4.
      **Verify:** `git tag v0.0.1 && git push --tags` produces a Release with
      `marquee-0.0.1-windows-x64.zip` and three APKs in **under 25 minutes**; the arm64 APK installs
      on the phone and plays a file. Then `gh release edit v0.0.1 --prerelease`. *(0.5 wd)*
- [ ] **0.12 Write `ci.yml`** (§11.2). Build order in every Dart job, in this order and no other:
      `flutter pub get` → **`dart run build_runner build --delete-conflicting-outputs`** →
      `dart format --set-exit-if-changed` → `flutter analyze --fatal-infos` → `flutter test`.
      The codegen step is not optional: drift writes `lib/db/database.g.dart`, `*.g.dart` is
      **gitignored and never committed**, and on a fresh checkout `flutter analyze` fails on the
      missing `part` without it. Then web Vitest, worker Vitest, Playwright, and the checks job
      (tokens drift, fixtures drift, parity, licences, secrets). Biome for `web/` + `worker/` with
      **`noConsole` scoped to `worker/`**.
      **Verify:** a PR containing `console.log` in `worker/src/index.ts` **fails CI**, and a clone with
      no generated files still goes green. *(1 e)*
- [ ] **0.13 Write `scripts/make-fixtures.sh` and commit the fixtures** (§10.2).
      **Verify:** running the script twice produces identical bytes;
      `make-fixtures.sh && git diff --exit-code test/fixtures` is a CI check. *(1 e)*
- [ ] **0.14 Timeboxed spike (2 h, then stop): the Windows `libmpv-2.dll` swap.** Drop a current
      `mpv-dev-**lgpl**-x86_64-*` DLL over the one media_kit ships and see whether the app still runs.
      **Ship the bundled DLL either way.**
      **Verify:** a dated paragraph in RESEARCH saying "works" or "does not work, symptom X". *(1 e)*

**Phase 0 is done when:** Lite is live at a public URL; the Worker proxies a real OpenSubtitles
search; one `git push --tags` produced a Release with a Windows zip and three signed APKs; `ci.yml`
is green; fixtures and tokens are generated and drift-checked; and every day-1 unknown has a written
answer.

### 9.2 Phase 1 — design system and skeleton screens (~24 h)

Every screen exists, is navigable, and looks like the design — fed entirely by placeholder data.
No network, no libmpv beyond a still frame. **The beam shader is NOT in this phase** — resist
starting it; a half-built shader makes every golden unstable.

- [ ] **1.1 Build/refresh `design/preview.html`** — Lobby (night + Matinee), Threading mid-sweep,
      Auditorium with controls, Booth sheet. Static HTML/CSS using `tokens.css` only.
      **Verify:** four screens render at 390 px and 1440 px; every colour is a token; a screenshot of
      each is committed to `design/`. *(0.5 wd)*
- [ ] **1.2 Wire `tokens.dart` into `ThemeData`** plus a `HouseTheme` inherited widget carrying the
      Auditorium/Matinee split and the `--house` value.
      **Verify:** `test/theme/tokens_test.dart` asserts every contrast pair in §3.2 within ±0.15. *(1 e)*
- [ ] **1.3 Load fonts for tests.** `test/flutter_test_config.dart` registers Big Shoulders Display,
      Geist, Geist Mono and Noto Sans via `FontLoader`, sets the golden comparator tolerance to
      **0.5 %**, and installs `Clock.fixed(2026-09-06T15:44Z)`.
      **Verify:** a trivial golden of the word `MARQUEE` renders in Big Shoulders, **not Ahem**. *(0.5 e)*
- [ ] **1.4 Primitives, batch A:** `Bulb` (off/on/warming/flicker), `MarqueeSign`, `Folio`, `Chip`,
      `ToggleBulb`, `UnderlineInput`, `SentenceBanner`.
      **Verify:** a widget-catalogue route shows every state; goldens committed for each. *(0.5 wd)*
- [ ] **1.5 Primitives, batch B:** `TicketStrip`, `CandidateRow` (match / by-name / HI / selected /
      downloading / attached), `FilmGate` (static: sprockets, buffered range, frame-in-gate),
      `SyncRuleReadout`, `TransportMark`.
      **Verify:** goldens for every state listed in §4. *(0.5 wd)*
- [ ] **1.6 Lobby skeleton.** Sky band, marquee sign, velvet rail with three placeholder cards, Open
      disc, doors drop target, attribution line, three ambience bulbs, empty state.
      **Verify:** matches the preview at phone and desktop widths; drag-over brightens the doors. *(1 e)*
- [ ] **1.7 Threading skeleton.** Leader numeral with a conic sweep driven by a fake `Ticker`, hash
      line, candidate list, ticket strip, Skip link.
      **Verify:** a debug button steps 3 → 2 → 1 → flash; a second button **freezes the sweep
      mid-numeral**. *(1 e)*
- [ ] **1.8 Auditorium skeleton.** Folio, black picture area, aisle lights, film gate, transport
      marks, sync readout; auto-hide after 2400 ms; every §4.3 state reachable from a debug menu.
      **Verify:** controls hide and return; the folio stays at 40 %; focus rings visible on every
      mark. *(0.5 wd)*
- [ ] **1.9 Booth sheet + Ticket Office skeletons.** The sheet rises on the 380/32 spring to 70 % and
      drag-dismisses; Ticket Office rows, ticket strip, attribution block with the **exact** TMDB
      notice and the OpenSubtitles credit.
      **Verify:** both match the preview; the sheet **never exceeds 70 %** so the frame stays visible. *(1 e)*
- [ ] **1.10 Windows chrome.** `window_manager` frameless window; the marquee sign is the drag region;
      three bulb window controls; `flutter_acrylic` Mica **in the Lobby only**.
      **Verify:** dragging the sign moves the window; maximise/restore/close work; the Auditorium is
      **not** translucent. *(1 e)*
      *If Mica misbehaves on the current Flutter, drop to a flat `--bg` Lobby and note it — it is
      decoration, not a feature.*
- [ ] **1.11 Lite skeleton.** The same structure in `web/src/ui/`: landing with drop frame, leader
      overlay, No Print card, Booth sheet. Tokens only, no framework.
      **Verify:** Playwright screenshots of the landing match `design/preview.html` within the
      visual-diff threshold. *(0.5 wd)*
- [ ] **1.12 Accessibility and reduced-motion pass.** Focus rings everywhere, ≥ 44 × 44 px targets
      (gate 56 px), `role="slider"` + `aria-valuetext` on the gate and the sync rule, an `aria-live`
      region for the leader, `MediaQuery.disableAnimations` / `prefers-reduced-motion` branches.
      **Verify:** `@axe-core/playwright` reports **zero** violations on Lite; Flutter
      `meetsGuideline(textContrastGuideline)` and `androidTapTargetGuideline` pass. *(1 e)*

**Phase 1 is done when:** you can walk Lobby → Threading → Auditorium → Booth → Ticket Office and
back with placeholder data on Windows and in the browser; goldens exist for every component state;
and the app does not look worse than the preview.

### 9.3 Phase 2 — engine and the core feature (~38 h)

- [ ] **2.1 ⚑ `hash.dart` + `hash_test.dart`** (§6.2), including the `no_flutter_imports_test.dart`
      guard. **Verify:** all six vectors pass — including `0xFF`×131 072 → `000000000001c000` and the
      131 071-byte `FileTooSmall` — at **100 % line coverage**. *(1 e)*
- [ ] **2.2 `filename.dart` + goldens** (§6.3), anime brackets included.
      **Verify:** all eight golden filenames produce the exact expected records, including
      `movie.mkv → confidence: low`. *(0.5 wd)*
- [ ] **2.3 ⚑ `scoring.dart` + goldens** (§6.4).
      **Verify:** the A/D/C/B/E ranking reproduces to **2 decimal places**; `machine_translated` is
      listed with `autoPick: false`; the list is ordered, never filtered. *(1 e)*
- [ ] **2.4 `timecode.dart`, `sync_rule.dart`, `detents.dart` + goldens** (§6.7–6.9).
      **Verify:** `4364.4 / 9663 → 01:12:44 · −01:28:19`; `+0.376 → +0.40` (round, not floor); the
      152 px / 160 px detent pair behaves exactly as specified. *(1 e)*
- [ ] **2.5 `tickets.dart` + goldens** (§6.6).
      **Verify:** all eight quota inputs produce the exact strip text, colour, state and aria-label;
      `allowed_downloads` is **never** hard-coded. *(0.5 e)*
- [ ] **2.6 `srt.dart` + goldens** (§6.11) — BOM, CRLF, out-of-order cues, `<i>`, `{\an8}`, shift
      with clamp. **Verify:** `sample-crlf-bom.srt` converts **byte-for-byte** to the expected VTT. *(0.5 e)*
- [ ] **2.7 ⚑ `threading.dart` state machine + tests** (§6.5).
      **Verify:** every transition is covered; a rejected phase **freezes `sweep` at its current
      value** and publishes the correct `next[]`; `FileTooSmall` produces **no** error UI; exactly
      one automatic retry exists (the 410). *(0.5 wd)*
- [ ] **2.8 ⚑ `opensubtitles.dart` + `net.dart` against `MockClient`.** Sorted params, mandatory
      headers, `Retry-After` handling, 401/406/410/429 → typed `ThreadingFailure`.
      **Verify:** a test asserts the outgoing query string is **alphabetically sorted**; every fixture
      JSON in §10.3 parses. *(1 e)*
- [ ] **2.9 `subdl.dart`** — keyed search, **anonymous** zip download, in-memory unzip with the size
      and traversal guards. **Verify:** the `subdl-zip.bin` fixture yields one `.srt`; a zip with a
      `../` entry is **rejected**. *(1 e)*
- [ ] **2.10 drift schema, DAOs, migration test** (§5.2).
      **Verify:** `hash_cache` lookups are indexed; the artwork sweep deletes rows older than 180
      days; a `watch()` query drives a live list; a migration preserves every row. *(1 e)*
- [ ] **2.11 ⚑ `player/engine.dart`** (§8.1) — lifecycle, 10 Hz throttled streams, `container-fps`
      and `chapter-list` reads, `sub-delay` writes.
      **Verify:** all twelve corpus files (§12) play on Windows with hardware decode;
      `chapter-list` populates the gate detents. *(0.5 wd)*
- [ ] **2.12 `player/tracks.dart`** — enumerate embedded audio and subtitle tracks, switch them,
      attach an external `SubtitleTrack.uri(path)`.
      **Verify:** the fixture MKV's embedded SRT **and** ASS tracks both list and both render, with
      correct `\pos` and `\an8`. *(1 e)*
- [ ] **2.13 ⚑ Wire Threading to the real machine.** `threadingProvider`; the sweep driven by real
      promises; candidate rows from `scoring.dart`; the ticket strip from the real `/download`
      response.
      **Verify:** opening a hash-hit file lights the MATCH bulb and shows a real `remaining`; killing
      the network mid-search **freezes the numeral** and slides in the fallback rows within 500 ms. *(0.5 wd)*
- [ ] **2.14 ⚑ Sidecar write + `hash_cache`.** Save as `<video>.<lang>.srt` beside the file (with the
      `.1` collision rule), record the cache row, and check **sidecar → cache → network** in that
      order on every open.
      **Verify:** reopening the same file uses **0** downloads and shows the same MATCH state;
      deleting the sidecar while keeping the row prompts a clean re-fetch, not a crash. *(1 e)*
- [ ] **2.15 Ticket Office sign-in.** username/password → `/login` → JWT in `flutter_secure_storage`;
      **the password is never retained**; 401 → "Ticket expired — sign in again"; quota from
      `user.allowed_downloads`; sign-out clears the token.
      **Verify:** the strip changes from `ANONYMOUS · 5 PER DAY PER IP` to `n OF <allowed> TONIGHT`. *(1 e)*
- [ ] **2.16 Keyboard cue sheet.** One `design/cue-sheet.json` feeding **both** the `?` overlay and
      the README; bind every shortcut in §4.3.
      **Verify:** every listed key works on Windows and the overlay is generated from the JSON, not
      hand-written. *(0.5 e)*
- [ ] **2.17 ⚑ Port the engine to TypeScript.** `osHash.ts`, `srt2vtt.ts`, `scoring.ts`,
      `filename.ts`, `tickets.ts`, `timecode.ts`, `syncRule.ts`, `capability.ts`, `threading.ts` —
      **sharing the same golden tables**.
      **Verify:** Vitest reproduces every Dart golden, and `scripts/check-parity.mjs` passes. *(0.5 wd)*
- [ ] **2.18 ⚑ Harden the Worker** to §7.6 in full.
      **Verify:** `worker/test/worker.test.ts` covers every invariant, including "the key never
      appears in any response". *(1 e)*
- [ ] **2.19 ⚑ Lite end to end.** Drop → capability probe → `osHash` → Worker search → auto-pick →
      download → SRT→VTT `<track>` → play. JASSUB lazy-loaded for `.ass`. IndexedDB cache so a reopen
      is free and works offline.
      **Verify:** an MP4/H.264 plays **with subtitles in under 3 s**; an unplayable file shows the No
      Print card naming the missing decoder in **under 1 s**. *(0.5 wd)*
- [ ] **2.20 Lite sign-in + ticket strip.** Login through the Worker; the JWT sealed with a
      non-extractable WebCrypto key; a "this session only" option.
      **Verify:** the strip shows real quota; refusing to store the token keeps it in memory only. *(1 e)*

**Phase 2 is done when:** on Windows, dropping a hash-matched 1080p MKV attaches synced English
subtitles with **zero clicks in under 3 s**; reopening it costs **zero** downloads; unplugging the
network stalls the leader at "2" with a sentence and a working "Play without subtitles"; and the same
ritual works in Lite for browser-playable codecs. Coverage: **100 %** on `hash`, `scoring`,
`timecode`, `sync_rule`, `tickets`; ≥ 90 % on the rest of the engine.

### 9.4 Phase 3 — polish, motion, sound (~26 h)

- [ ] **3.1 The `--house` system.** One provider tweened 1 → 0 over 900 ms on `--ease-house`, driving
      wall luminance, sky opacity, bulb intensity and beam width **simultaneously**; reversed on
      leaving; 240 ms crossfade under reduced motion.
      **Verify:** dropping a file visibly dims the room *before* the leader starts, and a grep proves
      there is no second tween. *(1 e)*
- [ ] **3.2 `beam.frag`** (timeboxed to half a weekend day). Cone in `--accent` at 8–14 % alpha,
      3-octave value noise, ~200 dust sprites; uniforms `angle`, `width`, `time`, `house`; DPR capped
      1.5 / 1.0; paused on `visibilitychange` and during playback; **static radial-gradient fallback**
      on shader failure or reduced motion.
      **Verify:** ≤ 2 ms/frame in `perf_test.dart`; deleting the shader asset falls back **without an
      exception**. *(0.5 wd)*
- [ ] **3.3 Bias light.** `bias_light.dart` + the throttled sampler (500 ms desktop / 1000 ms Android,
      top-80 % crop) + the 5-stop wall gradient with the 600 ms lerp.
      **Verify:** the §6.10 goldens pass; an all-black frame keeps `--focus` at 6 %; sampling stops
      when paused; ≤ 2 ms per sample. *(0.5 wd)*
- [ ] **3.4 Film gate, full.** Chapter/5-min detents with the 6 px capture radius, spring snap, FINE
      mode, first-run 12 px nudge, buffering flicker at 2 Hz, selection haptics.
      **Verify:** the §6.9 detent table reproduces on a real drag; the nudge fires once and is
      remembered. *(1 e)*
- [ ] **3.5 Thumbnail strip in the gate.** A second muted `hwdec=no` player builds a cached JPEG strip
      after open; **if it stalls for > 3 s, fall back to timecode-only silently**.
      **Verify:** dragging pulls thumbnails through the gate on Windows; on Android the fallback
      engages without jank. *(1 e)*
- [ ] **3.6 Sync rule UI.** The mono ruler under a fixed caret, 50 ms detents with selection haptics,
      `J`/`K` and `Shift` steps, long-press reset, per-hash memory surfaced as the `±0.35` Lobby chip.
      **Verify:** the value is written live to mpv `sub-delay`; reopening the same file restores it;
      a different hash starts at 0.00. *(1 e)*
- [ ] **3.7 Ticket tear.** `clip-path` tear + medium haptic + paper rip; the count decrements **after**
      the animation; at 2 left the strip turns crimson with the sign-in / Subdl sentence.
      **Verify:** a widget test asserts the decrement **order**, and crimson is the only crimson
      element on that screen. *(0.5 e)*
- [ ] **3.8 Marquee warm-up, sky band, night flicker.** Title spelled letter by letter (60 ms stagger,
      capped at 24), sky band from the injected clock, 0.5 % bulb flicker at local night, Matinee for
      Lobby/Booth/Ticket Office **only**.
      **Verify:** with the clock fixed at 21:14 IST the bulbs are lit and flickering; at 11:00 they
      are painted and the sky is at full strength. *(1 e)*
- [ ] **3.9 Sound and haptics.** The §3.9 table, each behind one bulb; silent during playback; honours
      the OS silent switch.
      **Verify:** every event fires **once and only once**; turning both bulbs off makes the app
      silent and still. *(1 e)*
- [ ] **3.10 Booth sheet, full.** Track list, style presets applied **live** via mpv `sub-*`, position,
      the sync rule, "Find another print" (re-runs rungs 3–4 **without leaving the sheet**), ticket
      count.
      **Verify:** changing size or outline updates the paused frame immediately; "Find another print"
      never closes the sheet. *(0.5 wd)*
- [ ] **3.11 TMDB posters and per-title accent.** `/find/{imdb_id}` → poster/backdrop;
      `material_color_utilities` → per-title accent; `expires_at = +180 days` with a startup sweep;
      logo + exact notice wherever artwork appears.
      **Verify:** disabling TMDB removes every network call to it **and** the logo; an artwork row
      older than 180 days is deleted on launch. *(1 e)*
- [ ] **3.12 Lite motion parity.** House-down as a CSS `@property --house` tween, a View Transition on
      library → player, the JASSUB canvas over the video, `requestVideoFrameCallback` bias light,
      Howler + Web Audio for the same sound set.
      **Verify:** Playwright visual specs match the preview; `prefers-reduced-motion` kills dust and
      parallax but keeps the honest leader. *(0.5 wd)*
- [ ] **3.13 Grain, shadows, one-accent audit.** Grain in the Lobby and sheets only (**0 in the
      Auditorium**); every shadow falls down; a manual sweep for "more than one accent per screen".
      **Verify:** no grain over the picture; the crimson budget holds on every screen. *(0.5 e)*

**Phase 3 is done when:** side by side, the running app and `design/preview.html` are
indistinguishable at phone and desktop widths; 60 fps during playback with the beam and bias light
on; and the reduced-motion build still stalls the leader honestly.

### 9.5 Phase 4 — Android packaging and the phone experience (~16 h)

- [ ] **4.1 Manifest and build config** (§8.2). **Verify:** "Open with → Marquee" appears for an MKV
      in a file manager, and **rotating during playback does not restart libmpv**. *(1 e)*
- [ ] **4.2 ⚑ libass on the device.** Bundle `NotoSans-Regular.ttf`; set `libassAndroidFont` +
      `libassAndroidFontName: 'Noto Sans'`; keep `vo=gpu` and `hwdec=auto-safe`.
      **Verify:** the fixture `.ass` renders with correct `\pos` and `\an8` on a real phone,
      **identical to Windows**. *(1 e)*
- [ ] **4.3 `PipChannel.kt`.** **Verify:** pressing home during playback enters PiP with no controls;
      returning restores the full Auditorium at the same position. *(1 e)*
- [ ] **4.4 `MediaStoreChannel.kt` + SAF grants.** **Verify:** the Lobby rail fills from the phone's
      videos **without a full-storage permission**, and a granted folder still works after a reboot. *(0.5 wd)*
- [ ] **4.5 Edge-to-edge, insets and back.** **Verify:** nothing sits under the status/navigation
      bars, and the predictive-back preview shows the room, not a blank page. *(1 e)*
- [ ] **4.6 Gestures and haptics** (§4.3). **Verify:** the back gesture never fires while scrubbing,
      and brightness returns to the system value after leaving. *(1 e)*
- [ ] **4.7 Splash, icon, keep-awake.** **Verify:** the launcher icon is legible at 48 dp in
      themed-icon mode; the screen never sleeps mid-film and **does** sleep in the Lobby. *(0.5 e)*
- [ ] **4.8 Update-over-install proof.** Tag `v0.1.0` after `v0.0.1` and install the new arm64 APK
      over the old one.
      **Verify:** it installs **without an uninstall prompt**, and the library, resume points and
      sign-in survive. *(0.5 e)*
- [ ] **4.9 Measure the unmeasured.** Play a 1080p HEVC file with libass on for 20 minutes on the
      phone; record battery drain, sustained fps and case temperature; repeat with subtitles off.
      **Verify:** three dated numbers written into RESEARCH. *(1 e)*
- [ ] **4.10 Set the Android ambience defaults from 4.9.** Bias light and beam default **on** only if
      4.9 shows **< 5 % extra drain over 20 minutes**; otherwise both default off with a one-line
      explanation in the Ticket Office.
      **Verify:** the default matches the measurement and the Ticket Office says why. *(0.5 e)*

**Phase 4 is done when:** the arm64 APK plays the full twelve-file corpus with hardware decode and
correct ASS rendering, does PiP, respects the back gesture, fills its library from MediaStore,
installs over the previous version, and stays under the thermal/battery bar you measured.

### 9.6 Phase 5 — testing, hardening, launch (~16 h)

- [ ] **5.1 `integration_test/` on `windows-latest`** — `player_test`, `subtitles_test`, `seek_test`,
      `keyboard_test`, `house_test`, `perf_test` against real libmpv and the committed fixtures.
      **Verify:** the suite runs in `release.yml` **before** artifacts are published and fails the tag
      on a regression. *(0.5 wd)*
- [ ] **5.2 Playwright suites** — `lite`, `playback`, `threading`, `subtitles`, `noprint`, `offline`,
      `keyboard`, `a11y`, `visual/*`, `perf/*` across `chrome`, `firefox` and a `pixel-7` profile,
      with the Worker mocked by `page.route`.
      **Verify:** green on PRs; visual diffs reviewed **by eye**; the codec-line assertions match the
      per-browser certainties. *(0.5 wd)*
- [ ] **5.3 Nightly `contract.yml`** — the live shape check, skipped when `OS_API_KEY` is absent.
      **Verify:** deleting a field from a fixture makes it fail; a green nightly run is visible. *(0.5 e)*
- [ ] **5.4 Performance gates in CI** — APK/zip size limits, Lighthouse budget, bundle size, Flutter
      timeline thresholds.
      **Verify:** adding a 5 MB asset to `web/` fails the build with a clear message. *(1 e)*
- [ ] **5.5 Manual device passes** — the Android checklist on the phone and the Windows checklist on
      the PC, **both against the tag's own artifacts**, never a dev build.
      **Verify:** both checklists signed off in the release PR. *(1 e)*
- [ ] **5.6 Licence and attribution audit.** `LICENSES/` complete; the About page lists
      libmpv/ffmpeg/libass LGPL notices with links to the two build-script repos; the OpenSubtitles
      credit present; the TMDB logo + exact notice present when TMDB is on; every font credited;
      confirm the shipped Android flavour is `default` (never `encoders-gpl`) and the Windows DLL is
      an LGPL build.
      **Verify:** a checklist in the release PR, **each item naming the file and line that satisfies
      it**. *(1 e)*
- [ ] **5.7 Ship `v1.0.0`.** Generated release notes plus a hand-written summary; README screenshots
      from the real app; the Lite landing linking to the Release; the Worker rollback path exercised
      once.
      **Verify:** a stranger can download the zip or APK from the Releases page, open a file, and get
      synced subtitles with zero clicks. *(0.5 e)*

### 9.7 Phase 6 — stretch (nothing here blocks v1.0.0)

Audio-based automatic sync (ffsubsync-style cross-correlation of speech energy against cue timing —
procedural, no ML); `glsl-shaders` presets on Windows (Anime4K, interpolation/`tscale`, HDR
tone-mapping); a CI step to refresh the Windows `libmpv-2.dll` from an **`-lgpl-`** build (only if
0.14 said it works); an "Indic subtitles" Noto font-pack download; the Lite WebCodecs path behind its
button; playlists and "play next in folder"; an Inno Setup installer with file associations; a Rive
wordmark; COOP/COEP for threaded JASSUB by moving Lite to Workers static assets.

**Never, at any point:** streaming, torrents, DLNA, a media server, transcoding, accounts of our own,
LLM features, store listings.

### 9.8 The Weekend MVP fast path (16.5 hours — two full days)

Sixteen and a half hours, the exact sum of the fourteen rows below — two 8-hour days, not one weekend
evening plus a Saturday. In this order, skipping everything else. The result: a Windows build (and an APK from CI) that plays
any file and fetches synced subtitles with zero clicks, plus a live Lite page doing the same for
browser codecs.

| # | Task | Why it is on the path | Time |
|---|---|---|---|
| 1 | **0.1** Repo + MIT + licences | Nothing works without it | 0.5 h |
| 2 | **0.6** `scripts/tokens.mjs` | Both tiers need tokens before any UI | 1 h |
| 3 | **0.4** `flutter create` + media_kit, plays a file | The engine, proven | 2 h |
| 4 | **0.7 + 0.8** Lite scaffold → live on Pages | Day 1 = live | 1 h |
| 5 | **0.9** Worker deployed with the key | Lite cannot call OpenSubtitles without it | 1 h |
| 6 | **0.11** `release.yml` + `v0.0.1` | An APK on your phone the same day | 1.5 h |
| 7 | **2.1** `hash.dart` + seven golden vectors | The whole idea rests on this function | 1 h |
| 8 | **2.3** `scoring.dart` + goldens | Picking the *right* subtitle is the feature | 1 h |
| 9 | **2.8** `opensubtitles.dart` | The only mandatory API | 1 h |
| 10 | **2.7** `threading.dart` | Makes the leader honest instead of decorative | 1.5 h |
| 11 | **2.11 + 2.13** Player wiring + Threading on real promises | Drop → leader → subtitles, end to end | 2 h |
| 12 | **2.14** Sidecar write + `hash_cache` | A ticket is never wasted twice | 0.5 h |
| 13 | **2.17 + 2.19** TS engine port + Lite end to end | The mandatory web tier does the ritual | 2 h |
| 14 | **4.2** libass font on Android | Without it, subtitles are invisible on the phone | 0.5 h |

**What the MVP deliberately lacks:** the beam, bias light, the marquee warm-up, gate thumbnails, the
ticket-tear animation, sound, the Matinee palette, the library rail, TMDB posters, Subdl, PiP and
gestures. It looks plain — but the leader still counts 3-2-1 honestly, the controls still auto-hide,
and the one thing the project exists for already works.

---

## 10. Testing requirements — what must exist before "done"

### 10.1 The layers, and what each one proves

| Layer | Tool | Proves | Gate |
|---|---|---|---|
| Unit (Dart engine) | `flutter test` over `lib/engine/**` | moviehash, filename grammar, scoring, quota model, timecodes, sync detents, chapter detents, the leader state machine, the OpenSubtitles client against fixture JSON | Every PR. **100 %** line coverage on `hash.dart`, `scoring.dart`, `timecode.dart`, `sync_rule.dart`, `tickets.dart`; ≥ 90 % on the rest of the engine |
| Unit (drift) | `flutter test` with `NativeDatabase.memory()` | Library rows, hash cache, resume positions, per-hash offsets, TMDB expiry, migrations | Every PR |
| Widget + golden | `flutter test --tags golden`, fonts loaded, 0.5 % tolerance | Every component matches the design in **both** palettes plus a `disableAnimations` variant | Every PR; goldens diffed **by eye** |
| Integration (native) | `flutter test integration_test -d windows` with **real libmpv** and committed fixtures | Open → first frame; SRT and ASS attach and render; seek + detents; the keyboard map; house-down/up; error states | The `test` job of `release.yml` + a weekly cron |
| Unit (web) | Vitest (`happy-dom`) | The same golden tables as Dart, via the TS port | Every PR |
| Component (web) | `@testing-library/dom` + `user-event` | Landing, drop frame, No Print card, leader, candidate list, sync rule announce correctly and are keyboard-operable | Every PR |
| E2E (web) | Playwright — `chrome` (branded, has H.264/AAC), `firefox`, `pixel-7` | Real `<video>`, real drop, real JASSUB canvas, Worker mocked with `page.route`, PWA offline | Every PR |
| Visual (web) | `toHaveScreenshot` + computed-style assertions against `tokens.css` | The four screens match the preview; contrast goldens | Every PR |
| Worker | `@cloudflare/vitest-pool-workers` (`SELF.fetch`, `fetchMock`) | Every §7.6 invariant, including "the key never leaks" | Every PR **and before every Worker deploy** |
| Contract (live) | Vitest, skipped unless `OS_API_KEY` is present | Real OpenSubtitles responses still have the shape the fixtures assume | Nightly cron. **A failure opens a GitHub issue rather than failing a branch** — the API is not ours |
| Performance | mpv properties, Flutter timeline summaries, Lighthouse CI, bundle and artifact sizes | §10.6 budgets | Weekly + before every tag |
| Accessibility | `@axe-core/playwright`; Flutter `meetsGuideline(...)` + semantics tests; manual NVDA/TalkBack | §3.10 | Automated every PR; manual before every tag |
| Device | Manual checklists on the phone and the PC, **against the tag's own artifacts** | Permissions, back gesture, rotation, PiP, audio focus, libass, battery, frameless window, SmartScreen | Before every `v*` tag |

**Commands**

| What | Command |
|---|---|
| Dart unit + widget | `flutter test --exclude-tags golden` |
| Goldens (Linux/CI only) | `flutter test --tags golden` · regenerate: `--update-goldens` |
| Coverage | `flutter test --coverage && genhtml coverage/lcov.info -o coverage/html` |
| Native integration (Windows) | `flutter test integration_test -d windows` |
| Web unit | `cd web && npm test -- --run` |
| Web e2e | `cd web && npx playwright test` · visual only: `npx playwright test e2e/visual` |
| Worker | `cd worker && npm test` · contract: `OS_API_KEY=… npm run test:contract` |
| Tokens in sync | `node scripts/tokens.mjs && git diff --exit-code web/src/styles/tokens.css lib/theme/tokens.dart` |

### 10.2 Determinism rules (non-negotiable — they are why the suite is not flaky)

- **The clock is injected everywhere it shows:** the sky band, the marquee night flicker, the
  `RESETS 00:00 UTC` countdown, the TMDB cache expiry. Dart: `withClock(Clock.fixed(DateTime.utc(2026,
  9, 6, 15, 44)))`. Web: `vi.setSystemTime(new Date('2026-09-06T21:14:00+05:30'))` and Playwright
  `page.clock.install({ time: '2026-09-06T21:14:00+05:30' })`. **21:14 IST is night** — bulbs lit,
  flicker on — which is the house fixture.
- **Every RNG takes a seed.** Tests pass `Random(8)`.
- **The network is never real** in unit or e2e tests: Dart uses `MockClient`; Playwright intercepts
  `**/api/**`; the Worker suite uses `fetchMock`. Only the nightly contract test touches the live API.
- **Fixtures are bit-exact.** `scripts/make-fixtures.sh` uses `-fflags +bitexact -flags:v +bitexact
  -flags:a +bitexact -map_metadata -1`, so the same command on any ffmpeg 6/7 build reproduces the
  same bytes and therefore the same moviehash. Hashes are frozen in `test/fixtures/hashes.json` and
  asserted by both suites. `make-fixtures.sh && git diff --exit-code test/fixtures` is a CI check;
  the Windows runner **never** regenerates fixtures, it consumes the committed bytes.
- `TZ=Asia/Kolkata` in `vitest.config.ts` and `playwright.config.ts`. The ticket strip always prints
  UTC, so it is unaffected.
- **Fonts are loaded before any golden runs** via `FontLoader` in `test/flutter_test_config.dart` —
  otherwise Flutter renders the Ahem block font and every golden is meaningless.
- **No sleeping in tests.** Dart uses `fakeAsync`/`withClock`; Vitest uses `vi.useFakeTimers()`;
  Playwright uses `page.clock` and waits on **state**, never `waitForTimeout`.
- **A flaky test is a broken test.** No retries on local/PR runs (CI gets `retries: 1` only so a
  runner hiccup does not block a merge); any test that actually uses its retry is quarantined with an
  issue link the same day.

### 10.3 Fixtures you must generate and commit

**Media** (`test/fixtures/media/`, all ≥ 128 KiB so they hash, all < 1 MB so the repo stays light):

| File | ffmpeg recipe (bit-exact flags implied) | Used by |
|---|---|---|
| `testsrc-10s-h264-aac.mkv` | `-f lavfi -i testsrc2=size=320x180:rate=24000/1001 -f lavfi -i sine=frequency=1000 -t 10 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 64k` + chapters from `chapters.ffmeta` (0 s "Leader", 3 s "Reel 1", 6 s "Reel 2") + an embedded SRT track + an embedded ASS track | player, seek/detents, embedded tracks, web playback in Chrome |
| `testsrc-10s-h264-aac.mp4` | same streams, `-movflags +faststart` | web fast path (every browser) |
| `testsrc-10s-vp9-opus.webm` | `-c:v libvpx-vp9 -b:v 200k -c:a libopus` | web playback in Firefox |
| `testsrc-10s-hevc-ac3.mkv` | `-c:v libx265 -x265-params log-level=0 -crf 24 -c:a ac3 -b:a 96k` | the **No Print** path on the web; HEVC hwdec on native |
| `testsrc-10s-h264.avi` | `-c:v mpeg4 -q:v 4 -c:a mp3` | "any container" on native |
| `tiny-100kib.mkv` | the first fixture cut with `-fs 102400` | the too-small path |
| `corrupt.mkv` | 200 KiB of deterministic pseudo-random bytes (`openssl enc -aes-256-ctr -pass pass:marquee -nosalt < /dev/zero`) | the "Undecodable print" state |
| `frame-bias.png` | 64 × 36: 60 % `#FFC56E`, 30 % `#A3252F`, 10 % `#5FD48A` | the bias-light quantizer golden |

**Text:** `sample.srt` (4 cues incl. `<i>` and a two-line cue) · `sample-crlf-bom.srt` (BOM + CRLF +
an out-of-order index) · `sample.ass` (Noto Sans style, one `\pos`, one `\an8`) · `sample-hi.srt`
(bracketed `[DOOR SLAMS]`).

**OpenSubtitles JSON** (`test/fixtures/os/`, shared with `worker/test/fixtures` and
`web/e2e/fixtures`): `search-hash-hit.json` (3 entries, `moviehash_match: true` on A,
`files[0].file_id: 1234567`, `feature_details {feature_type:"Movie", title:"The Third Man", year:1949,
imdb_id:41959, tmdb_id:1092}`) · `search-miss.json` (`total_count: 0`) · `search-by-name.json` (two
entries, no `moviehash_match`, one `machine_translated`) · `login-ok.json` (`allowed_downloads: 20`)
· `login-vip.json` (`allowed_downloads: 1000, vip: true, base_url: "vip-api.opensubtitles.com"`) ·
`download-ok.json` (`remaining: 7`, `reset_time_utc: "2026-09-07T00:00:00.000Z"`) ·
`download-406.json` · `401.json` · `429.txt` (headers `Retry-After: 2`, `X-RateLimit-*`) ·
`link-410.txt` · `subdl-search.json` · `subdl-zip.bin` · `tmdb-find.json`.

**Test data never leaves the repo:** no real film, no real subtitle file, no real key in `test/`. The
only external download is `breakdance.avi`, fetched to a temp dir and never committed.

### 10.4 Required native integration tests (real libmpv, `windows-latest`)

| # | Given | Then |
|---|---|---|
| I1 | `testsrc-10s-h264-aac.mkv` | a first frame within **1.5 s**; `duration ≈ 10 s ± 40 ms` |
| I2 | `testsrc-10s-hevc-ac3.mkv` | **video and audio** decode; the audio track reports `ac3`. This is the case the web tier cannot do and the whole reason libmpv exists |
| I3 | `testsrc-10s-h264.avi` | plays — proves "any container" |
| I4 | `corrupt.mkv` | the *Undecodable print* state within 2 s, no hang, and the **next** `open()` succeeds |
| I5 | `sample.srt` attached | the track is active; a screenshot at t = 2 s has non-background pixels in the bottom third |
| I6 | `sample.ass` with `\pos` and `\an8` | the `\an8` cue renders in the **top** third and the `\pos` cue at its coordinates, compared with a committed golden at 2 % tolerance (libass output is not bit-stable across builds) |
| I7 | the MKV's **embedded** SRT and ASS tracks | both list with titles; switching takes effect within 2 frames |
| I8 | `libass: true` with the bundled font | mpv reports `sub-ass=yes`, `config=yes`, `sub-font-provider=none`, `sub-fonts-dir` pointing at the cache copy, and **`vo == gpu`**. This test fails loudly if anyone ever sets `vo=mediacodec_embed` |
| I9 | chapters at 0/3/6 s, drag the gate to 3.1 s and release | snaps to 3.000 s, position lands within 40 ms, one selection tick |
| I10 | position 5 s, `←` then `Shift+→` | 0 s then 30 s (clamped to duration); the folio updates in the same frame |
| I11 | `design/cue-sheet.json` | every listed key has an observable effect, **and the test fails if the JSON lists a key the app ignores *or* the app handles a key the JSON omits** |
| I12 | Lobby → open → back | `--house` reaches 0 within 900 ms ± 60 ms; the video is disposed on the way back; a second open leaks no `Player` |
| I13 | the Windows frameless window | dragging the marquee title bar moves the window; Mica is active in the Lobby and **off** during playback |
| I14 | play 10 s with controls visible | the Flutter timeline summary meets the §10.6 budgets |
| I15 | a file passed as a command-line argument | it plays **without passing through the Lobby** |

**There is no Android emulator in CI** and libmpv wants a real GPU, so Android integration runs on the
owner's machine only. The standing Android gate is therefore the manual checklist — **not optional**.

### 10.5 Required golden/widget tests

Marquee sign (now-showing night · Matinee day with bulbs **off** · a 30-letter title proving the
24-letter stagger cap) · Leader (phase "2" at 180° · **stalled** with the angle frozen and rows laid
out beneath without the numeral moving · `disableAnimations` crossfade) · Ticket strip (7/10 · 2 left
crimson · exhausted) · Film gate (idle at 4364.4 s with buffered range and 4 chapters · dragging in
FINE mode) · Sync rule at `+0.35` (**the caret is fixed; the ruler has moved**) · Candidate row (six
states) · Booth sheet at 70 % over a paused frame · Ticket Office in both palettes with the
attribution block present and typeset · Lobby night · Auditorium with controls (controls on `--bg`,
never on the picture) · Auditorium after 2400 ms idle (all chrome gone, folio at 40 %) · the
"Undecodable print" error (**scan the rendered image and fail if pixels within ΔE 10 of `--danger`
cover more than 2 % of the frame**) · every screen with `disableAnimations` (assert **zero** repeating
tickers left running).

Behavioural (not golden): the gate exposes slider semantics with a timecode value; toggle bulbs report
`role: switch`; the ticket strip's semantic label matches §6.6; **tapping a candidate row overrides
the auto-pick and cancels the in-flight download**.

### 10.6 Performance budgets — these are gates, not aspirations

| # | Metric | Gate | Measured by |
|---|---|---|---|
| N1 | moviehash of a 1.4 GB file | ≤ 60 ms (target 40) | `perf_test`, median of 20 runs |
| N2 | `player.open` → first frame, local 1080p | **< 1.5 s** | `perf_test` |
| N3 | Cold start → Lobby interactive | Windows **< 1.5 s**; Android **< 2.5 s** | `perf_test` (Windows); stopwatch (Android) |
| N4 | Drop → subtitles attached + first frame, hash hit, 10 Mbit | **< 3 s** end to end | manual with throttling; CI asserts the non-network part < 1.8 s |
| N5 | Failure → fallback rows visible | **< 500 ms** | threading unit test with a fake clock |
| N6 | Frame time (controls + gate drag + sync rule) | 60 fps: **0 frames > 16.7 ms at p90**, worst < 32 ms | timeline summary on a `--profile` build |
| N7 | Beam shader | **≤ 2 ms/frame** at the DPR cap | `perf_test` with the shader isolated |
| N8 | Bias-light sample + quantize | ≤ 8 ms per sample, off the raster thread | `perf_test`; over budget → drop the cadence to 1000 ms on desktop too |
| N9 | Windows release zip | ≤ **60 MB** | `release.yml` size gate |
| N10 | `arm64-v8a` APK | ≤ **55 MB** (target 45; libmpv + ffmpeg is ~30–40 MB per ABI — a jump means a flavour or ABI mistake) | `release.yml` size gate |
| N11 | Universal APK | **0 files** — split-per-ABI only | `release.yml` assertion |
| N12 | Lite JS bundle, gzipped, without JASSUB/WebCodecs chunks | ≤ **120 KB** (target 60) | `size-limit` in `ci.yml` |
| N13 | JASSUB and the WebCodecs path | lazy chunks, **0 bytes** on the landing page | Playwright network assertion |
| N14 | Lighthouse (mobile, throttled) on the Lite landing | Performance ≥ **90** (target 95), Accessibility **= 100**, Best Practices ≥ 95; LCP ≤ 2.0 s, CLS ≤ 0.02, TBT ≤ 150 ms | `lighthouserc.json` |
| N15 | Lite: drop → playing with subtitles (MP4/H.264) | **< 3 s** | Playwright timing |
| N16 | Lite: unplayable file → No Print card | **< 1 s** | Playwright timing |
| N17 | Tag → both artifacts on a Release | **< 25 min** wall clock | `timeout-minutes: 25` on each build job |
| N18 | Memory after 30 open/close cycles | no monotonic growth (< 10 % over the first-open baseline) | `perf_test` loop over `ProcessInfo.currentRss` |

Three techniques carry most of this: the leader's phases run **concurrently with player warm-up**;
the bias light decodes at 64 × 36 via `targetWidth`, never full-res; and Lite ships no framework.

### 10.7 Licence, privacy and secret-leak checks (every PR)

| # | Check | Fails when |
|---|---|---|
| G1 | `flutter pub deps --style=compact` through a licence allow-list | any transitive package is AGPL, GPL or unlicensed. `guessit-js` must never appear in `web/package-lock.json` either |
| G2 | The Android flavour actually linked | the APK contains `libmpv.so` from anything but the `default` flavour — `encoders-gpl` would make the app GPLv3 |
| G3 | Windows DLL provenance | `libmpv-2.dll`'s SHA-256 does not match `tools/libmpv-windows.sha256`; if the refresh step is ever enabled, the source archive name must contain `-lgpl-` |
| G4 | Attribution present | the built app's string table lacks "Subtitles by OpenSubtitles.com", the verbatim TMDB notice, the LGPL notices with both build-script links, or the OFL font list |
| G5 | No secret in any bundle | `web/dist/**` or a native artifact matches the consumer-key pattern or `VITE_.*KEY`; or the tree contains `.p12`, `key.properties`, `local.properties` |
| G6 | No telemetry | the tree matches `analytics|sentry|posthog|gtag|firebase`; or the Lite CSP `connect-src` lists anything but `'self'`, the Worker and the two optional TMDB hosts (`api.themoviedb.org`, `image.tmdb.org`) |
| G7 | TMDB cache expiry | a build whose TTL constant exceeds 180 days |
| G8 | Fonts | any `font-family` outside Big Shoulders Display / Geist / Geist Mono / Noto Sans |
| G9 | Design tokens in sync | `tokens.mjs` output differs from the committed files |
| G10 | Cue sheet in sync | `design/cue-sheet.json` differs from what the overlay and README render |

Also assert with a stylesheet lint: `--accent-2` is **never** a `color:` value in an Auditorium
stylesheet; `--picture-bg` is used **only** on the video container; `--ink-faint` and `--danger` only
appear as text colours at ≥ 18 px on `--surface-2`.

### 10.8 Live contract test (nightly, never blocking)

`describe.skipIf(!process.env.OS_API_KEY)`. **Search-only** calls (search is unlimited), plus at most
**one** `/download` per month behind an explicit `RUN_DOWNLOAD_PROBE=1` flag. It asserts that every
field the fixtures read still exists; records the observed `X-RateLimit-*` values into
`worker/test/observed-limits.json` so the undocumented limit is discovered empirically; checks
whether an unsorted query still 301s and still drops `moviehash_match`; records whether
`moviehash_match=only` is honoured; probes whether `/utilities/guessit` exists; reads back
`allowed_downloads`; and measures the download link's TTL. **A failure opens a GitHub issue via
`gh issue create` rather than failing the branch** — a shape change is news, not a build break.

---

## 11. Deployment

Four deployables, four pipelines, kept independent by path triggers: a CSS tweak in `web/` never
rebuilds an APK, and a Dart change never redeploys the Worker.

| # | Deployable | Built by | Lands at |
|---|---|---|---|
| 1 | Marquee (Windows) — `marquee.exe` + `libmpv-2.dll` | Actions `windows-latest` | a zip on a GitHub Release |
| 2 | Marquee (Android) — signed split-per-ABI APKs | Actions `ubuntu-24.04` | APKs on the same Release, sideloaded |
| 3 | Marquee Lite | Actions → GitHub Pages | `https://<owner>.github.io/marquee/` |
| 4 | `marquee-proxy` | Actions → `wrangler deploy` | `https://marquee-proxy.<subdomain>.workers.dev` |

### 11.1 Secrets and configuration — the complete inventory

**The rule that governs all of it: anything that reaches the browser bundle is public.** Secrets live
in the Worker or in a runner's memory during a build.

| Name | Kind | Set where | Consumed by | Notes |
|---|---|---|---|---|
| `OS_API_KEY` | secret | GitHub repo secret **and** `wrangler secret put` | `release.yml` → `--dart-define` (native); the Worker (Lite) | The same consumer key in two places by necessity. Semi-secret in native builds (Kodi's official addon ships one too) — rate-limit client-side and rotate if abused |
| `TMDB_READ_TOKEN` | secret, optional | GitHub repo secret | `release.yml` → `--dart-define` | Posters only. A user's own BYO key is the alternative |
| `ANDROID_KEYSTORE_BASE64` | secret | GitHub repo secret | `release.yml` android leg | The whole `.p12.b64` file |
| `ANDROID_KEYSTORE_PASSWORD` | secret | " | " | |
| `ANDROID_KEY_ALIAS` | secret | " | " | `release` |
| `ANDROID_KEY_PASSWORD` | secret | " | " | **Equals the store password** (PKCS12 rule) |
| `CLOUDFLARE_API_TOKEN` | secret | " | `worker.yml` | "Edit Cloudflare Workers" template |
| `CLOUDFLARE_ACCOUNT_ID` | secret | " | `worker.yml` | |
| `ALLOWED_ORIGIN` | public var | `worker/wrangler.toml` `[vars]` | Worker | `https://<owner>.github.io` — **no path** |
| `UPSTREAM_BASE` | public var | " | Worker | `https://api.opensubtitles.com/api/v1` |
| `USER_AGENT` | public var | " | Worker | `Marquee-Web v1.0.0` — must be descriptive |
| `VITE_BASE_PATH` | public build var | `pages.yml` | `web/vite.config.ts` | `/marquee/` on Pages, `/` locally |
| `VITE_API_BASE` | public build var | `pages.yml` | `web/src/config.ts` | the Worker URL + `/api` |
| `VITE_APP_VERSION` | public build var | `pages.yml` | the About line | `github.sha` |
| `MARQUEE_VERSION` | build define | `release.yml` | About line, `User-Agent` | the tag without the `v` |
| Subdl key | **user** data | Ticket Office → secure storage | the app | the *user's* key. Never a repo secret, never shipped |
| OpenSubtitles JWT | **user** data | login → `flutter_secure_storage` / WebCrypto AES-GCM | the app | the password is **never** stored |

**Never:** put the key in a `VITE_*` variable; commit `android/key.properties`,
`android/local.properties`, or any `.p12`/`.jks`; echo a secret into a workflow log; add a secret to
`wrangler.toml`.

### 11.2 `.github/workflows/ci.yml`

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
  FLUTTER_VERSION: '3.47.0'      # pinned; moved only in a deliberate commit

jobs:
  dart:
    name: analyze + dart tests + goldens
    runs-on: ubuntu-24.04        # goldens are generated on Linux ONLY
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs   # drift: *.g.dart is gitignored
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - name: Coverage gates
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
        env:
          VITE_BASE_PATH: /marquee/
          VITE_API_BASE: https://marquee-proxy.<subdomain>.workers.dev/api
      - run: npx size-limit          # N12 / N13

  worker:
    name: worker tests
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: worker } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: worker/package-lock.json }
      - run: npm ci
      - run: npx biome ci .          # includes the noConsole rule scoped to worker/
      - run: npm test                # every §7.6 invariant

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
    name: fixtures, tokens, parity, licences, secrets
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '${{ env.FLUTTER_VERSION }}', channel: stable, cache: true }
      - uses: actions/setup-node@v7
        with: { node-version: 22 }
      - name: Media fixtures are bit-exact
        run: bash scripts/make-fixtures.sh && git diff --exit-code test/fixtures
      - name: Design tokens in sync (G9)
        run: node scripts/tokens.mjs && git diff --exit-code web/src/styles/tokens.css lib/theme/tokens.dart
      - name: Engine test parity between Dart and TS
        run: node scripts/check-parity.mjs
      - name: Cue sheet in sync (G10)
        run: node scripts/check-cue-sheet.mjs
      - name: Licence allow-list (G1)
        run: flutter pub get && dart run build_runner build --delete-conflicting-outputs && dart run tool/check_licences.dart
      - name: No secrets, no telemetry (G5/G6)
        run: bash tool/check_no_secrets.sh

  lighthouse:
    name: lighthouse budgets
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: web } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: web/package-lock.json }
      - run: npm ci
      - run: npm run build
        env: { VITE_BASE_PATH: /, VITE_API_BASE: https://marquee-proxy.<subdomain>.workers.dev/api }
      - run: npx @lhci/cli autorun     # thresholds in web/lighthouserc.json (N14)
```

### 11.3 `.github/workflows/pages.yml`

Prerequisite: **Settings → Pages → Build and deployment → Source: "GitHub Actions"**.

```yaml
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
          # Public config only. The API key lives in the Worker.
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

**`web/vite.config.ts`:**

```ts
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
        // The app shell and fonts precache. NEVER precache media or /api/**.
        globPatterns: ['**/*.{js,css,html,woff2,png,svg,frag}'],
        navigateFallback: 'index.html',
        runtimeCaching: [{ urlPattern: /\/api\//, handler: 'NetworkOnly' }],
      },
    }),
  ],
})
```

`vite-plugin-pwa` derives `scope` and `start_url` from `base`, so both become `/marquee/`
automatically. **Two rules that bite on sub-path hosting:** never `fetch('/data.json')` — always
`import.meta.env.BASE_URL + 'data.json'` — and register the service worker from
`import.meta.env.BASE_URL + 'sw.js'`. Test with `npm run build && npx vite preview --base /marquee/`
before pushing.

**Caching policy for Lite:**

| Cache | Contents | Strategy |
|---|---|---|
| Precache | `index.html`, hashed JS/CSS, `tokens.css`, the three subset variable fonts, icons, manifest | precached; `StaleWhileRevalidate` on navigation |
| Lazy | JASSUB WASM + worker (~1.2 MB), the WebCodecs module | **Not precached.** Fetched on first `.ass` / first button press, then `CacheFirst` with a 30-day expiry |
| Worker API | `/api/*` | **`NetworkOnly`.** Never cache a subtitle search or a download link in the service worker — links expire and quota answers must be live |
| Subtitles | converted VTT text | **IndexedDB**, not Cache Storage, keyed by `moviehash|lang` — so reopening the same file offline reattaches instantly and costs nothing |

**What Pages cannot do:** no custom headers, therefore no COOP/COEP, therefore no
`SharedArrayBuffer` — **JASSUB runs single-threaded** on the deployed site. It falls back
automatically and the app must **not** attempt the threaded path. Deep links return HTTP 404 even
when they render (the `404.html` copy makes them boot anyway). 1 GB site / 100 GB-month soft limits.
The escape hatch, if ASS rendering ever proves too slow, is Cloudflare **Workers with static assets**
(free, `_headers` supported) — a hosting move, not a rewrite.

**Verify after the first deploy:**

```bash
U=https://<owner>.github.io/marquee
curl -sI $U/                       # 200
curl -sI $U/manifest.webmanifest   # 200, application/manifest+json
curl -sI $U/sw.js                  # 200, javascript
curl -s  $U/ | grep -o 'src="[^"]*"' | head   # every asset path starts with /marquee/
```

A 404 on `sw.js`, or an asset path missing `/marquee/`, means `VITE_BASE_PATH` did not reach the
build.

### 11.4 `.github/workflows/release.yml`

One workflow produces both native artifacts and publishes them. **Note the Temurin 17 pin (R1) and
`minSdk 26` (R2).**

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
    timeout-minutes: 25          # N17: tag -> artifacts in under 25 min
    strategy:
      fail-fast: false
      matrix:
        include:
          - label: windows-x64
            os: windows-latest
            target: windows
          - label: android-apks
            os: ubuntu-24.04     # Android SDK 34-37, build-tools, JDKs preinstalled
            target: android
    steps:
      - uses: actions/checkout@v7

      - name: Derive version
        id: v
        shell: bash
        run: |
          set -euo pipefail
          RAW='${{ github.ref_type == 'tag' && github.ref_name || format('v0.0.{0}', github.run_number) }}'
          echo "name=${RAW#v}"                  >> "$GITHUB_OUTPUT"
          echo "code=${{ github.run_number }}"  >> "$GITHUB_OUTPUT"

      - uses: actions/setup-java@v6
        if: matrix.target == 'android'
        with:
          distribution: temurin
          java-version: '17'     # R1 — the proven version for this Flutter + AGP pair
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
          if ($mb -gt 60) { throw "Windows zip is $mb MB; budget is 60 MB (N9)" }
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
            if "$APKSIGNER" verify --print-certs "$src" | grep -qi 'CN=Android Debug'; then
              echo "::error::$abi APK is DEBUG-signed"; exit 1
            fi
            cp "$src" "out/marquee-${{ steps.v.outputs.name }}-$abi.apk"
          done
          # No universal APK — libmpv is ~30-40 MB per ABI (N11)
          test ! -f build/app/outputs/flutter-apk/app-release.apk
          sz=$(stat -c%s "out/marquee-${{ steps.v.outputs.name }}-arm64-v8a.apk")
          echo "arm64-v8a APK: $((sz / 1024 / 1024)) MB"
          test "$sz" -le $((55 * 1024 * 1024)) \
            || { echo "::error::arm64 APK exceeds the 55 MB budget (N10)"; exit 1; }
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

**Why a matrix rather than two hand-written jobs:** the checkout, the version derivation, the Flutter
pin and the `--dart-define` set are identical on both platforms and must stay identical. A matrix
makes drift impossible; the platform-specific halves are guarded with `if: matrix.target == …`.

### 11.5 `.github/workflows/worker.yml`

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
      - run: npm test                       # the Worker is the only component that can leak a key:
        working-directory: worker           # it never deploys red
      - uses: cloudflare/wrangler-action@v4
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          workingDirectory: worker
```

### 11.6 `.github/workflows/contract.yml`

```yaml
name: contract

on:
  schedule:
    - cron: '0 3 * * *'          # nightly
  workflow_dispatch:

permissions:
  contents: read
  issues: write                  # a shape change opens an issue, it does not fail a branch

jobs:
  contract:
    runs-on: ubuntu-24.04
    defaults: { run: { working-directory: worker } }
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version: 22, cache: npm, cache-dependency-path: worker/package-lock.json }
      - run: npm ci
      - run: npm run test:contract
        env:
          OS_API_KEY: ${{ secrets.OS_API_KEY }}
          GH_TOKEN: ${{ github.token }}
```

### 11.7 Versioning, releasing, rolling back, backing up

**Versioning.** SemVer, one tag per release (`v1.0.0`). `pubspec.yaml` carries `1.0.0+1` as the local
default; CI overrides both halves — `--build-name` from the tag minus the `v`, `--build-number` from
`github.run_number`, which guarantees `versionCode` **always increases** (a harmless gap after a
re-run is fine). Lite has no version of its own: it ships `github.sha` in its About line and deploys
continuously from `main`. The Worker likewise deploys from `main`. **`applicationId` and the signing
key are permanent.**

**Release checklist.** 1) `ci.yml` green on `main`, golden diffs reviewed as images. 2) `contract.yml`
green (or its issue triaged) within 24 h. 3) Every open day-1 question has an answer or a written
mitigation. 4) Bump `pubspec.yaml`, update `CHANGELOG.md`, push, wait for green. 5)
`git tag v1.2.3 && git push origin v1.2.3`. 6) Watch `release.yml`: `test` → `build` (both legs) →
`publish`, under 25 minutes. 7) Download the Release's **own** artifacts and walk the Android and
Windows manual checklists. 8) If either fails, mark it a pre-release immediately
(`gh release edit v1.2.3 --prerelease`) and fix forward.

**Rollback.**

| Broken | How | Caveat |
|---|---|---|
| Lite (Pages) | `git revert <sha> && git push` — redeploys in ~2 min | A revert is the honest record |
| Worker | `npx wrangler deployments list` then `npx wrangler rollback [<id>]` — instant, no build | Secrets are not part of a deployment, so a rollback never loses `OS_API_KEY` |
| A bad Release | `gh release edit v1.2.3 --prerelease`, or delete one bad asset; then tag a fix | **Users cannot downgrade an APK** — a lower `versionCode` refuses to install. Rolling back Android means shipping a *forward* fix |
| A bad Windows zip | Delete the asset; the previous Release's zip is still downloadable | The app is portable |
| A leaked `OS_API_KEY` | Revoke at opensubtitles.com → API Consumers, create a new one, update the repo secret **and** `wrangler secret put`, redeploy, tag a patch for native | Builds in the wild keep the old key until they update |
| A leaked keystore | **There is no rollback.** A new key means a new `applicationId` and a clean install | Which is why the backup below is not optional |

**Backups.** `marquee-release.p12` **and its passphrase** → password manager **and** one offline copy
(this is the only unrecoverable thing in the project). OpenSubtitles / Cloudflare / TMDB credentials →
password manager (all regenerable). Source and docs → the public repo. **User data** → the Ticket
Office's Export library JSON (§5.5). Downloaded subtitles → already on disk beside the films, which
is why "save beside file" is the default.

### 11.8 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Pages deploy is green but the site is blank, console 404s for `/assets/…` | `VITE_BASE_PATH` did not reach the build | Check the `env:` block; verify every `src=` starts with `/marquee/` |
| Lite loads, search returns nothing, CORS error on the preflight | `ALLOWED_ORIGIN` does not match the browser's `Origin` exactly | An `Origin` is scheme + host + port with **no path**. Fix `wrangler.toml`, redeploy, re-run the §7.6 probes |
| Worker returns 403 to everything | The request has no `Origin` (curl, or a native build pointed at the proxy) | Expected. Native calls the API directly; add `-H "Origin: …"` when probing |
| Worker returns 404 for a valid endpoint | The path is not in `ALLOW` | Add the exact upstream path **and** a test case in the same commit |
| Search results are missing `moviehash_match` | Unsorted params caused the canonical 301, which drops that param | The Worker sorts them; the native client must too |
| HTTP 429 everywhere, suddenly | The undocumented per-second limit | Honour `Retry-After` and `X-RateLimit-Reset`; check `worker/test/observed-limits.json` |
| APK builds but will not install over the previous one | Debug-signed, or `versionCode` did not increase | `apksigner verify` catches the first; the second means `--build-number` was not passed |
| Subtitles invisible **only on Android** | `libassAndroidFontName` is not the TTF's internal family name, or the font asset is not bundled | Verify the family really is `Noto Sans` |
| Android plays video but has no subtitles **and no OSD** | Someone set `vo: 'mediacodec_embed'` | mpv disables subtitle rendering under that vo. Keep `vo=gpu` — the integration test fails the build on this |
| `flutter build windows` fails on a fresh runner | The Flutter pin and `media_kit` disagree | Move `FLUTTER_VERSION` deliberately in **both** workflows; never switch to unpinned `channel: stable` |
| Windows build runs but plays nothing | `libmpv-2.dll` missing from the output | The workflow asserts it before zipping; if it fails, clear the pub cache and rebuild |
| Golden tests fail only on Windows | Goldens are Linux-only by design | `--exclude-tags golden` locally; regenerate on `ubuntu-24.04` |
| `make-fixtures.sh` diff fails in CI | A different ffmpeg build produced different bytes | Regenerate on `ubuntu-24.04` (the reference) and commit both the fixtures **and** `hashes.json` — a fixture change moves every hash golden |
| Cloudflare error 1027 | The Worker's 100k/day is spent | It hard-fails and never bills. Check the origin allow-list first — the only way a solo user hits this is someone else using the proxy |
| A tag ran but no Release appeared | `publish` is `if: github.ref_type == 'tag'`; `workflow_dispatch` deliberately produces artifacts only | Tag properly, or download the artifact from the run |

---

## 12. Definition of done

Marquee is `v1.0.0` when every box below is ticked **and demonstrated**, not asserted.

### 12.1 The eight product criteria

- [ ] **1 · Zero-click subtitles.** Open a ≥ 128 KiB video that has a moviehash hit → English
      subtitles attached, in sync, the MATCH bulb lit, and the first frame shown **within 3 s** of
      the drop on a 10 Mbit connection, **with no click and no keypress**.
- [ ] **2 · Any codec, both platforms.** Every file in the twelve-file corpus plays with **video and
      audio** on **both** Windows and Android, with hardware decode where available, and the same
      ASS test file renders with **identical positioning and styling** on both:
      MKV/HEVC/AC-3 · MKV/H.264/DTS · AVI/XviD/MP3 · MP4/H.264/AAC · WebM/VP9/Opus · MP4/AV1 ·
      MOV/ProRes · TS/H.264 · 10-bit HEVC · MKV+PGS · MKV+ASS · MKV+FLAC.
- [ ] **3 · A ticket is never wasted.** Re-opening a file whose subtitle was already fetched costs
      **0** downloads (sidecar + cache hit rate 100 %); the app never downloads more than **1**
      subtitle per open without an explicit tap; the ticket strip always shows the **true**
      `remaining` from the last API response.
- [ ] **4 · Honest loading.** The leader never advances past a phase that has not resolved; a failure
      **stalls the numeral** and shows one sentence with the next action (filename search → Subdl →
      manual → skip) **within 500 ms** of the failure.
- [ ] **5 · Fast to the picture.** Cold start → Lobby **< 1.5 s** Windows, **< 2.5 s** mid-range
      Android; open → first frame **< 1.5 s** for a local 1080p file; controls, gate drag and sync
      rule run at **60 fps**; the beam shader costs **≤ 2 ms**/frame at its DPR cap.
- [ ] **6 · Usable in the dark.** Every control reachable by keyboard on Windows (the cue sheet lists
      them all and is generated from `cue-sheet.json`) and by thumb on Android (≥ 44 × 44 px, the gate
      56 px); every text token **≥ 4.5 : 1** on its allowed surface; `prefers-reduced-motion` honoured
      with the leader still stalling honestly.
- [ ] **7 · Marquee Lite is honest.** A dropped MP4/H.264 or WebM plays with subtitles **within 3 s**;
      an unplayable file shows the No Print card with container and codec names and the reason
      ("This browser has no AC-3 decoder") **within 1 s** — never a silent black rectangle.
- [ ] **8 · Release is one command.** `git tag v1.0.0 && git push --tags` → a Windows x64 zip +
      `arm64-v8a` APK (+ `armeabi-v7a`, `x86_64`) on a GitHub Release with **no manual step**, in
      **under 25 minutes**; the APK installs **over** the previous version and the library, resume
      positions and sync offsets survive.

### 12.2 Design-fidelity checks against the preview

- [ ] Side by side at **390 px and 1440 px**, the running app and `design/preview.html` are
      indistinguishable for the Lobby (night **and** Matinee), Threading mid-sweep, the Auditorium
      with controls, and the Booth sheet.
- [ ] **One accent per screen.** Crimson appears only as the 1 px marquee trim, the ticket stubs and
      the low-quota strip. On the Threading screen the ticket strip is the *only* crimson element.
- [ ] **No spinner exists anywhere in the codebase.** Buffering is the gate frame flickering at 2 Hz;
      loading is a shimmer or a leader numeral.
- [ ] **No red banner exists anywhere.** The error golden proves it: pixels within ΔE 10 of `--danger`
      never cover more than 2 % of an error frame.
- [ ] Grain is present in the Lobby and sheets at 4 % and **absent over the picture**.
- [ ] Every shadow falls **down**; every glow is tungsten; the only glow is `--bulb-halo`.
- [ ] The marquee bulbs are **off** (letters painted) in Matinee, and lit with a 0.5 % flicker at
      local night.
- [ ] The sync rule's **caret is fixed and the ruler moves**.
- [ ] Controls sit on the wall (`--bg`), **never on the video**.
- [ ] `house-down` is driven by exactly **one** tweened value — a grep proves there is no second tween.
- [ ] Type is only Big Shoulders Display / Geist / Geist Mono, and subtitles are only Noto Sans.

### 12.3 Engineering gates

- [ ] `ci.yml` green on `main`, including the golden diff reviewed **as images**.
- [ ] Coverage: **100 %** on `hash`, `scoring`, `timecode`, `sync_rule`, `tickets` (and their TS
      twins); **≥ 90 %** on the rest of `lib/engine` and `web/src/engine`; **≥ 80 %** on `worker/src`.
- [ ] `scripts/check-parity.mjs` passes — no engine rule exists in one language and not the other.
- [ ] Every performance budget N1–N18 met; N3, N4 and N17 re-measured **by hand** before the tag.
- [ ] `@axe-core/playwright`: **zero** violations at `wcag2a`/`wcag2aa` on all five Lite screens, with
      colour-contrast violations **not suppressed**.
- [ ] A manual NVDA pass on Windows and a TalkBack pass on Android walk Lobby → Threading →
      Auditorium → Booth → Ticket Office.
- [ ] The nightly contract run is green (or its auto-filed issue is triaged) within 24 h of the tag.
- [ ] `integration_test` green on `windows-latest` **before** the artifacts are published.
- [ ] The Android and Windows manual checklists are walked on **the tag's own artifacts** — never a
      dev build — and signed off in the release PR.
- [ ] The restore drill has been done once: export the library, uninstall, reinstall from the Release,
      import, and confirm the rail, the resume positions and one `±0.35` badge all come back.

### 12.4 Licence, privacy and attribution gates

- [ ] `LICENSES/` complete; `LICENSE` is MIT.
- [ ] The About block lists **libmpv / ffmpeg / libass LGPL notices with links to both build-script
      repos**, the OFL fonts, the ISC icons and the CC0 sounds — typeset, not hidden behind a link.
- [ ] "Subtitles by OpenSubtitles.com" appears in the Lobby footer **and** the Ticket Office.
- [ ] With TMDB enabled, the TMDB logo and the **verbatim** notice appear wherever artwork does; with
      it disabled, **no** network call to TMDB is made and the logo is gone.
- [ ] The shipped Android native flavour is `default` (**never** `encoders-gpl`) and the Windows DLL
      is an LGPL build whose SHA-256 matches `tools/libmpv-windows.sha256`.
- [ ] No AGPL/GPL dependency anywhere; `guessit-js` appears in no lockfile.
- [ ] Greps find **no** analytics/telemetry/crash-reporting SDK, no key in any bundle, no `.p12` or
      `key.properties` in the tree, and no `console.*` in `worker/`.
- [ ] The Ticket Office About page lists the three APIs and **exactly what data each receives**.
- [ ] Each licence item in the release PR names **the file and line that satisfies it**.

### 12.5 Documentation gates

- [ ] `README.md` carries: what it is, screenshots **from the real app**, the Quickstart (download the
      zip / sideload the APK / open the Lite URL), the **SmartScreen warning stated before the user
      meets it**, the keyboard table generated from `cue-sheet.json`, the OpenSubtitles quota
      explanation, and an **Attribution** section.
- [ ] `CHANGELOG.md` has a `v1.0.0` entry written by hand, not only generated notes.
- [ ] If any golden number moved during the build, the document that stated it moved **in the same
      commit**.

---

## 13. Code quality rules

### 13.1 Language and typing

- **TypeScript is `strict`** — plus `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`,
  `noImplicitOverride`, `verbatimModuleSyntax`. **No `any`.** Use `unknown` at boundaries and narrow.
  Brand identifiers that must not be confused (`MovieHash`).
- **Dart:** `flutter_lints` plus `--fatal-infos` in CI. Prefer `final`; make every engine model
  immutable and `const`-constructible; use `sealed class` for closed unions (`SubtitleTrackRef`,
  `LeaderEvent`) and switch exhaustively so a new variant is a compile error.
- **No `dynamic`, no `late` without a comment justifying it, no `!` on a nullable** unless the line
  above proves it non-null.
- Errors are typed. `lib/api` maps every HTTP status to a `ThreadingFailure` **before** it reaches
  state; no raw exception crosses a provider boundary.

### 13.2 Formatting and linting

- **Biome** is the only formatter/linter for `web/` and `worker/`; `dart format` + `flutter_lints`
  for Dart. Both run in CI with `--set-exit-if-changed` / `biome ci`.
- `noConsole` is **error** inside `worker/` and **warn** elsewhere. There is no logging framework:
  the app prints nothing in release.
- No commented-out code. No `TODO` without an issue link. No `@ts-expect-error` without a one-line
  reason.

### 13.3 Architecture conventions

- **Engine purity is enforced by a test.** `lib/engine/**` may not import `package:flutter/…`,
  Riverpod, drift, or `http`. It takes plain values and returns plain values. The same rule applies
  to `web/src/engine/**`: no DOM, no `fetch`, no `window`.
- **UI never touches `lib/api` or `lib/db`.** Only providers do. A widget that needs data watches a
  provider; a widget that causes an effect calls a provider method.
- **One file, one concept.** A component file exports one component plus its private helpers. An
  engine file exports one algorithm plus its types.
- **Feature folders, not layer folders**, inside `lib/ui/` — `lobby/`, `threading/`, `auditorium/`,
  `booth/`, `ticket_office/`, with shared primitives in `components/`.
- **Naming:** Dart files `snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`;
  TypeScript files `camelCase.ts` (components `PascalCase` where they are classes). Golden files
  `component_state.png` (`marquee_now_showing_night.png`).
- **Widget size:** if a `build()` exceeds ~80 lines or nests more than five levels, extract a widget.
  Never use a builder function where a widget class belongs (it breaks `const` and rebuild scoping).
- **`const` everywhere it is legal.** A rebuild you did not need is a frame you did not get.

### 13.4 The token discipline

- **No hard-coded colour, spacing, radius, duration or easing anywhere in UI code.** Everything comes
  from `tokens.css` / `tokens.dart`, which are **generated**. A hand edit to either file fails CI.
- Adding a token means editing `scripts/tokens.mjs`, regenerating both outputs, **and adding a row to
  the contrast table** — a token with no contrast row fails the test.
- Magic numbers in the engine are named constants at the top of the file with the reason in a comment
  (`_kLetterboxTone = 8; // L* below this is letterbox, not the film's colour`).

### 13.5 Dependencies

- **Every dependency needs a one-sentence justification** in the PR that adds it, plus its licence.
- **The Worker stays at zero runtime dependencies.** Forever.
- `pubspec.lock` and both `package-lock.json` files are committed; CI uses `npm ci`, never
  `npm install`. Dependabot is on.
- Prefer 60 lines of your own code over a package you would use 5 % of (that is why `srt2vtt`,
  the IndexedDB wrapper and the Kotlin channels are hand-rolled).

### 13.6 No dead code

- If a feature is cut, **delete it** — do not comment it out and do not leave it behind a flag that is
  never true. Git remembers.
- No unused exports, no unused CSS classes, no orphan assets. CI's `size-limit` and the licence
  script both notice.
- A flag that exists must be reachable from the UI or from a test. There are exactly two legitimate
  flags in this app: the ambience bulbs (user-facing) and `RUN_DOWNLOAD_PROBE` (test-only).

### 13.7 Tests and commits

- **Engine first.** A pure function lands with its golden table in the same commit. If a golden
  number changes, the document that states it changes in the **same** commit.
- **A test names a behaviour, not a method:** `test('freezes the sweep when the search rejects')`,
  not `test('threading works')`.
- **Commit cadence:** small, green, imperative subject lines under 72 characters, scoped
  (`engine: round sync-rule detents instead of flooring`). Every commit builds. Never commit a red
  `main`.
- One PR per checkpoint in §9 where practical; the PR description carries the checkpoint's **Verify**
  line and how you verified it.
- A PR that touches `test/goldens/**` must say **why** in its description, and the diff is reviewed as
  an image, never accepted blind.
- Never commit: a `.p12`, a key, a `local.properties`, a real subtitle file, a real film, or a
  screenshot containing a filename you would not publish.

### 13.8 The five rules that matter most

1. **The leader never lies.** If a phase has not resolved, its numeral does not advance.
2. **A ticket is never spent twice.** Sidecar, then cache, then network — in that order, every open.
3. **One value drives the lighting.** `--house` and nothing else.
4. **The engine is pure and the goldens are shared.** Dart and TypeScript can never drift.
5. **No secret ever reaches a bundle.** The Worker holds the key; native gets it at build time; the
   browser never sees it.
