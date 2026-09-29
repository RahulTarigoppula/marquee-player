# Marquee — Testing Strategy & Test Plan

Written 2026-09-06. Binding inputs: `_shared/DECISIONS.md` (D1 Marquee exception: Flutter + media_kit native tier, Vite + TypeScript web tier; D2 mandatory Cloudflare Worker; D5 licensing; D7 token contract; D9 "engine first"), `docs/RESEARCH.md` (§3 API facts, §5.2 identification pipeline, §5.3 playback config, §5.4 web tier, §8 risks, verification log), `docs/DESIGN.md` (§4 colour + contrast tables, §7 motion, §8 signature interactions, §9 screens, §13 a11y, §14 Android, §15 tokens). `GOAL.md` (repo root) / `docs/ARCHITECTURE.md` were being written in parallel; where they name a module differently, they win and this file's paths get renamed.

Marquee is three deployables that must be tested differently:

| Tier | Stack | Test tooling | Runs where |
|---|---|---|---|
| **Native** (Windows exe + Android APK) | Flutter (stable, pinned) + media_kit (libmpv/libass) + drift | `flutter test` (unit + widget), golden tests (`matchesGoldenFile`), `integration_test` with the real player | `ubuntu-24.04` (unit/golden), `windows-latest` (integration with libmpv), owner's phone (manual) |
| **Web** ("Marquee Lite") | Vite + TypeScript (no React), JASSUB, optional movi-player/mediabunny | Vitest, `@testing-library/dom`, Playwright (branded Chrome + Firefox + Pixel 7 profile), screenshots | `ubuntu-24.04`; codec matrix also checked by hand in Edge/Chrome/Firefox on the owner's PC |
| **Worker** (`marquee-proxy`) | Cloudflare Worker, TypeScript | Vitest with `@cloudflare/vitest-pool-workers` (`SELF.fetch`, `fetchMock`) + a nightly contract test against the real OpenSubtitles API | `ubuntu-24.04` |

The riskiest pieces — libass on a real phone, battery/thermals, the Windows `libmpv-2.dll` swap, and whether browsers really decode MKV/HEVC/AC-3 — cannot be proven in CI. They are on the day-1 list (§13) and the manual checklists (§14, §15).

---

## 1. Strategy at a glance

| Layer | Tool | What it proves | Where | Gate |
|---|---|---|---|---|
| Unit (Dart engine) | `flutter test` on `lib/engine/**` (pure Dart, no Flutter imports) | moviehash, filename grammar, candidate scoring, quota/ticket model, timecodes, sync-rule detents, chapter detents, leader state machine, OpenSubtitles client behaviour against fixture JSON | `test/engine/**_test.dart` | Every PR; 100 % line coverage on `hash.dart`, `scoring.dart`, `timecode.dart`, `sync_rule.dart`, `tickets.dart`; ≥ 90 % on the rest of `lib/engine` |
| Unit (drift) | `flutter test` with `NativeDatabase.memory()` | Library rows, hash cache (`moviehash+lang → file_id, path`), resume positions, per-hash sync offsets, TMDB cache expiry (≤ 6 months), migrations | `test/db/**_test.dart` | Every PR |
| Widget + golden | `flutter test` (+ `--tags golden`), fonts loaded in `flutter_test_config.dart` | Marquee sign, leader, ticket strip, film gate, sync rule, candidate row, booth sheet, Ticket Office look exactly like `design/preview.html`; Auditorium and Matinee palettes; reduced motion | `test/widgets/**`, goldens in `test/goldens/` (generated on Linux only) | Every PR; goldens diffed by eye |
| Integration (native) | `flutter test integration_test -d windows` on `windows-latest`, real libmpv, committed ≥ 128 KiB fixtures | File opens → first frame; SRT and ASS attach and render; seek + chapter detents; keyboard map; house-down/up; error states | `integration_test/*_test.dart` | `release.yml` `test` job + weekly |
| Unit (web) | Vitest (`environment: happy-dom`) | `osHash` (BigInt), SRT→VTT, capability probe, ticket copy, timecode, sync-rule (same goldens as Dart) | `web/src/**/*.test.ts` | Every PR (`pages.yml` runs `npm test -- --run`) |
| Component (web) | `@testing-library/dom` + `@testing-library/user-event` | Lite landing, drop frame, No Print card, leader, candidate list, sync rule announce correctly and are keyboard-operable | `web/src/**/*.test.ts` | Every PR |
| E2E (web) | Playwright 1.5x — projects `chrome` (branded, has H.264/AAC), `firefox`, `pixel-7` (branded Chrome, touch) | Real `<video>`, real drag/drop and `<input type=file>`, real JASSUB canvas, Worker mocked with `page.route`, PWA offline | `web/e2e/*.spec.ts` | `ci.yml` on every PR; never blocks `pages.yml` |
| Visual (web) | Playwright `toHaveScreenshot` + computed-style assertions against `tokens.css` | The Lite landing, Threading mid-sweep, Auditorium with controls, No Print card match the preview; contrast goldens | `web/e2e/visual/*.spec.ts` | Every PR |
| Worker | `@cloudflare/vitest-pool-workers` | CORS/preflight, origin allow-list, path allow-list, header injection, param sorting, Authorization forwarding, cache policy, rate-limit header passthrough, key never leaks | `worker/test/*.test.ts` | Every PR + before every Worker deploy |
| Contract (live) | Vitest, skipped unless `OS_API_KEY` is present | Real OpenSubtitles responses still have the shape the fixtures assume; unverified endpoints/params (§13) | `worker/test/contract.test.ts` | Nightly `contract.yml` + day 1 |
| Performance | mpv properties via media_kit, Flutter timeline summaries, Lighthouse CI, bundle sizes, APK/zip sizes | Budgets in §9 | `integration_test/perf_test.dart`, `web/e2e/perf/*.spec.ts`, `web/lighthouserc.json`, release workflow size gates | Weekly + before every tag |
| Accessibility | `@axe-core/playwright` (web), Flutter `meetsGuideline(textContrastGuideline)` + `androidTapTargetGuideline` + semantics tests (native), manual NVDA/TalkBack pass | §10 | `web/e2e/a11y.spec.ts`, `test/a11y/**` | Every PR (automated), before every tag (manual) |
| Device | Manual checklist on the owner's phone (Android 14+) and Windows 11 PC with the tag's own artifacts | Permissions, back gesture, rotation, PiP, audio focus, libass, battery, frameless window, SmartScreen | §14, §15 | Before every `v*` tag |

**Commands** (run from the repo root unless stated; the Flutter app lives at the root, the web tier in `web/`, the Worker in `worker/` — see DEPLOYMENT §1):

| What | Command |
|---|---|
| Dart unit + widget | `flutter test --exclude-tags golden` |
| Goldens (Linux/CI only) | `flutter test --tags golden` · regenerate: `flutter test --tags golden --update-goldens` |
| Coverage | `flutter test --coverage && genhtml coverage/lcov.info -o coverage/html` |
| Native integration (Windows) | `flutter test integration_test -d windows` |
| Web unit/component | `cd web && npm test -- --run` |
| Web e2e | `cd web && npx playwright test` · visual: `npx playwright test e2e/visual` · update: `--update-snapshots` |
| Worker | `cd worker && npm test` · contract: `OS_API_KEY=… npm run test:contract` |
| Tokens in sync | `node scripts/tokens.mjs && git diff --exit-code web/src/styles/tokens.css lib/theme/tokens.dart` |
| Everything CI runs | `.github/workflows/ci.yml` (§16) |

**Determinism rules**
- The clock is injected everywhere it shows: sky band (time of day), marquee night flicker, `RESETS 00:00 UTC` countdown, TMDB cache expiry. Dart: a `Clock` (package `clock`, `withClock(Clock.fixed(DateTime.utc(2026, 9, 6, 15, 44)))`). Web: `vi.setSystemTime(new Date('2026-09-06T21:14:00+05:30'))` and Playwright `page.clock.install({ time: '2026-09-06T21:14:00+05:30' })` — 21:14 IST = **night** (bulbs lit, flicker on), which is the house fixture.
- Every RNG (flicker, dust sprites, seeded IDs) takes a seed; tests pass `Random(8)`.
- Network is never real in unit/e2e tests: Dart uses `package:http/testing.dart` `MockClient`; the web tier's Playwright suites intercept `**/api/**` with `page.route`; the Worker suite uses `fetchMock` from `cloudflare:test`. Only `contract.test.ts` touches the real API.
- Fixtures are bit-exact: `scripts/make-fixtures.sh` (§2.2) uses `-fflags +bitexact -flags:v +bitexact -flags:a +bitexact -map_metadata -1`, so the same command on any ffmpeg 6/7 build reproduces the same bytes and therefore the same moviehash. The hashes are frozen in `test/fixtures/hashes.json` and asserted by both Dart and TS suites.
- `TZ=Asia/Kolkata` in `vitest.config.ts` and `playwright.config.ts`; the ticket strip always prints UTC so it is unaffected.
- Fonts: `test/flutter_test_config.dart` loads Big Shoulders Display, Geist, Geist Mono and Noto Sans through `FontLoader` before any golden runs; otherwise Flutter's test binding renders the Ahem block font and every golden is meaningless.

---

## 2. Test layout and fixtures

```
lib/engine/                                  # pure Dart, no Flutter imports (D9 "engine first")
  hash.dart          → test/engine/hash_test.dart            moviehash (RandomAccessFile), 128 KiB rule
  filename.dart      → test/engine/filename_test.dart        Dart port of parse-torrent-title (MIT) — NOT guessit-js (LGPL)
  scoring.dart       → test/engine/scoring_test.dart         subliminal-style candidate ranking
  opensubtitles.dart → test/engine/opensubtitles_test.dart   REST client: sorted params, headers, 401/406/410/429
  subdl.dart         → test/engine/subdl_test.dart           fallback provider (search keyed, download anonymous, zip)
  tickets.dart       → test/engine/tickets_test.dart         quota model → ticket-strip copy
  timecode.dart      → test/engine/timecode_test.dart        folio strings
  sync_rule.dart     → test/engine/sync_rule_test.dart       50 ms detents, clamp, J/K, per-hash memory
  detents.dart       → test/engine/detents_test.dart         chapter/5-min detents, capture radius
  threading.dart     → test/engine/threading_test.dart       leader state machine (3 → 2 → 1 → flash), stalls, fallbacks
  bias_light.dart    → test/engine/bias_light_test.dart      quantizer over an RGBA buffer → 5 stops
  srt.dart           → test/engine/srt_test.dart             SRT parse/shift (native uses mpv sub-delay; parser shared for "save beside file" rewrites)
lib/db/              → test/db/                              drift schema, hash cache, migrations, TMDB expiry
lib/ui/              → test/widgets/, test/goldens/           widget + golden tests
integration_test/                                            player_test, subtitles_test, seek_test, keyboard_test, house_test, perf_test
test/fixtures/                                               media + JSON fixtures (below)
test/flutter_test_config.dart                                font loading, golden comparator tolerance (0.5 %), fixed clock

web/src/engine/      → web/src/engine/*.test.ts               osHash, srt2vtt, capability, tickets, timecode, syncRule (same goldens)
web/src/ui/          → web/src/ui/*.test.ts                   Testing Library (DOM)
web/e2e/                                                     lite.spec, playback.spec, threading.spec, subtitles.spec, noprint.spec,
                                                             offline.spec, keyboard.spec, a11y.spec, visual/*.spec, perf/*.spec
web/e2e/fixtures/                                            symlink/copy of test/fixtures media + Worker response JSON
worker/test/                                                 worker.test.ts, contract.test.ts, fixtures/*.json
scripts/make-fixtures.sh                                     regenerates media fixtures bit-exactly (ffmpeg)
scripts/tokens.mjs                                           tokens.css + tokens.dart from one source
```

### 2.1 Golden data — moviehash

The OpenSubtitles hash is `size + Σ le_u64(first 64 KiB) + Σ le_u64(last 64 KiB)` mod 2⁶⁴, printed as 16 lowercase hex digits; files under 128 KiB are rejected (RESEARCH §3, verified).

| Vector | Input | Expected | Why it matters |
|---|---|---|---|
| **V1 — official** | `breakdance.avi` from https://opensubtitles.github.io/oshash/ (12 909 756 bytes; downloaded once by `scripts/make-fixtures.sh`, never committed — 12 MB) | `8e245d9679d31e12` | **One of the two** externally published vectors; run in CI only when the download succeeds, otherwise skipped with a warning |
| **V2 — zeros** | 131 072 bytes, all `0x00` | `0000000000020000` (= size) | Boundary: exactly 128 KiB is accepted; both chunks are the same bytes |
| **V3 — ones** | 131 072 bytes, all `0xFF` | `000000000001c000` | 64-bit wrap: each chunk sums to 2⁶⁴ − 8192; size + 2·(2⁶⁴ − 8192) ≡ 131 072 − 16 384 = 114 688 = 0x1C000 |
| **V4 — long zeros** | 200 000 bytes, all `0x00` | `0000000000030d40` | Last chunk starts at `size − 65 536`, not at a chunk boundary |
| **V5 — too small** | 131 071 bytes | throws `FileTooSmall` (Dart) / rejects with `FILE_TOO_SMALL` (TS) | Threading must skip the hash and go straight to filename search (DESIGN §9.2 "File < 128 KiB" state), never show an error |
| **V6 — fixtures** | every file in `test/fixtures/media/` | value in `test/fixtures/hashes.json` | Regression lock on the fixture generator |
| **V7 — sparse 2³²** | a *stub* source (fake `RandomAccessFile` / `Blob`) reporting `size = 4 294 967 296` (2³²) whose two 64 KiB chunks are all `0x00` — no 4 GB file, no download | `0000000100000000` (= size; both chunk sums are 0) | **The large-file vector.** It is the only one that catches 32-bit truncation in `raf.setPosition(sizeBytes - kChunk)` / `Blob.slice(file.size - CHUNK)` and a `Number` leak in the TS path. Success criterion #2 includes 4K HEVC files that routinely exceed 4 GB |

**The second published vector.** https://opensubtitles.github.io/oshash/ ships **two** vectors, not one: `breakdance.avi` (V1) and **`dummy.rar`, 4 295 033 890 bytes → `61f7751fc2a72bfb`**. The larger one is the one that matters, because its size exceeds 2³² and so it is the only published vector that exposes 64-bit overflow and large-file seek bugs. We do **not** download 4 GB in CI; **V7 covers exactly that failure mode synthetically**, and `dummy.rar` stays documented here as the external cross-check anyone can run by hand once.

V2–V5 and V7 are constructed in memory by the test (no files in git). The Dart implementation relies on VM ints wrapping at 64 bits — the test also asserts `toUnsigned(64)` is applied so a negative wrap never prints a `-`. The TS implementation uses `BigInt` and masks with `0xffff_ffff_ffff_ffffn`; the test asserts `padStart(16, '0')` on V2.

### 2.2 Media fixtures (`test/fixtures/media/`, regenerated by `scripts/make-fixtures.sh`)

Committed (all ≥ 128 KiB so they hash, all < 1 MB so the repo stays light):

| File | ffmpeg recipe (bit-exact flags implied) | Used by |
|---|---|---|
| `testsrc-10s-h264-aac.mkv` | `-f lavfi -i testsrc2=size=320x180:rate=24000/1001 -f lavfi -i sine=frequency=1000 -t 10 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 64k` + `-map_chapters` from `chapters.ffmeta` (chapters at 0 s "Leader", 3 s "Reel 1", 6 s "Reel 2") + embedded SRT track (`sample.srt`) + embedded ASS track (`sample.ass`) | player_test, seek_test (detents), subtitles_test (embedded tracks), web playback (Chrome plays H.264 MKV) |
| `testsrc-10s-h264-aac.mp4` | same streams, `-movflags +faststart` | web playback fast path (every browser) |
| `testsrc-10s-vp9-opus.webm` | `-c:v libvpx-vp9 -b:v 200k -c:a libopus` | web playback in Firefox |
| `testsrc-10s-hevc-ac3.mkv` | `-c:v libx265 -x265-params log-level=0 -crf 24 -c:a ac3 -b:a 96k` | No Print path on the web (RESEARCH §5.4), HEVC hwdec on native |
| `testsrc-10s-h264.avi` | `-c:v mpeg4 -q:v 4 -c:a mp3` | "any container" on native; hash V6 |
| `tiny-100kib.mkv` | first fixture cut with `-fs 102400` | V5 too-small path |
| `corrupt.mkv` | 200 KiB of `/dev/urandom` with seed via `openssl enc -aes-256-ctr -pass pass:marquee -nosalt < /dev/zero` | "Undecodable print" error state |
| `frame-bias.png` | 64×36 PNG: 60 % `#FFC56E`, 30 % `#A3252F`, 10 % `#5FD48A` (drawn by the script with ImageMagick or a 20-line Node script) | bias-light quantizer golden |

Text fixtures: `sample.srt` (4 cues, includes `<i>` and a two-line cue), `sample-crlf-bom.srt` (UTF-8 BOM + CRLF + a cue with index out of order), `sample.ass` (Noto Sans style, one `\pos` override, one `\an8` top cue — proves libass/JASSUB positioning), `sample-hi.srt` (bracketed `[DOOR SLAMS]` for the HI heuristic).

`ffmpeg` is preinstalled on `ubuntu-24.04`; the script runs as a CI check (`make-fixtures.sh && git diff --exit-code test/fixtures`) so a drifted fixture fails loudly. The Windows runner never regenerates fixtures — it consumes the committed bytes.

### 2.3 Golden data — filename grammar (`filename.dart` / `filename.ts`)

Expected output of *our* parser (a Dart/TS port of MIT `parse-torrent-title`, extended for anime brackets). These names also appear in the DESIGN wireframes, so the same strings show up in goldens.

| Filename | title | year | S/E | resolution | source | codec | group | notes |
|---|---|---|---|---|---|---|---|---|
| `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv` | The Third Man | 1949 | — | 1080p | BluRay | x264 | AMIABLE | the house film |
| `Chungking.Express.1994.REMASTERED.1080p.BluRay.x265-RARBG.mkv` | Chungking Express | 1994 | — | 1080p | BluRay | x265 | RARBG | `remastered: true` |
| `Paddington.2014.720p.WEB-DL.H264-NTb.mkv` | Paddington | 2014 | — | 720p | WEB-DL | H264 | NTb | |
| `Severance.S02E04.1080p.WEB.H264-NTb.mkv` | Severance | — | 2 / 4 | 1080p | WEB | H264 | NTb | `type: 'episode'` |
| `The Third Man (1949).mkv` | The Third Man | 1949 | — | — | — | — | — | spaces + parentheses |
| `[SubsPlease] Frieren - 12 (1080p) [ABCD1234].mkv` | Frieren | — | — / 12 | 1080p | — | — | SubsPlease | anime bracket form; hash in trailing brackets ignored |
| `movie.mkv` | movie | — | — | — | — | — | — | `confidence: 'low'` → Threading uses `query=<raw filename>` (server-side guessit) instead of `query=<title>` |
| `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.en.srt` | — | — | — | — | — | — | — | `.srt` is not a video → rejected by the picker filter, never parsed |

Title cleaning rules asserted: dots/underscores → spaces; year is the *last* 19xx/20xx token before a quality token; group is the token after the last `-` unless it is a codec; everything after the first quality token is not title.

### 2.4 Golden data — candidate scoring (`scoring.dart` / `scoring.ts`)

Weights (from RESEARCH §5.2, subliminal-style): hash match 1000 ≫ same release group 200 ≫ same source 100 ≫ same resolution 50 ≫ same video codec 20; then `+ log10(download_count)`; hearing-impaired: −30 unless the user prefers HI (then +30); `fps` equal to the container's fps ±0.01: +40, unequal: −40, unknown: 0; `ai_translated`/`machine_translated`: −500 (never auto-picked, still listed).

Fixture `candidates-third-man.json` (mirrors the DESIGN §9.2 wireframe), file = `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv`, container fps 23.976:

Rows are listed in **scoring order** — the same order ARCHITECTURE §6.3 and IMPLEMENTATION-PROMPT §6.4 print, and the same order the DESIGN §9.2 wireframe and `design/preview.html` draw: **A > D > C > B > E**.

| id | release | moviehash_match | downloads | HI | fps | Score | Expected rank (HI not preferred) | Expected rank (HI preferred) |
|---|---|---|---|---|---|---|---|---|
| A | `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE` | true | 12 431 | false | 23.976 | 1000+200+100+50+20+40+4.09 = **1414.09** | **1** · auto-pick | **1** |
| D | `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE` | false | 51 000 | false | 23.976 | 200+100+50+20+40+4.71 = **414.71** | **2** | **2** |
| C | `The.Third.Man.1949.BluRay-AMIABLE` | false | 902 | true | 25 | 200+100−40−30+2.96 = **232.96** | **3** | **3** |
| B | `The.Third.Man.1949.1080p.WEB-DL.H264-NTb` | false | 4 102 | true | 23.976 | 50+40−30+3.61 = **63.61** | **4** | **4** |
| E | any, `machine_translated: true` | true | 99 999 | false | 23.976 | 1000−500+… — always < A's 1414.09 | last, `autoPick: false` | last |

The HI-preferred column is identical because flipping HI from −30 to +30 lifts B to 123.61 and C to 292.96 — both still below D's 414.71 and above nothing new. Assert both columns; a change that reorders one and not the other is a bug.

The scores are exact to 2 decimal places (PLAN 2.3's acceptance): log₁₀(12431)=4.0945, log₁₀(51000)=4.7076, log₁₀(902)=2.9552, log₁₀(4102)=3.6130, giving 1414.0945 / 414.7076 / 232.9552 / 63.6130. Round half-up to 2 dp for the table.

Note on C vs B: with these weights C (232.96) outranks B (63.61) — the fixture is authored so the test *documents* that release-group match beats fps mismatch. If the product decision flips (fps mismatch should sink a candidate below a same-fps WEB-DL), change the fps penalty to −250 and update this table in the same commit. Additional assertions: ties broken by `download_count`; the auto-pick is rank 1 unless `autoPick: false`; the list keeps every candidate (nothing filtered, only ordered); language filter is applied *before* scoring; Subdl candidates carry `provider: 'subdl'` and score with `moviehash_match: false` always.

### 2.5 Golden data — SRT → WebVTT and delay (`srt.dart`, `srt2vtt.ts`)

`sample-crlf-bom.srt` (BOM, CRLF, cue 2 listed before cue 1, one `<i>` cue, a cue without a trailing blank line at EOF) →

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

Assertions: comma → dot in timestamps; BOM stripped; CRLF → LF; cues sorted by start time (index renumbered); `<i>`/`<b>`/`<u>` kept (VTT supports them), `<font color>` stripped to text; `{\an8}` ASS-style tags in SRT converted to `line:0` position; overlapping cues kept as-is (VTT allows overlap); a delay of `+0.35` s shifts *every* cue by +350 ms (`00:01:02.850 --> 00:01:04.350`) and never produces a negative start (clamped to `00:00:00.000`). Native tier: the same parser is used only when "Save beside file" rewrites an SRT with the remembered offset baked in (opt-in); playback delay goes through mpv `sub-delay` and is not re-encoded.

### 2.6 Golden data — quota → ticket strip (`tickets.dart` / `tickets.ts`)

Input is the OpenSubtitles `/download` response (`requests`, `remaining`, `reset_time_utc`) or the login `user.level`/`allowed_downloads`, plus the fixed clock 2026-09-06T15:44Z.

| Input | Strip text | Colour | State | aria-label |
|---|---|---|---|---|
| `{requests: 3, remaining: 7, reset_time_utc: "2026-09-07T00:00:00.000Z"}` | `7 OF 10 TONIGHT · RESETS 00:00 UTC` | `--ink` | `n-left` | "7 of 10 downloads left tonight" |
| `remaining: 2` | `2 OF 10 TONIGHT · RESETS 00:00 UTC` + "Sign in at the ticket office (free, more tickets)" or "Use the Subdl slot" | `--accent-2` strip, text `--accent-2-lit` | `two-left` | "2 of 10 downloads left tonight" |
| `remaining: 0` or HTTP **406** | `NO TICKETS LEFT TONIGHT · RESETS 00:00 UTC` + sentence "No tickets left tonight — sign in for more, or use the Subdl slot" | `--accent-2` / `--accent-2-lit` | `exhausted` | "No downloads left tonight" |
| signed out (no JWT) | `ANONYMOUS · 5 PER DAY PER IP` | `--ink-muted` | `anonymous` | "Anonymous: 5 downloads per day per network" |
| `allowed_downloads: 20` from login | total shows **20**, not 10 (`7 OF 20 TONIGHT`) | | | The two help articles disagree (10 vs 20) — the app trusts the login response, never a constant |
| `allowed_downloads: 1000, vip: true` | `7 OF 1000 · VIP` and `base_url` from login is used for subsequent calls | | `vip` | |
| HTTP **429** with `Retry-After: 2` | strip unchanged; leader "2" stalls; sentence "OpenSubtitles asked us to wait 2 s" | `--warning` | — | announced once |
| HTTP **410** on the `link` | "That print expired — fetching a fresh link" then one retry of `/download` (costs a ticket only if the server says so: assert `remaining` from the retry is what is shown) | `--warning` | — | |

The ticket count decrements *after* the `ticket-tear` animation completes (DESIGN §7 #9) — the model exposes `pendingTear` so the widget test can assert order.

### 2.7 Golden data — folio timecodes (`timecode.dart` / `timecode.ts`)

Position floors to whole seconds, remaining ceils, so both add up to the duration; always `HH:MM:SS`, tabular figures, U+2212 minus.

| position s | duration s | Folio |
|---|---|---|
| 4364.4 | 9663 | `01:12:44 · −01:28:19` (the DESIGN wireframe) |
| 0 | 9663 | `00:00:00 · −02:41:03` |
| 9663 | 9663 | `02:41:03 · −00:00:00` |
| 59.999 | 61 | `00:00:59 · −00:00:02` |
| 3599.2 | 3600 | `00:59:59 · −00:00:01` |
| 45 000 | 45 000 | `12:30:00 · −00:00:00` (never wraps at 24 h) |
| unknown duration (live/stream) | — | `00:00:45 · —` |

Speed suffix: 2× while long-pressing → `2.0×` appended; A–B loop → `A–B` appended. Threading folio: `REEL 01 · THREADING`. Auditorium desktop folio: `REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19` (title uppercased, condensed to 40 chars with `…`).

### 2.8 Golden data — sync rule and chapter detents

Sync rule (`sync_rule.dart`): detent 0.05 s, range ±2.00.

| Action | From | To | Folio |
|---|---|---|---|
| drag to +0.37 | 0 | **+0.35** | `SUB +0.35` |
| drag to +0.376 | 0 | +0.40 (nearest, not floor) | `SUB +0.40` |
| drag to +2.40 | 0 | +2.00 (clamped) | `SUB +2.00` |
| `K` | +0.35 | +0.40 | |
| `J` | +0.35 | +0.30 | |
| `Shift+K` | +0.35 | +0.85 | |
| long-press readout / `Shift+J+K` | +0.85 | 0.00 | readout `SYNC +0.00`, folio suffix removed |
| reopen same moviehash | — | remembered value (+0.35) | Lobby card shows `±0.35` badge |
| reopen different hash | — | 0.00 | |

The value written to mpv is the string `"0.35"` via `setProperty('sub-delay', …)`; the web tier shifts VTT cues (§2.5). Sign convention: positive = subtitles appear later.

Chapter detents (`detents.dart`): source is mpv `chapter-list`; with no chapters, detents every 300 s; capture radius **6 px** at the gate's rendered width. Fixture: width 800 px, duration 9663 s (12.08 s/px), chapters at 0 / 1800 / 4200 / 7200 s.

| Release at px | Nearest detent px | Result |
|---|---|---|
| 152 | 149.0 (1800 s) | snap → 1800 s, `gate-snap` spring, light haptic + selection tick |
| 160 | 149.0 | 11 px away → no snap → 1932.6 s |
| 0 | 0 | 0 s |
| 800 | — (7200 s is 596 px) | 9663 s (end; no snap to a chapter that is not within 6 px) |
| any, FINE mode (drag up off the strip) | — | detents disabled, 1/8 speed: 80 px of drag = 10 px of gate = 120.8 s |

### 2.9 OpenSubtitles fixture JSON (`test/fixtures/os/`, shared with `worker/test/fixtures` and `web/e2e/fixtures`)

Hand-written from the RESEARCH §5.2 response shapes; the nightly contract test (§7.2) re-validates the shapes against the live API and fails if a field the app reads disappears.

- `search-hash-hit.json` — `total_count: 3`, three `data[]` entries A/B/C from §2.4 with `attributes.moviehash_match: true` on A, `files[0].file_id: 1234567`, `feature_details: { feature_type: "Movie", title: "The Third Man", year: 1949, imdb_id: 41959, tmdb_id: 1092 }`.
- `search-miss.json` — `total_count: 0, data: []`.
- `search-by-name.json` — two entries, no `moviehash_match`, one `machine_translated: true`.
- `login-ok.json` — `{ token: "eyJ…", user: { allowed_downloads: 20, level: "Sub leecher", user_id: 1, vip: false }, base_url: "api.opensubtitles.com", status: 200 }`.
- `login-vip.json` — `allowed_downloads: 1000, vip: true, base_url: "vip-api.opensubtitles.com"`.
- `download-ok.json` — `{ link: "https://www.opensubtitles.com/download/…/subtitle.srt", file_name: "the.third.man.1949.srt", requests: 3, remaining: 7, reset_time: "08 hours and 16 minutes", reset_time_utc: "2026-09-07T00:00:00.000Z" }`.
- `download-406.json` — status 406, `{ message: "Download limit reached", remaining: 0, reset_time_utc: … }`.
- `401.json` — `{ message: "Unauthorized" }` (expired JWT → silent re-login prompt in the Ticket Office, never a red banner).
- `429.txt` — status 429, headers `Retry-After: 2`, `X-RateLimit-Limit: 5`, `X-RateLimit-Remaining: 0`, `X-RateLimit-Reset: 1`.
- `link-410.txt` — status 410 on the download link.
- `guessit-ok.json` — `{ title: "The Third Man", year: 1949, screen_size: "1080p", source: "Blu-ray", video_codec: "H.264", release_group: "AMIABLE", type: "movie" }` — used only if the day-1 check (§13 #4) confirms `/utilities/guessit` exists.
- `subdl-search.json` / `subdl-zip.bin` — Subdl search result and a 1-cue zip.
- `tmdb-find.json` — `/find/tt0041959?external_source=imdb_id` → `movie_results[0].{id: 1092, poster_path, backdrop_path}`.

`imdb_id: 41959` (tt0041959) is The Third Man; `tmdb_id: 1092` is recorded from memory — confirm both on day 1 (§13 #12) and then freeze.

### 2.10 Golden data — web capability line (`capability.ts`)

The Lite landing prints one honest line from `canPlayType` + `VideoDecoder.isConfigSupported` (DESIGN §9.6). The unit test stubs both; the e2e test asserts only what is certain per browser.

| Probe | Stubbed result | Line fragment |
|---|---|---|
| `video/mp4; codecs="avc1.42E01E, mp4a.40.2"` | `probably` | `MP4/H.264 ✓` |
| `video/webm; codecs="vp9, opus"` | `probably` | `WebM/VP9 ✓` |
| `video/webm; codecs="av01.0.05M.08"` | `probably` / `""` | `AV1 ✓` / `AV1 ✗` |
| `video/mp4; codecs="hvc1.1.6.L93.B0"` → then `VideoDecoder.isConfigSupported({codec:'hvc1.1.6.L93.B0'})` | `""` + `{supported:true}` | `HEVC ✓ (WebCodecs)` |
| both negative | | `HEVC ✗` |
| `audio/mp4; codecs="ac-3"` | `""` | `AC-3 ✗` (movi-player software fallback offered in the No Print card, not counted as ✓) |
| MKV | never probed — policy | `MKV partial` always |
| `window.VideoDecoder` undefined | | line ends `· WebCodecs unavailable`, "Try the WebCodecs path" button hidden |

E2E certainties: `chrome` project → contains `MP4/H.264 ✓` and `WebM/VP9 ✓`; `firefox` → contains `AC-3 ✗`; all → contains `MKV partial`.

### 2.11 Golden data — bias light (`bias_light.dart`)

Input `frame-bias.png` (§2.2) → five stops ordered by population: stop 0 within ΔE2000 < 5 of `#FFC56E`, stop 1 of `#A3252F`, stop 2 of `#5FD48A`; stops 3–4 are the darkened duplicates the quantizer produces and must have L < stop 2's L. An all-black frame (letterbox) → `null` (the widget keeps `--focus` at 6 %). A frame that is 95 % black + 5 % tungsten → black is excluded (pixels with L\* < 8 are dropped before quantizing) and stop 0 is tungsten. Sampling cadence is a widget concern (500 ms desktop / 1000 ms Android, `bias-lerp` 600 ms; 1200 ms in reduced motion) and is asserted in the widget test with a fake ticker.

### 2.12 Golden data — contrast (DESIGN §4 tables, asserted with ±0.15 tolerance)

`web/src/styles/tokens.test.ts` parses `tokens.css` and computes WCAG 2.x contrast; `test/theme/tokens_test.dart` does the same over `tokens.dart` (proves the generator kept them equal).

| Pair (Auditorium) | Expected | Pair (Matinee) | Expected |
|---|---|---|---|
| `--ink` / `--bg` | 16.8 | `--ink` / `--bg` | 12.8 |
| `--ink-muted` / `--bg` | 7.5 | `--ink-muted` / `--bg` | 6.1 |
| `--ink-faint` / `--surface-2` | 4.2 (→ only ≥ 18 px there) | `--ink-faint` / `--surface-2` | 4.7 |
| | | `--ink-faint` / `--bg` | 5.9 |
| `--accent` / `--bg` | 13.0 | `--accent` / `--bg` | 6.1 |
| `--accent-ink` / `--accent` | 12.0 | `--accent-ink` / `--accent` | 6.9 |
| `--accent-2-lit` / `--bg` | 5.3 | `--accent-2` / `--bg` | 6.0 |
| `--success` / `--bg` | 10.8 | `--success` / `--bg` | 5.8 |
| `--warning` / `--bg` | 9.7 | `--danger` / `--bg` | 5.9 |
| `--danger` / `--surface-2` | 4.1 (→ only ≥ 18 px) | `--focus` / `--bg` | 6.2 |
| `--focus` / `--bg` | 14.7 | | |

Matinee's `--ink-muted` (6.11 · 5.56 · 4.92 on `--bg` · `--surface` · `--surface-2`) and `--ink-faint` (5.86 · 5.34 · 4.72) sit deliberately close: on the cream ground any third tier light enough to be *seen* as a third tier drops under AA, so Matinee expresses tertiary text by size and tracking instead (DESIGN §4.2). Assert both rows — a commit that lightens `--ink-faint` to open the gap must fail here, not in review.

Lint-style assertions in the same file: `--accent-2` never appears as a `color:` value in any Auditorium stylesheet (crimson is non-text on dark); `--picture-bg` is used only on the video container; every `font-family` resolves to Big Shoulders / Geist / Geist Mono / Noto Sans (no Fraunces, no Bebas — the portfolio rule).

---

## 3. Engine test cases (pure logic — Dart and TypeScript)

Format is Given / When / Then. Cases marked **‡** exist in **both** languages against the same golden table in §2; `scripts/check-parity.mjs` compares the `test('…')` names found in `test/engine/*_test.dart` and `web/src/engine/*.test.ts` and fails CI when one side has a case the other lacks, so a rule can never drift between the native and Lite tiers.

### 3.1 moviehash — `hash.dart` ‡ `osHash.ts`

| # | Given | When | Then |
|---|---|---|---|
| H1 ‡ | The official `breakdance.avi` (12 909 756 B) fetched by `make-fixtures.sh` | hash it | `8e245d9679d31e12` (§2.1 V1). If the download failed the test is `skip`ped with a printed warning — never silently passed |
| H2 ‡ | 131 072 B of `0x00` | hash it | `0000000000020000`; exactly 128 KiB is **accepted** |
| H3 ‡ | 131 072 B of `0xFF` | hash it | `000000000001c000` — proves the sum wraps mod 2⁶⁴ instead of throwing or going negative |
| H4 ‡ | 200 000 B of `0x00` | hash it | `0000000000030d40`; the last chunk starts at `size − 65 536`, i.e. it is not chunk-aligned |
| H5 ‡ | 131 071 B | hash it | Dart throws `FileTooSmall`; TS rejects with `code: 'FILE_TOO_SMALL'`. Neither surfaces a stack trace to the UI |
| H6 | Any fixture in `test/fixtures/media/` | hash it | equals `test/fixtures/hashes.json` (regression lock on the generator) |
| H7 ‡ | A stub source reporting `size = 4 294 967 296` (2³²) with two all-zero 64 KiB chunks | hash it | `0000000100000000` (§2.1 V7). Catches 32-bit truncation of `size − 65 536` and a `Number` leak in the TS path — the bug the spec's own `dummy.rar` vector (4 295 033 890 B → `61f7751fc2a72bfb`) exists to catch, without the 4 GB download |
| H7 | A 4 GiB sparse file (Dart only, made with `RandomAccessFile.truncate`) | hash it | completes in < 100 ms and reads exactly 131 072 B — asserted with a counting `RandomAccessFile` spy. Guards against anyone "optimising" the reader into a whole-file stream |
| H8 | A file deleted between `open()` and the second `read` | hash it | the error is wrapped as `HashUnavailable`, Threading skips to filename search, and the leader does **not** stall (DESIGN §9.2 has no "hash error" state) |
| H9 ‡ | The Dart result and the TS result for the same fixture bytes | compare | identical strings — the parity test reads `hashes.json` from both suites |
| H10 | A hash whose top bit is set (8 B of `0xFF` at offset 0 plus padding) | format it | 16 lowercase hex chars, no leading `−`, no `0x` — `toUnsigned(64)` in Dart, `& 0xffff_ffff_ffff_ffffn` + `padStart(16,'0')` in TS |

### 3.2 Filename grammar — `filename.dart` ‡ `filename.ts`

| # | Given | When | Then |
|---|---|---|---|
| F1 ‡ | Each row of the §2.3 table | parse | every listed field matches exactly; unlisted fields are `null`, never `''` |
| F2 ‡ | `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv` | parse | title has no dots, the year is the *last* 19xx/20xx before a quality token, `group == 'AMIABLE'` |
| F3 ‡ | `Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-TERMINAL.mkv` | parse | `title == 'Blade Runner 2049'`, `year == 2017` — a year inside the title is not stolen by the year rule |
| F4 ‡ | `movie.mkv` | parse | `confidence == 'low'`; Threading then sends `query=<raw filename>` and lets the server's guessit decide (§3.4 O6) |
| F5 ‡ | `[SubsPlease] Frieren - 12 (1080p) [ABCD1234].mkv` | parse | `title == 'Frieren'`, `episode == 12`, `group == 'SubsPlease'`, the trailing CRC bracket discarded |
| F6 ‡ | `The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.en.srt` | offer to the picker filter | rejected as "not a video" *before* parsing — a sidecar must never be openable as a film |
| F7 ‡ | A name whose last dash segment is a codec (`…-x265`) | parse | `group == null`, `codec == 'x265'` — the "token after the last dash unless it is a codec" rule |
| F8 | A path, not a name (`D:\Films\The Third Man (1949)\video.mkv`) | parse | only the basename is parsed; when the basename is `confidence: 'low'` the **parent directory** name is parsed as a second attempt and used when it scores higher |

### 3.3 Candidate scoring — `scoring.dart` ‡ `scoring.ts`

| # | Given | When | Then |
|---|---|---|---|
| S1 ‡ | `candidates-third-man.json` + the parsed release + container fps 23.976, HI *not* preferred | rank | order `A, D, C, B, E`, exactly the "Expected rank" column of §2.4 |
| S2 ‡ | same, HI preferred | rank | HI candidates gain +30 instead of −30; the documented order for that column holds |
| S3 ‡ | Candidate E (`machine_translated: true`) | rank | present in the list, `autoPick == false`, never rank 1 even with 99 999 downloads |
| S4 ‡ | Two candidates identical except `download_count` | rank | higher count wins; ties break on `download_count` then `file_id` so the order is stable across runs |
| S5 ‡ | A candidate with `fps == null` | rank | the fps term contributes `0`, not `−40` — unknown is not wrong |
| S6 ‡ | A mixed list containing `provider: 'subdl'` entries | rank | Subdl entries always score with `moviehash_match: false`; they may still outrank OpenSubtitles rows on release-group match |
| S7 ‡ | A list containing `language: 'fr'` while preferences are `['en','hi']` | rank | French is filtered **before** scoring; no French row is returned (the language filter is not a penalty) |
| S8 ‡ | An empty `data[]` | rank | returns `[]` and `autoPick == null`; the caller shows Threading *Stalled*, not an exception |
| S9 | The weight constants | read from code | exported and asserted against the literal numbers in §2.4, so changing a weight forces a deliberate doc edit in the same commit |

### 3.4 OpenSubtitles client — `opensubtitles.dart` ‡ `opensubtitles.ts`

Native calls the API directly with the `--dart-define`d consumer key; Lite calls the Worker. The client is written once per language against an injected transport (`MockClient` / a `fetch` stub), so both paths share these cases.

| # | Given | When | Then |
|---|---|---|---|
| O1 ‡ | hash `8e245d9679d31e12`, languages `en` | build the search request | the query string is **alphabetically sorted** (`languages=en&moviehash=…&moviehash_match=include&order_by=download_count`) — RESEARCH §5.4 pt 6: unsorted params earn a 301 to the canonical URL and the redirect *drops* `moviehash_match` |
| O2 ‡ | a 301 with a `Location` header anyway | follow | at most **one** redirect is followed and the params we care about are re-asserted; a second redirect is an error |
| O3 | native transport | any request | headers carry `Api-Key`, `User-Agent: Marquee vX.Y.Z`, `Accept: application/json`; the test asserts the key equals the `--dart-define` value and never appears in any log line |
| O4 ‡ | Lite transport | any request | **no** `Api-Key` header is set client-side (the Worker injects it); `Authorization` is forwarded when a JWT exists |
| O5 ‡ | `search-hash-hit.json` | parse | three candidates; A has `moviehash_match == true`; `feature_details.imdb_id == 41959`, `tmdb_id == 1092` |
| O6 ‡ | filename confidence `low` | build the by-name search | `query=<raw filename>`, **not** `query=<title>` (F4) |
| O7 ‡ | HTTP 401 on a search | handle | the JWT is dropped from storage, the request is retried **once** anonymously, and the Ticket Office row reads "Ticket expired — sign in again" in `--warning` — never a red banner (DESIGN §9.5) |
| O8 ‡ | HTTP 406 on `/download` | handle | `QuotaExhausted` with `remaining: 0`; the strip goes to `exhausted` (§2.6) and **no** retry is attempted |
| O9 ‡ | HTTP 429 with `Retry-After: 2` | handle | one retry after 2 s of *fake* clock (the test must not sleep), the sentence "OpenSubtitles asked us to wait 2 s" is announced once, the leader stalls on "2" |
| O10 ‡ | HTTP 429 **without** `Retry-After` | handle | falls back to `X-RateLimit-Reset`, then to 1 s / 2 s / 4 s backoff capped at 3 attempts |
| O11 ‡ | HTTP 410 fetching the `link` from `download-ok.json` | handle | one fresh `POST /download`; the ticket count shown is the `remaining` from the **retry** response, never a locally decremented number |
| O12 ‡ | `login-ok.json` | parse | `allowed_downloads == 20` becomes the strip total; the app never hard-codes 10 or 20 (§2.6) |
| O13 ‡ | `login-vip.json` | parse | subsequent requests use `base_url: vip-api.opensubtitles.com`; the test asserts the host of the next request changed |
| O14 ‡ | a successful login | inspect storage | only the JWT is persisted; a test that greps the serialised store for the password string fails if it is found |
| O15 ‡ | the same `moviehash+lang` searched twice inside 24 h | second call | served from cache, transport called **once** (GOAL §5.3) |
| O16 ‡ | a network error (DNS / offline) | handle | `Offline` — distinct from `ServerError`; Threading shows *Offline* with "Play without subtitles" lit (DESIGN §9.2) |

### 3.5 Subdl fallback — `subdl.dart` ‡ `subdl.ts`

| # | Given | When | Then |
|---|---|---|---|
| D1 ‡ | the user's Subdl key is set and OpenSubtitles returned `total_count: 0` | search | `GET api.subdl.com/api/v1/subtitles?api_key=…&file_name=…&languages=EN` — Subdl has no hash parameter at all (RESEARCH §3) |
| D2 ‡ | `subdl-search.json` | map | candidates carry `provider: 'subdl'`, `moviehash_match: false`, and render in the "Also from Subdl" section (DESIGN §9.2) |
| D3 ‡ | a Subdl download URL | build the request | it goes to `dl.subdl.com` **without** the `api_key` — a free key carries search quota only; downloads must be anonymous (RESEARCH §3) |
| D4 ‡ | `subdl-zip.bin` | extract | the single `.srt` inside is written beside the video; a zip with 2+ subtitle entries picks the best language match; a zip with none raises `NoSubtitleInArchive` |
| D5 ‡ | no Subdl key configured, OpenSubtitles quota exhausted | render | the Subdl slot reads "add a free key" rather than showing an error, and no request is made |

### 3.6 Tickets and quota — `tickets.dart` ‡ `tickets.ts`

| # | Given | When | Then |
|---|---|---|---|
| T1 ‡ | each row of §2.6 | render the model | strip text, colour token, state name and `aria-label` match the table exactly with the clock fixed at 2026-09-06T15:44Z |
| T2 ‡ | `remaining: 0` | ask for a download | the quota guard refuses **before** any HTTP call (GOAL §5.3) and returns `NoTicket`; the transport spy records zero requests |
| T3 ‡ | a successful download | observe the model | `pendingTear == true` first, count decrements **after** `tearComplete()` — so the widget can play `ticket-tear` before the number changes (DESIGN §7 #9) |
| T4 ‡ | signed out | render | `ANONYMOUS · 5 PER DAY PER IP` in `--ink-muted`; the sign-in nudge appears once per session, not once per open |
| T5 ‡ | `reset_time_utc` in the past (clock skew) | render | clamps to `RESETS 00:00 UTC`; never prints a negative duration |
| T6 ‡ | two opens of the same `moviehash+lang` | second open | cache hit, **0** tickets spent, strip unchanged (GOAL §5.3) |

### 3.7 Folio timecodes — `timecode.dart` ‡ `timecode.ts`

| # | Given | When | Then |
|---|---|---|---|
| C1 ‡ | each row of §2.7 | format | exact string, U+2212 minus, `HH:MM:SS`, no 24 h wrap |
| C2 ‡ | position 4364.4 / duration 9663 | format | `01:12:44 · −01:28:19`; floor + ceil sum to the duration in every row |
| C3 ‡ | duration `null` | format | `00:00:45 · —` (em dash), never `NaN` or `--:--:--` |
| C4 ‡ | speed 2.0 and an A–B loop set | format | suffixes append in the order `2.0×` then `A–B` |
| C5 ‡ | a 62-character title on desktop | build the auditorium folio | uppercased and condensed to 40 chars with a single `…`; the ellipsis never lands mid-surrogate-pair |

### 3.8 Sync rule — `sync_rule.dart` ‡ `syncRule.ts`

| # | Given | When | Then |
|---|---|---|---|
| Y1 ‡ | each row of §2.8 | apply | value and folio string match; `+0.376` rounds to `+0.40` (nearest, not floor) |
| Y2 ‡ | value `+0.35` | write to the player | native calls `setProperty('sub-delay', '0.35')` — a **string**, mpv's property API is string-typed; Lite shifts every VTT cue by +350 ms |
| Y3 ‡ | drag beyond the ends | apply | clamped to ±2.00, no wrap, and no haptic past the clamp |
| Y4 ‡ | a remembered offset for moviehash `8e24…` | reopen the same file | the offset is restored and the Lobby card shows a `±0.35` chip |
| Y5 ‡ | a different moviehash | open | offset is 0.00 — offsets key on the hash, never the path, so a renamed file keeps its sync |
| Y6 ‡ | long-press reset / `Shift+J+K` | apply | value 0.00, readout `SYNC +0.00`, folio suffix **removed** rather than printed as `SUB +0.00` |
| Y7 ‡ | "save beside file" with "bake the offset in" enabled | rewrite the SRT | every cue shifts, starts clamp at `00:00:00.000`, and the *runtime* delay resets to 0 so the offset is never applied twice |

### 3.9 Chapter and seek detents — `detents.dart`

| # | Given | When | Then |
|---|---|---|---|
| E1 | the §2.8 fixture (800 px, 9663 s, chapters 0/1800/4200/7200) | release at each px in the table | snap / no-snap matches; the run repeats at 360 px and 1920 px and the capture radius stays **6 px** (not 6 seconds) |
| E2 | mpv reports an empty `chapter-list` | build detents | detents every 300 s plus one at 0 and one at the duration |
| E3 | FINE mode (drag up off the strip) | drag 80 px | 1/8 speed → 10 px of gate travel → 120.8 s; detents disabled, no selection haptic |
| E4 | three detents crossed inside one frame | drag | exactly **3** `selectionClick`s — not 1, not 30 |
| E5 | first-run flag unset | open the Auditorium | the gate nudges 12 px right and back once, then sets the flag; a second open does not nudge |

### 3.10 Threading state machine — `threading.dart` ‡ `threading.ts`

The leader *is* the state machine; these cases are what make the loading indicator honest (GOAL §5.4).

| # | Given | When | Then |
|---|---|---|---|
| L1 ‡ | a sidecar `The Third Man.en.srt` already beside the file | open | the sidecar is attached, **no** network call is made, the leader runs 3 → 2 → 1 → flash in under 200 ms, and the MATCH bulb stays dark (a sidecar is not a hash match) |
| L2 ‡ | a 1.42 GB MKV, hash hit, download OK | open | phases in order `hashing → searching → downloading → attached`; the hash prints during "3", `moviehash_match` during "2", the saved path during "1" |
| L3 ‡ | search resolves after 4 s | observe | "2" does **not** advance to "1" before the promise resolves; the sweep angle is a function of elapsed time within the phase and freezes when the phase does |
| L4 ‡ | search rejects (offline) | observe | the sweep **stalls at its current angle** — it does not reset to 0 or jump to 360 — and the fallback rows appear within 500 ms (GOAL §5.4) |
| L5 ‡ | a hash hit where every candidate is `machine_translated` | observe | no auto-pick; the list is shown and the leader waits for input rather than downloading |
| L6 ‡ | a file < 128 KiB | open | the hash phase is skipped silently, "3" still sweeps for the file read, the search is by filename, and **no** error state is shown (DESIGN §9.2) |
| L7 ‡ | quota exhausted (406) during "1" | observe | the leader stalls on "1", the strip turns crimson with its one sentence, and "Skip subtitles" / "Use the Subdl slot" are offered |
| L8 ‡ | the user presses Esc / swipes down mid-phase | observe | the in-flight request is cancelled (the transport spy sees an abort), no ticket is spent, playback starts with no subtitle |
| L9 ‡ | `moviehash_match == true` | observe | exactly one 2-pop and one `mediumImpact`, and the MATCH bulb transition fires **after** the 2-pop (DESIGN §7 #12) |
| L10 ‡ | the whole chain succeeds | count announcements | four announcements — "Reading file", "Searching subtitles", "Downloading English subtitles", "Subtitles attached, in sync" — and **not** one per sweep frame (DESIGN §13) |

### 3.11 SRT ↔ WebVTT — `srt.dart` ‡ `srt2vtt.ts`

| # | Given | When | Then |
|---|---|---|---|
| V1 ‡ | `sample-crlf-bom.srt` | convert | byte-identical to the §2.5 golden: BOM stripped, CRLF → LF, `,` → `.`, cues sorted and renumbered |
| V2 ‡ | a cue with `<i>`, `<b>`, `<u>` | convert | tags kept; `<font color="#ff0000">` stripped to its text |
| V3 ‡ | a cue with `{\an8}` | convert | becomes a `line:0` cue setting; the tag is never printed as literal text |
| V4 ‡ | overlapping cues | convert | preserved as-is (WebVTT permits overlap; re-timing them would desync dialogue) |
| V5 ‡ | delay `+0.35` | shift | every cue moves +350 ms; `−5.0` applied to a cue starting at 1.0 s clamps the start to `00:00:00.000` **and keeps the original duration** |
| V6 ‡ | a Windows-1252 file with a mis-encoded `é` | decode | decoded via the declared charset if present, else UTF-8, else Windows-1252 as a last resort; the golden contains no U+FFFD |
| V7 ‡ | a cue index out of order and no trailing newline at EOF | convert | parsed without loss; the last cue survives |

### 3.12 Bias light — `bias_light.dart`

| # | Given | When | Then |
|---|---|---|---|
| B1 | `frame-bias.png` (§2.2) | quantize | stop 0 within ΔE2000 < 5 of `#FFC56E`, stop 1 of `#A3252F`, stop 2 of `#5FD48A`; stops 3–4 have lower L\* than stop 2 |
| B2 | an all-black 64×36 frame (letterbox) | quantize | returns `null`; the widget keeps `--focus` at 6 % alpha (DESIGN §4.3) |
| B3 | 95 % black + 5 % tungsten | quantize | pixels with L\* < 8 are dropped first, so stop 0 is tungsten, not black |
| B4 | two consecutive samples | drive the widget with a fake ticker | `bias-lerp` runs 600 ms; with `disableAnimations` it runs 1200 ms and **still changes colour** (it is colour, not motion — DESIGN §7) |
| B5 | Android with bias light off (the default until measured, DESIGN §14) | play | `player.screenshot` is never called; the spy asserts zero invocations |

---

## 4. Data layer — drift, caches and migrations (`test/db/`)

All run on `NativeDatabase.memory()`; migrations use `drift_dev` schema snapshots in `test/db/schemas/`.

| # | Given | When | Then |
|---|---|---|---|
| DB1 | an empty DB | insert a library row for `D:\Films\The Third Man (1949).mkv` | `moviehash` is the lookup key, `path` is a unique index; the same film at a new path **updates** the row instead of duplicating it |
| DB2 | a subtitle cached for `moviehash+lang` | look it up | returns `{file_id, path}`; if the file is missing on disk the row is invalidated and the next open re-downloads — a cached path that no longer exists must never report a hit |
| DB3 | a resume position of 4364.4 s in a 9663 s film | store, reopen | resumes at 4364.4 s; a position within 30 s of the **end** stores as "finished" (position 0) so the sprocket track fills instead of resuming on the credits |
| DB4 | a per-hash sync offset | store twice | one row per `moviehash` (not per path); rewriting is idempotent |
| DB5 | a TMDB cache row written at T | read at T + 6 months + 1 day | expired and deleted (TMDB terms forbid caching > 6 months — RESEARCH §3). Driven by `withClock`, never by sleeping |
| DB6 | a search-result cache row | read at T + 24 h + 1 s | expired. The **download** cache has no expiry — a downloaded `.srt` stays valid forever |
| DB7 | schema v1 with rows | migrate to vN | `verifySelfIntegrity()` passes and every existing row survives; a migration that would drop data fails the test |
| DB8 | 5 000 library rows | query one Lobby rail page | under 16 ms (one frame) with the rail's `LIMIT/OFFSET` and index; asserted with a 3× margin so it is not flaky |
| DB9 | the DB file | grep the serialised bytes | contains no password, no `Api-Key` and no JWT — the JWT lives in `flutter_secure_storage`, not drift |
| DB10 | `app_state` (the eighth table — ARCHITECTURE §4) | write `settings`, `window_bounds` `{x:120,y:80,w:1440,h:900,maximized:false}` and `seen_gate_nudge: true`, close the DB, reopen it | all three read back byte-identical, proving DEPLOYMENT §9 / W-I5 (“window size and position persist between runs”) and PLAN 3.4 (“the film-gate nudge fires **once** and is remembered”) have somewhere to live. A second simulated restart must **not** re-fire the nudge |
| DB11 | a full export written by §5.5 | import it into an empty DB | the three `app_state` keys come back with everything else — a restore that loses the window geometry or re-arms the nudge fails |

---

## 5. Widget and golden tests (`test/widgets/`, `test/goldens/`)

Goldens are generated **on Linux only** (`ubuntu-24.04`) with fonts loaded by `test/flutter_test_config.dart` and a 0.5 % comparator tolerance; Windows runs the same widget tests with `--exclude-tags golden`. Every component that appears in both rooms gets an Auditorium **and** a Matinee golden, plus a `disableAnimations` variant for the animated ones.

| # | Component | Given | Then |
|---|---|---|---|
| W1 | Marquee sign | title `THE THIRD MAN`, 1949, night | matches `marquee_now_showing_night.png`; bulbs lit, crimson trim exactly 1 px at 1× DPR; the flicker RNG is `Random(8)` so the frame is deterministic |
| W2 | Marquee sign | Matinee, day | bulbs **off**, letters painted `--ink`, no halo (DESIGN §4.2) |
| W3 | Marquee sign | a 30-letter title | `bulb-warmup` stagger caps at 24 letters / 1.44 s; golden taken at t = 1.5 s |
| W4 | Leader | phase "2", sweep at 180° | matches `leader_2_half.png`; the hash line reads `8e245d9679d31e12 · 1.42 GB · 23.976 fps` in Geist Mono |
| W5 | Leader | phase "2", **stalled** | the sweep angle is frozen and the fallback rows lay out beneath without the numeral moving |
| W6 | Leader | `disableAnimations` | a 240 ms opacity crossfade, still stalls honestly, no conic sweep |
| W7 | Ticket strip | `remaining: 7 / 10` | `7 OF 10 TONIGHT · RESETS 00:00 UTC`, `--ink`, ten perforations with three torn |
| W8 | Ticket strip | `remaining: 2` | crimson strip, text in `--accent-2-lit`, sign-in nudge present |
| W9 | Ticket strip | `remaining: 0` | `exhausted` golden plus the Subdl slot row |
| W10 | Film gate | 800 × 56, position 4364.4 s, buffered to 5200 s, 4 chapters | matches `gate_idle.png`; sprocket holes 3 × 4 px; the gate window is 16:9 with a 1 px `--accent` edge |
| W11 | Film gate | dragging, FINE mode | `FINE` label in mono, detents hidden |
| W12 | Sync rule | expanded at `+0.35` | ruler golden; the caret is fixed and the **ruler** has moved — a golden showing a moved caret is a regression |
| W13 | Candidate row | MATCH / by-name / HI / Subdl / downloading / attached | six goldens; `CHECK SYNC` in `--warning`, `synced ✓` in `--success` |
| W14 | Booth sheet | 70 % height over a paused frame | `--booth-glass` + 24 px blur + 1 px `--border` top edge, with the frame still visible below |
| W15 | Ticket Office | signed in, all toggles | full-screen golden in both palettes; the attribution block (OpenSubtitles credit, TMDB logo + notice, LGPL links, OFL fonts) is present and typeset, not hidden behind a link (DESIGN §9.5) |
| W16 | Lobby | 5 cards, night sky band, `--house: 1` | matches `lobby_night.png` and the corresponding frame of `design/preview.html` |
| W17 | Auditorium | controls shown, wall glow from B1's stops | matches `auditorium_controls.png`; controls sit on `--bg`, never on the picture (DESIGN §13) |
| W18 | Auditorium | 2400 ms idle elapsed | all chrome gone, folio at 40 % opacity |
| W19 | "Undecodable print" error | `corrupt.mkv` | one sentence in `--ink` on `--bg` with actions beneath, and **no** red fill — asserted by scanning the rendered image for pixels within ΔE 10 of `--danger` covering more than 2 % of the frame |
| W20 | Every screen | `MediaQuery.disableAnimations = true` | no beam animation, no dust, sheets fade; a ticker counter asserts zero repeating tickers are left running |

Behavioural widget tests (not goldens) in the same folder: the gate exposes slider semantics with a timecode value, toggle bulbs report `role: switch`, the ticket strip's semantic label matches §2.6, and tapping a candidate row overrides the auto-pick and cancels the in-flight download.

---

## 6. Native integration tests (`integration_test/`, real libmpv)

Run with `flutter test integration_test -d windows` on `windows-latest` (the `test` job of `release.yml`, plus a weekly cron). They use the committed fixtures from §2.2 — never a network stream — and a fake OpenSubtitles transport, so CI never spends a ticket.

| # | File | Given | When | Then |
|---|---|---|---|---|
| I1 | `player_test` | `testsrc-10s-h264-aac.mkv` | `player.open` | a first frame is presented within **1.5 s** (GOAL §5.5) and `player.state.duration ≈ 10 s ± 40 ms` |
| I2 | `player_test` | `testsrc-10s-hevc-ac3.mkv` | open | video **and** audio decode; the audio track reports `ac3`. This is the case the web tier cannot do and the whole reason libmpv exists |
| I3 | `player_test` | `testsrc-10s-h264.avi` | open | plays — proves "any container" |
| I4 | `player_test` | `corrupt.mkv` | open | the *Undecodable print* state appears within 2 s, the app does not hang, and the next `open()` succeeds |
| I5 | `subtitles_test` | `sample.srt` beside the video | `setSubtitleTrack(SubtitleTrack.uri(...))` | the track is active; a screenshot at t = 2 s has non-background pixels in the bottom third |
| I6 | `subtitles_test` | `sample.ass` with `\pos` and `\an8` | attach | the `\an8` cue renders in the **top** third and the `\pos` cue at its coordinates — the libass proof. Compared with `test/goldens/ass_an8_windows.png` at 2 % tolerance (libass output is not bit-stable across builds) |
| I7 | `subtitles_test` | the MKV's **embedded** SRT and ASS tracks | list tracks | both appear with titles; switching takes effect within 2 frames |
| I8 | `subtitles_test` | `libass: true` with the bundled font | read mpv properties | `sub-ass=yes`, `config=yes`, `sub-font-provider=none`, `sub-fonts-dir` pointing at the cache copy, and `vo == gpu`. This test fails loudly if anyone ever sets `vo=mediacodec_embed` while libass is on (RESEARCH §8) |
| I9 | `seek_test` | chapters at 0 / 3 / 6 s | drag the gate to 3.1 s and release | snaps to 3.000 s, `position` lands within 40 ms, one selection tick |
| I10 | `seek_test` | position 5 s | `←` then `Shift+→` | 0 s then 30 s (clamped to duration); the folio updates in the same frame |
| I11 | `keyboard_test` | `design/cue-sheet.json` | send every listed key | every shortcut has an observable effect, and the test **fails if the JSON lists a key the app ignores or the app handles a key the JSON omits** — the cue sheet is the single source of truth (DESIGN §16) |
| I12 | `house_test` | Lobby → open → back | run | `--house` reaches 0 within 900 ms ± 60 ms, the video is disposed on the way back, and a second open leaks no `Player` (finalizer counter) |
| I13 | `house_test` | the Windows frameless window | drag the marquee title bar | the window moves (`window_manager`); Mica is active in the Lobby and **off** during playback (DESIGN §16) |
| I14 | `perf_test` | `testsrc-10s-h264-aac.mkv` | play 10 s with controls visible | Flutter timeline summary meets the budgets in §9 |
| I15 | `player_test` | a file passed as a command-line argument | launch `marquee.exe "…\x.mkv"` | it plays without passing through the Lobby |

**Android integration.** There is no Android emulator in CI and libmpv wants a real GPU, so Android `integration_test` runs only on the owner's machine (`flutter drive`) when Flutter is installed locally. The standing Android gate is therefore the manual checklist in §14, which is **not** optional.

---

## 7. Worker tests (`worker/test/`)

The Worker (`marquee-proxy`) is the only piece of Marquee that holds a secret, so its tests are as much a security suite as a functional one. They run under `@cloudflare/vitest-pool-workers` with `SELF.fetch` and `fetchMock` from `cloudflare:test`; the real API is never touched here.

### 7.1 Unit / contract-with-ourselves (`worker.test.ts`)

| # | Given | When | Then |
|---|---|---|---|
| P1 | `Origin: https://<owner>.github.io` | `OPTIONS /api/subtitles` | **204** with `Access-Control-Allow-Origin` echoing that origin, `Allow-Methods: GET,POST,OPTIONS`, `Allow-Headers: Content-Type,Authorization`, `Max-Age: 86400`, `Vary: Origin`. The Worker answers the preflight **itself** — OpenSubtitles' own preflight returns 403 (RESEARCH §5.4 pt 6), which is why the proxy exists |
| P2 | `Origin: https://evil.example` | `OPTIONS` and `GET` | 403 with **no** CORS headers at all (a 403 carrying `Allow-Origin: *` would defeat the allow-list), and a `WorkerError` JSON body `{error:'forbidden-origin', sentence:"This build isn't allowed to talk to the subtitle service."}` — assert the `error` code, not just the status, so Lite always has a sentence to print |
| P3 | `Origin: http://localhost:5173` | any request | allowed (dev), and the echoed origin is the localhost one, not the production one |
| P4 | no `Origin` header (curl, native app) | any request | 403 `{error:'forbidden-origin'}` — native builds call OpenSubtitles directly and must never route through the Worker's quota |
| P5 | `GET /api/subtitles?moviehash=…` | forward | upstream URL is `https://api.opensubtitles.com/api/v1/subtitles?...`, headers include `Api-Key: <secret>` and `User-Agent: Marquee-Web vX.Y.Z` |
| P6 | any response | inspect | the response body and headers contain **no** occurrence of the secret; the test asserts on the raw serialised response, and on the `console` output captured during the request |
| P7 | `GET /api/../../admin` or `/api/subtitles/../../x` | forward | rejected **404 `{error:'not-found', sentence:'That endpoint is not proxied.'}`** (assert the JSON code, not only the status); the path is normalised and matched against the allow-list `subtitles`, `login`, `logout`, `download`, `infos/*`, `utilities/guessit`, `tmdb/*` before any upstream call |
| P8 | `GET /health` or `/` | request | 404 `{error:'not-found'}`, not a proxy pass — only `/api/**` is proxied |
| P9 | unsorted query params | forward | re-sorted alphabetically before the upstream call, so the gateway's canonical 301 (which drops `moviehash_match`) never fires (RESEARCH §5.4 pt 6) |
| P10 | client sends `Authorization: Bearer eyJ…` | forward | header forwarded verbatim; nothing else from the client's headers is (no `Cookie`, no `X-Forwarded-*`, no client `Api-Key` — a client-supplied `Api-Key` is **stripped**, not passed through) |
| P11 | upstream 429 with `Retry-After` and `X-RateLimit-*` | forward | those headers survive to the browser so the client can back off correctly |
| P12 | upstream 406 / 401 / 410 | forward | status and JSON body pass through unchanged — the client owns the copy, the Worker owns the transport |
| P13 | a `GET` response | inspect | `Cache-Control: private, max-age=300`; `POST /api/download` and `/api/login` responses are `no-store` (a cached download link would hand one user another user's ticket) |
| P14 | `PUT` / `DELETE` / `PATCH` | request | 405 `{error:'method-not-allowed'}` |
| P15 | a 12 MB upstream body | forward | streamed (`new Response(res.body, res)`), not buffered — the test asserts the Worker never calls `arrayBuffer()` on the upstream response |
| P16 | `wrangler.toml` | parse in a test | `ALLOWED_ORIGIN` and `UPSTREAM_BASE` are `[vars]`; `OS_API_KEY` appears **only** as a secret name — a test greps the whole `worker/` tree (excluding `node_modules`) for anything that looks like a key literal and fails on a hit |
| P17 | `wrangler.toml` | grep it | it contains **no** `[[kv_namespaces]]`, `[[d1_databases]]` or `[[analytics_engine_datasets]]` block, and any `[observability]` block is `enabled = false`. Workers Logs retains request metadata server-side, which contradicts “the Worker logs nothing and stores nothing” (GOAL §9, ARCHITECTURE §9.4/§13, IMPLEMENTATION-PROMPT §2.5). P6 only greps bodies and `console`, so this is the only test that catches it |
| P18 | `GET /api/subtitle-file?link=…` | a link on `evil.example`; a non-https link; a missing `link`; a `Content-Type: image/png` upstream; a `Content-Length` over 2 MB | `403 {error:'bad-link'}`, `403 {error:'bad-link'}`, `400 {error:'bad-link'}`, `415 {error:'bad-link'}`, `413 {error:'too-large'}`. A link on `opensubtitles.com` / `*.opensubtitles.org` over https with `text/plain` is streamed back **200** with CORS and `Cache-Control: no-store` |
| P19 | `POST /api/download` and `GET /api/infos/user` with **no** `Authorization` | request | **401 `{error:'sign-in-required', sentence:'Sign in to OpenSubtitles at the ticket office to download subtitles here.'}`** and **no upstream fetch at all** — an anonymous download would spend OpenSubtitles' shared 5/day/IP pool on the Worker's own IP. With an `Authorization` header the same request forwards normally |
| P20 | 61 requests in one minute from one `cf-connecting-ip` | request | the 61st is **429 `{error:'rate-limited', retryAfterSeconds:60}`**; the counter is a Cache-API key (`caches.default`), never KV, and a different IP in the same minute is unaffected |
| P21 | `GET /api/tmdb/find/tt0041959?external_source=imdb_id` | with `TMDB_READ_TOKEN` set, and unset | set → forwarded to `https://api.themoviedb.org/3/find/…` with `Authorization: Bearer <var>` built **server-side** (a client-supplied `Authorization` is **not** forwarded on this route), `Cache-Control: private, max-age=3600`; unset → `404 {error:'not-found'}`. In both cases the token appears nowhere in the response |

### 7.2 Live contract test (`contract.test.ts`, nightly)

`describe.skipIf(!process.env.OS_API_KEY)` — it never runs on a fork PR and never blocks a merge. It runs in `contract.yml` on a nightly cron and on day 1 (§13). It performs **search-only** calls (search is unlimited; downloads are not) plus at most **one** `/download` per month behind an explicit `RUN_DOWNLOAD_PROBE=1` flag.

| # | Assertion | Why it is here |
|---|---|---|
| K1 | `GET /subtitles?moviehash=8e245d9679d31e12&languages=en` returns 200 and every field the fixtures read (`data[].attributes.{language,download_count,fps,release,hearing_impaired,moviehash_match,files[].file_id,feature_details.{imdb_id,tmdb_id,title,year}}`) is present | the fixtures in §2.9 are hand-written; this is the only thing that keeps them honest |
| K2 | the response carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` | RESEARCH could not confirm the per-second cap from any primary source; the nightly run **records the observed header values into `worker/test/observed-limits.json`** so the real limit is discovered empirically rather than guessed (§13 #1) |
| K3 | an unsorted query string still 301s to the sorted canonical URL and still drops `moviehash_match=include` | if this ever changes, O1/O2/P9 can be simplified |
| K4 | `moviehash_match=only` is either honoured or ignored — the test records which | §13 #3 |
| K5 | `GET /utilities/guessit?filename=…` returns 200 with the `guessit-ok.json` shape, or 404/403 | §13 #4; a pass lets `filename.dart` become a fallback instead of the primary parser |
| K6 | `POST /login` returns `allowed_downloads`, and the value is recorded | settles the 10-vs-20 disagreement between the two help articles (§13 #5) |
| K7 | (flagged) `POST /download` returns a `link`; the link is fetched immediately, then again after 1 h, and the second result (200 or 410) is recorded | §13 #2 — measures the link TTL nobody has documented |
| K8 | a failure of K1 opens a GitHub issue via `gh issue create` rather than failing the branch | the API is not ours; a shape change is news, not a build break |

---

## 8. Marquee Lite (web tier) tests

### 8.1 Component tests (`web/src/ui/*.test.ts`, Testing Library DOM)

| # | Given | When | Then |
|---|---|---|---|
| U1 | the Lite landing | render | the drop frame is a real `<button>`-equivalent (focusable, `Enter`/`Space` opens the picker), and the `<input type="file">` is reachable by keyboard — drag-and-drop is never the only way in |
| U2 | the capability line | stub `canPlayType`/`VideoDecoder` per §2.10 | the printed fragments match the table exactly; when `window.VideoDecoder` is undefined the line ends `· WebCodecs unavailable` and the "Try the WebCodecs path" button is absent from the DOM (not merely hidden) |
| U3 | the leader | phase changes | exactly four `aria-live="polite"` announcements (§3.10 L10); a sweep-frame counter proves no per-frame announcement |
| U4 | the candidate list | render `search-hash-hit.json` | rows are a `role="radiogroup"`; arrow keys move the selection; `Enter` picks; the auto-picked row is `aria-checked` |
| U5 | the sync rule | render at `+0.35` | `role="slider"`, `aria-valuetext="plus 0.35 seconds"`, `aria-valuemin/-max` are ±2; `ArrowRight` steps 50 ms and `Shift+ArrowRight` 500 ms |
| U6 | the No Print card | container `mkv`, codecs `hevc` + `ac-3`, missing AC-3 | one sentence naming the actual missing codec, plus the two documented actions; the DOM contains no element with a `--danger` background |
| U7 | the ticket strip | §2.6 rows | text, class and `aria-label` match |
| U8 | the whole Lite app | render with `prefers-reduced-motion: reduce` | no `requestAnimationFrame` loop is scheduled for the beam or dust (asserted by stubbing rAF and counting) |

### 8.2 End-to-end (`web/e2e/*.spec.ts`, Playwright)

Projects: `chrome` (branded Chrome, so H.264/AAC are present), `firefox`, `pixel-7` (branded Chrome, touch, 412 × 915). The Worker is always mocked with `page.route('**/api/**')` from `web/e2e/fixtures/`; the clock is installed at 2026-09-06T21:14+05:30.

| # | Spec | Given | When | Then |
|---|---|---|---|---|
| X1 | `lite.spec` | a cold landing | load | the capability line matches §2.10's per-browser certainties; no console error; no network request leaves the origin except the mocked `/api/**` |
| X2 | `playback.spec` | `testsrc-10s-h264-aac.mp4` via `setInputFiles` | drop | `<video>` reaches `readyState >= 3` and `currentTime` advances past 1 s within 3 s (GOAL §5.7) |
| X3 | `playback.spec` | `testsrc-10s-vp9-opus.webm` in `firefox` | drop | plays — the Firefox codec sanity check |
| X4 | `playback.spec` | `testsrc-10s-hevc-ac3.mkv` | drop | the **No Print** card appears within **1 s** naming container and codecs (GOAL §5.7); the page never shows a silent black rectangle |
| X5 | `threading.spec` | a mocked hash hit | drop | leader phases 3 → 2 → 1 in order; the hash text `8e245d9679d31e12` is visible during "3"; MATCH bulb lights; a `<track>` is attached and `textTracks[0].mode === 'showing'` |
| X6 | `threading.spec` | the Worker route returns 429 with `Retry-After: 2` | drop | the leader stalls on "2", the sentence appears once, and after the fake 2 s it retries exactly once |
| X7 | `threading.spec` | the Worker route returns 406 | drop | the crimson exhausted strip plus the Subdl slot; **no** further `/api/download` request is made |
| X8 | `subtitles.spec` | `sample.ass` | attach | JASSUB mounts, its canvas overlays the video, and the `\an8` cue is rendered in the top third (pixel probe of the canvas, 2 % tolerance) |
| X9 | `subtitles.spec` | `sample-crlf-bom.srt` | attach | cue text and timings match the §2.5 golden as read back from `video.textTracks[0].cues` |
| X10 | `keyboard.spec` | the player | tab through | every control is reachable, the focus ring is visible (screenshot probe of the focused element's bounding box), and `Esc` goes exactly one lighting state up |
| X11 | `offline.spec` | the PWA installed and a previously played file | `context.setOffline(true)`, reload | the shell loads from the service worker, the previously fetched subtitle is served from IndexedDB, and Threading shows the *Offline* state with "Play without subtitles" lit — never a browser error page |
| X12 | `offline.spec` | a fresh visit while offline | load | the install prompt path is not broken and the app shell still renders (precache) |
| X13 | `a11y.spec` | landing, threading, player, No Print, ticket office | `@axe-core/playwright` | zero violations at `wcag2a`/`wcag2aa`; colour-contrast violations are **not** suppressed |
| X14 | `visual/lite.spec` | landing, Threading mid-sweep (clock frozen), Auditorium with controls, No Print | `toHaveScreenshot` | matches the checked-in baselines, which were taken from `design/preview.html` (DESIGN §16) |
| X15 | `visual/tokens.spec` | the rendered app | read computed styles | `--bg`, `--ink`, `--accent` etc. resolve to the exact hex values in `tokens.css`; the picture container is the only element using `--picture-bg`; no element uses `--accent-2` as a `color` in the Auditorium (§2.12) |
| X16 | `perf/lite.spec` | landing | Lighthouse CI (`web/lighthouserc.json`) | budgets in §9 |

### 8.3 PWA

`X11`/`X12` plus a manual check: the manifest's `start_url` and `scope` are `/marquee/` (the Pages sub-path), the service worker is registered from `import.meta.env.BASE_URL + 'sw.js'`, and the installed app opens at the Lite landing (DEPLOYMENT §6). GitHub Pages cannot serve COOP/COEP headers, so **JASSUB runs in its single-threaded fallback** on the deployed site; the test asserts the app detects this and does not attempt `SharedArrayBuffer` (the threaded path is only reachable via the Workers-static-assets escape hatch, DECISIONS §D2).

---

## 9. Performance tests and budgets

Budgets come straight from GOAL §5. A budget miss fails the job; the numbers below are the *gates*, not aspirations. Native numbers are measured on `windows-latest` for CI trend-tracking and re-measured by hand on the owner's PC and phone before a tag (§14, §15), because a shared runner's GPU is not the owner's.

| # | Metric | Budget | Measured by |
|---|---|---|---|
| N1 | moviehash of a 1.4 GB file | ≤ 60 ms (target 40 ms, GOAL §1) | `integration_test/perf_test.dart`, median of 20 runs |
| N2 | `player.open` → first frame, local 1080p | **< 1.5 s** | `perf_test`, `windows-latest` |
| N3 | Cold start → Lobby interactive | Windows **< 1.5 s**; Android **< 2.5 s** | `perf_test` (Windows, CI); §14 stopwatch (Android) |
| N4 | Drop → subtitles attached and first frame, hash hit, 10 Mbit | **< 3 s** end-to-end | §15 manual, with the network throttled; CI asserts the non-network part is < 1.8 s |
| N5 | Failure → fallback rows visible | **< 500 ms** | `threading` unit test with a fake clock (L4) |
| N6 | Frame time, controls + gate drag + sync rule | 60 fps: **0 frames > 16.7 ms at p90**, worst frame < 32 ms | `perf_test` timeline summary; `--profile` build |
| N7 | Beam shader cost | **≤ 2 ms/frame** at DPR cap (1.5 desktop / 1.0 Android) | `perf_test` with the shader isolated in a bare `CustomPaint` harness |
| N8 | Bias-light sample + quantize | ≤ 8 ms per sample, off the raster thread | `perf_test`; if it exceeds this the cadence drops to 1000 ms on desktop too |
| N9 | Windows release zip | ≤ 60 MB | `release.yml` size gate |
| N10 | `marquee-<version>-arm64-v8a.apk` (built as `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, renamed before upload) | ≤ 55 MB (CI gate; target 45) | `release.yml` size gate (libmpv + ffmpeg is ~30–40 MB per ABI, RESEARCH §5.1 — a jump means a flavour or ABI mistake) |
| N11 | Universal APK is **not** produced | 0 files | `release.yml` asserts only split-per-ABI artifacts exist |
| N12 | Lite JS bundle, gzipped, without JASSUB/WebCodecs chunks | ≤ 120 KB | `web/e2e/perf` + a `size-limit` check in `ci.yml` |
| N13 | JASSUB and the WebCodecs path | lazy chunks, **0 bytes** on the landing page | Playwright network assertion on X1 |
| N14 | Lighthouse (mobile, throttled) on the Lite landing | Performance ≥ 90, Accessibility **= 100**, Best Practices ≥ 95; LCP ≤ 2.0 s, CLS ≤ 0.02, TBT ≤ 150 ms | `lighthouserc.json` in `ci.yml` |
| N15 | Lite: drop → playing with subtitles, MP4/H.264 | **< 3 s** | X2 + X5 timing assertions |
| N16 | Lite: unplayable file → No Print card | **< 1 s** | X4 |
| N17 | Tag → both artifacts on a Release | **< 25 min** wall clock | `release.yml` job summary; the workflow sets `timeout-minutes: 25` per build job so an overrun fails |
| N18 | Memory after 30 opens/closes of the same file | no monotonic growth (< 10 % over the first-open baseline) | `perf_test` loop with `ProcessInfo.currentRss` |

---

## 10. Accessibility tests

Automated on every PR; the manual passes are release gates (§14, §15).

| # | Check | How |
|---|---|---|
| A1 | Contrast for every text token on every allowed surface | `web/src/styles/tokens.test.ts` and `test/theme/tokens_test.dart` compute WCAG 2.x ratios and compare with the §2.12 table (±0.15). Both palettes. A new token without a row in the table fails the test |
| A2 | `--ink-faint` and `--danger` are only used at ≥ 18 px on `--surface-2` | a stylesheet lint in `tokens.test.ts` plus a Flutter widget test that walks the tree and asserts `fontSize >= 18` wherever those colours are the text colour |
| A3 | `--accent-2` is never a text colour in the Auditorium | §2.12 lint |
| A4 | No control is drawn over the picture | a widget test asserts every interactive element's ancestor is the wall (`--bg`), not the video container (DESIGN §13) |
| A5 | Axe on all five Lite screens | X13, `wcag2a` + `wcag2aa`, zero violations |
| A6 | Flutter guideline suite | `meetsGuideline(textContrastGuideline)`, `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` on the Lobby, Threading, Auditorium, Booth and Ticket Office |
| A7 | Touch targets | ≥ 44 × 44 px everywhere; the film gate is 56 px on phone; edge dimmers are 48 px wide (DESIGN §13) |
| A8 | Focus visibility | every interactive element has a 2 px `--focus` ring at 2 px offset in both palettes; a Playwright screenshot probe and a Flutter `Focus` traversal test |
| A9 | Announcements | §3.10 L10 and U3 — once per phase, never per frame |
| A10 | Slider semantics | the gate is a slider whose `valueText` is a timecode; the sync rule's is "plus 0.35 seconds"; toggle bulbs are switches; decorative bulbs, beam and dust are excluded from semantics |
| A11 | Reduced motion | W6, W20, U8; plus a Flutter test that `disableAnimations` leaves **zero** repeating tickers alive |
| A12 | Keyboard completeness | I11 (cue sheet as the single source of truth) and X10 |
| A13 | Subtitle legibility default | the shipped libass style is Noto Sans, white with a 2 px black outline and 40 % shadow (`BorderStyle=1`) — asserted by reading back the mpv `sub-*` properties in `subtitles_test` |
| A14 | Manual screen-reader pass | NVDA on Windows and TalkBack on Android walk Lobby → Threading → Auditorium → Booth → Ticket Office before every tag (§14 M-A9, §15 W-A6) |

---

## 11. Licensing, privacy and secret-leak checks (`ci.yml`, every PR)

These are cheap greps and manifest reads, and they are the only defence against the three failure modes that would actually matter (DECISIONS §D5, GOAL §9).

| # | Check | Fails when |
|---|---|---|
| G1 | `flutter pub deps --style=compact` piped through an allow-list of licences | any transitive package is AGPL, GPL, or unlicensed. `guessit-js` (LGPL-3.0) must never appear in `web/package-lock.json` either |
| G2 | The Android flavour actually linked | the built APK contains `libmpv.so` from anything other than the `default` flavour; the check reads the resolved `media_kit_libs_android_video` version and asserts it pins release `v1.1.7` `default-*.jar` (RESEARCH §4) — `encoders-gpl` would make the app GPLv3 |
| G3 | The Windows DLL provenance | `libmpv-2.dll`'s SHA-256 matches the pinned expected value recorded in `tools/libmpv-windows.sha256`; if the DLL-refresh step (GOAL §7 "someday") is ever enabled, the source archive name must contain `-lgpl-` |
| G4 | Attribution present | the built app's Ticket Office string table contains "Subtitles by OpenSubtitles.com", the TMDB notice sentence verbatim, LGPL notices with links to both build-script repos, and the OFL font list |
| G5 | No secret in any bundle | grep `web/dist/**` and the Windows/Android artifacts for the OpenSubtitles consumer key pattern and for `VITE_.*KEY`; grep the repo tree for `.p12`, `key.properties`, `local.properties` |
| G6 | No telemetry | grep the whole tree for `analytics`, `sentry`, `posthog`, `gtag`, `firebase`; the Lite CSP `connect-src` allow-list contains only `'self'`, the Worker origin and the two optional TMDB hosts (`api.themoviedb.org`, `image.tmdb.org`) — nothing else; and X1 asserts no off-origin request is made from the landing page |
| G7 | TMDB cache expiry | DB5 — a build whose cache TTL constant exceeds 6 months fails |
| G8 | Fonts | every `font-family` in `tokens.css` / `pubspec.yaml` is one of Big Shoulders Display, Geist, Geist Mono, Noto Sans; no Fraunces, no Bebas (§2.12, the portfolio rule) |
| G9 | Design tokens in sync | `node scripts/tokens.mjs && git diff --exit-code web/src/styles/tokens.css lib/theme/tokens.dart` |
| G10 | Cue sheet in sync | `design/cue-sheet.json` is the source for the `?` overlay and the README table; a diff after regeneration fails (see I11) |

---

## 12. Determinism, coverage and flake policy

- **Coverage gates.** 100 % line coverage on `lib/engine/hash.dart`, `scoring.dart`, `timecode.dart`, `sync_rule.dart`, `tickets.dart` and their TS twins; ≥ 90 % on the rest of `lib/engine` and `web/src/engine`; ≥ 80 % on `worker/src`. UI code has no coverage gate — goldens and integration tests are its gate. Enforced by a small script over `coverage/lcov.info` and Vitest's `--coverage.thresholds`.
- **A flaky test is a broken test.** No `retries` in `playwright.config.ts` on the local/PR runs (CI gets `retries: 1` only so a runner hiccup does not block a merge, and any test that uses its retry is quarantined with an issue link the same day). No `waitForTimeout` in e2e — wait on state (`toHaveText`, `toHaveJSProperty`, `page.clock`), never on the wall clock.
- **No sleeping in unit tests.** Dart uses `fakeAsync`/`withClock`; Vitest uses `vi.useFakeTimers()`; Playwright uses `page.clock`.
- **Golden discipline.** Goldens are regenerated only on `ubuntu-24.04`, only by `flutter test --tags golden --update-goldens`, and a PR that touches `test/goldens/**` must say why in its description. A golden diff is reviewed as an image, not accepted blind.
- **Fixture discipline.** `make-fixtures.sh && git diff --exit-code test/fixtures` runs in `ci.yml`; a drifted fixture (different ffmpeg build, missing bit-exact flag) fails loudly rather than silently changing every hash.
- **Test data never leaves the repo.** No real film, no real subtitle file, no real API key in `test/` — the fixtures are synthetic (`testsrc2` + `sine`) and the only external download is `breakdance.avi`, which is fetched to a temp dir and never committed.

---

## 13. Day-1 verification list (unverified research claims)

RESEARCH's verification log leaves a set of claims at *likely* or *unverified*. Each becomes a concrete check on day 1 — before Phase 1 feature work — and each has a home in the test suite so the answer is locked in once it is known. **Record the answer in `docs/RESEARCH.md`'s verification log in the same commit as the test change.**

| # | Claim to check | How to check it | What changes when it is answered |
|---|---|---|---|
| 1 | OpenSubtitles per-second rate limit (the "~5 req/s" figure has no primary source) | Run `contract.test.ts` K2 with a real key; read `X-RateLimit-Limit/Remaining/Reset` and log them into `worker/test/observed-limits.json`. Then send 10 sequential searches and see where 429 appears | Sets the client-side spacing constant in `opensubtitles.dart`/`.ts`; O9/O10 keep working either way |
| 2 | Download-`link` TTL (410 exists, duration unknown) | K7 with `RUN_DOWNLOAD_PROBE=1`: download once, fetch the link immediately, then again after 1 h | Decides whether the app may cache a `link` at all (current design: never — store the file, not the link) |
| 3 | `moviehash_match=only` — does the gateway honour it? | K4 with a real key; compare result counts for `include` vs `only` on a hash with mixed matches | If honoured, the hash search can drop client-side filtering; if not, O1 stays as-is |
| 4 | **`GET /utilities/guessit` exists** (Kong returns 403 for real and fake routes without a key, so existence was unprovable) | K5 with a real key | If it exists, `guessit-ok.json` becomes live-validated and the endpoint is the *fallback* parser (`filename.dart` stays primary — a network round-trip must never be on the critical path). If not, delete the fixture and the code path |
| 5 | Free-account daily downloads: 10 or 20? (the two help articles disagree) | K6: sign in with the free account and read `user.allowed_downloads` | Nothing in code changes — the app already trusts the login response (§2.6, O12) — but the copy in DESIGN §8.5 ("7 OF 10 TONIGHT") is confirmed or updated |
| 6 | Does OpenSubtitles require visible attribution for API consumers? | Read the current ToS with the key in hand; if silent, ask support | The credit line ships regardless (GOAL §9); this only decides whether it may be moved out of the Lobby footer |
| 7 | **Windows `libmpv-2.dll` swap** for a current zhongfly `mpv-dev-lgpl-x86_64-*` build (loader has no version check; client API 2.x is additive — but nobody has documented doing it) | Build the Windows exe, drop the newer LGPL DLL in beside it, run the whole `integration_test` suite plus the 12-file corpus by hand | If it works, the "DLL refresh" CI step (GOAL §7) becomes real and G3's expected hash is parameterised. If it crashes, the app stays on the pinned Oct-2024 DLL and the risk in RESEARCH §8 stands |
| 8 | **libass on a real Android phone**: does it render, and what does `vo=gpu` + `hwdec=auto-safe` cost in battery and heat? (issue #945's thread could not be read; no data exists anywhere) | §14 M-P4/M-P5: play a 45-minute ASS-subtitled 1080p file with the screen on, record battery drain and skin temperature, then repeat with subtitles off | Decides whether bias light stays opt-in on Android (DESIGN §14) and whether an "ASS off" escape hatch is needed |
| 9 | What the media_kit `full` Android flavour adds over `default` | Diff `flavors/default.sh` and `flavors/full.sh` in `libmpv-android-video-build` | Only matters if a codec turns out to be missing in the 12-file corpus; `default` is what ships either way (G2) |
| 10 | Browser reality for MKV / HEVC / AC-3 and whether Firefox exposes HEVC through `VideoDecoder` | §15 W-B1..W-B4: run the fixture matrix by hand in Edge, Chrome and Firefox on the owner's PC, and record `VideoDecoder.isConfigSupported` output | Fixes the honest capability line copy (§2.10) and decides whether the `movi-player`/`mediabunny` path is worth building at all |
| 11 | Subdl: real download limits for a keyed user, and `dl.subdl.com` zip-link stability | One manual search + one anonymous zip download with the owner's free key; repeat the link after an hour | Confirms D3 (downloads must be anonymous) and whether the zip URL may be cached |
| 12 | **The Third Man's ids** — `imdb_id: 41959` (tt0041959) and `tmdb_id: 1092` were recorded from memory | `GET /find/tt0041959?external_source=imdb_id` on TMDB with a real token, and read `feature_details` from a live OpenSubtitles hash search | Freezes the numbers in `search-hash-hit.json` and `tmdb-find.json`. If wrong, every fixture and golden that prints them changes in one commit |
| 13 | Cloudflare Free sign-up without a credit card (docs never say so; "no card" is experience, not writing) | Sign up and deploy `marquee-proxy`; stop immediately if a card is requested (DECISIONS §D9.5) | If a card is required, the Lite tier loses OpenSubtitles and becomes a local-file player with sidecar-only subtitles — a scope change, not a workaround |
| 14 | Which Flutter version actually builds `media_kit` 1.2.6 cleanly (the "3.38" attribution is unverified; current stable is 3.47.x) | `flutter build windows` and `flutter build apk` on the pinned version in CI | Pins `flutter-version:` in `release.yml` and `ci.yml`; that pin is then only moved deliberately |
| 15 | Is the official `breakdance.avi` still downloadable from `opensubtitles.github.io/oshash/`? | `make-fixtures.sh` fetch step | Decides whether H1 runs or is permanently skipped; V2–V5 and V7 already cover the algorithm without it — including the >2³² case the spec's second vector (`dummy.rar`) covers |
| 16 | TMDB: does embedding a read token in a client violate anything, and what is the real rate limit? | Read the auth docs with the account open; watch for 429 during a library scan | Decides between a CI-injected token and BYO-key-only (GOAL §7 already allows both) |
| 17 | Anonymous 5/day/IP — is it shared across everyone behind one NAT? | Two anonymous downloads from the same network, then check `remaining` | Sets how hard the app pushes the one-time sign-in nudge (T4) |
| 18 | GitHub Pages serves the PWA manifest and service worker correctly under `/marquee/` | First deploy + `curl -I` on `manifest.webmanifest` and `sw.js`; then install on Android Chrome | DEPLOYMENT §6; a failure means `base`/`scope` are wrong, not the app |

Day 1 is not done until every row above has an answer or an explicit "still unknown, mitigated by X" note in RESEARCH's verification log, and until DECISIONS §D9.1 is satisfied: Marquee Lite live on Pages, `marquee-proxy` deployed, and a debug APK attached to a pre-release.

---

## 14. Manual QA checklist — Android (run before every `v*` tag)

Device: the owner's phone, Android 14+, **installing the tag's own `marquee-<version>-arm64-v8a.apk` from the GitHub Release** (that is the published asset name; `app-arm64-v8a-release.apk` is the raw Flutter output and never appears on a Release) — never a debug build and never over `flutter run`. Uninstall the previous build only when testing a first install; otherwise install over the top to prove updates work.

**Install and first run**
- [ ] M-I1 The APK downloads in Chrome on the phone and installs after allowing "install unknown apps" once.
- [ ] M-I2 It installs **over** the previous version without an uninstall (same keystore, higher `versionCode`) and the library, resume positions and sync offsets survive.
- [ ] M-I3 First launch shows the splash (`#07060A`, one 72 dp bulb) and reaches the Lobby in **< 2.5 s** on a cold start (stopwatch, N3).
- [ ] M-I4 The adaptive icon renders correctly on the launcher, including the themed/monochrome variant.

**Permissions and files**
- [ ] M-F1 Opening a file through the SAF picker works with **no** permission prompt at all.
- [ ] M-F2 "Open with" from Files / a download notification launches Marquee straight into Threading.
- [ ] M-F3 Granting media access (for the MediaStore library scan) shows the correct Android 14 dialog; choosing **"Select photos and videos"** (partial access) is handled — the library shows what was selected plus a "select more" affordance, never an empty screen.
- [ ] M-F4 Denying media access leaves the SAF path fully working; the app never nags twice.
- [ ] M-F5 A subtitle is saved **beside** the file when the tree URI is writable; when it is not, it lands in app storage and the Booth says so in one sentence.
- [ ] M-F6 Revoking permission in Settings while the app is backgrounded does not crash it on resume.

**Playback (the 12-file corpus, GOAL §5.2)**
- [ ] M-P1 All 12 files play with video **and** audio; hardware decode is in use where available (Ticket Office → Projection shows `auto-safe`).
- [ ] M-P2 The MKV+ASS file renders with **identical positioning and styling** to the Windows build — compare screenshots side by side (this is the libass acceptance criterion).
- [ ] M-P3 The MKV+PGS file shows image subtitles.
- [ ] M-P4 **Battery/thermal probe (§13 #8):** a 45-minute 1080p ASS file, screen on, brightness 50 %, aeroplane mode. Record start/end battery % and whether the phone throttles or gets uncomfortably warm.
- [ ] M-P5 Repeat M-P4 with subtitles off; the difference is the libass cost. Record both numbers in RESEARCH's verification log.
- [ ] M-P6 Audio focus: an incoming call pauses playback and it resumes (or stays paused) sensibly; a notification sound ducks rather than stopping.
- [ ] M-P7 Bluetooth headphones connect/disconnect mid-playback without a crash; disconnect pauses.
- [ ] M-P8 Keep-screen-on holds during playback and releases on pause and on exit (the screen must time out normally in the Lobby).

**Gestures, navigation and layout**
- [ ] M-G1 Single tap reveals controls; they auto-hide after 2400 ms; the folio stays at 40 %.
- [ ] M-G2 Double-tap left/right thirds seek ∓10 s and the gate visibly jumps.
- [ ] M-G3 Long-press gives 2× while held; the folio reads `2.0×`; releasing returns to 1.0×.
- [ ] M-G4 Vertical drag on the left edge changes brightness, on the right edge volume, each with a mono readout; both start **inside** the system gesture inset and do not fight the back gesture.
- [ ] M-G5 Horizontal drag scrubs with the gate following; releasing snaps at a chapter with a tick.
- [ ] M-G6 Pinch toggles fit/fill.
- [ ] M-G7 **Predictive back:** the system back preview from the Booth sheet shows the room behind it, not a blank page; from the Auditorium it runs `house-up`; from the Lobby it exits. Test with gesture navigation *and* 3-button navigation.
- [ ] M-G8 Rotation portrait ↔ landscape does **not** rebuild the player (playback continues without a stutter or a re-buffer) and the layout switches to the landscape arrangement of DESIGN §9.3.
- [ ] M-G9 Edge-to-edge: status and navigation bars are transparent, icons are light in the Auditorium and dark in the Matinee lobby, and no control sits under the gesture bar or the camera cutout in landscape.
- [ ] M-G10 On a foldable or a > 600 dp screen, the orientation lock being ignored does not break the layout.

**Picture-in-picture and interruptions**
- [ ] M-N1 Home/recents during playback enters PiP; the folio appears in the PiP title; tapping the PiP window restores the Auditorium at the same position.
- [ ] M-N2 Closing the PiP window stops playback and releases the wakelock.
- [ ] M-N3 Killing the app from recents mid-film and reopening resumes at the stored position.
- [ ] M-N4 A low-memory background kill does not corrupt the drift DB (reopen and check the library).

**Threading and subtitles on device**
- [ ] M-T1 A hash-hit file reaches "subtitles attached, in sync" with no interaction (GOAL §5.1).
- [ ] M-T2 Aeroplane mode → the leader stalls on "2" and offers "Play without subtitles"; nothing crashes and no ticket is spent.
- [ ] M-T3 The ticket strip's `remaining` matches what the OpenSubtitles website reports for the account.
- [ ] M-T4 Sign-in works, the JWT survives an app restart, and the password is not stored (check with the app's own "sign out" then a cold start).
- [ ] M-T5 The sync rule's detents are felt (`selectionClick`) and the offset survives closing and reopening the same film.

**Accessibility on device**
- [ ] M-A1 TalkBack walks Lobby → Threading → Auditorium → Booth → Ticket Office; every control is announced with a useful label.
- [ ] M-A2 The leader announces four times, not continuously.
- [ ] M-A3 The gate announces a timecode; the sync rule announces "plus 0.35 seconds".
- [ ] M-A4 System font size at maximum does not clip the folio, the ticket strip or the candidate rows.
- [ ] M-A5 "Remove animations" in Accessibility settings kills the beam and dust; the leader still stalls honestly.
- [ ] M-A6 Every target is comfortably thumb-hittable one-handed; the gate is 56 px.

---

## 15. Manual QA checklist — Windows and browsers (run before every `v*` tag)

Machine: the owner's Windows 11 PC, running **the tag's own zip**, extracted to a fresh folder (not the dev build directory).

**Install and window**
- [ ] W-I1 The zip extracts and `marquee.exe` runs with no missing-DLL dialog; `libmpv-2.dll` sits next to it.
- [ ] W-I2 SmartScreen shows "Windows protected your PC" (expected — the exe is unsigned). "More info → Run anyway" works. **The README must say this before a user meets it.**
- [ ] W-I3 Running from a path with spaces and one with a non-ASCII character both work (media_kit 1.2.4–1.2.6 shipped long-path fixes; this is the regression check).
- [ ] W-I4 Cold start → Lobby in **< 1.5 s** (N3).
- [ ] W-I5 The frameless window drags by the marquee title bar; minimise/maximise/close bulbs work; double-click on the bar maximises; the window remembers its size and position.
- [ ] W-I6 Mica is visible in the Lobby and **off** during playback (the picture area is opaque black).
- [ ] W-I7 `marquee.exe "D:\Films\The Third Man (1949).mkv"` opens straight into Threading.
- [ ] W-I8 Two instances do not fight over the same file; the second either focuses the first or opens independently without corrupting the DB.

**Playback**
- [ ] W-P1 The full 12-file corpus plays with video and audio.
- [ ] W-P2 The MKV+ASS file matches the Android render (M-P2).
- [ ] W-P3 Hardware decode is active (D3D11VA) and toggling it off in the Ticket Office falls back to software without a restart.
- [ ] W-P4 A 4K HEVC 10-bit file plays without dropped frames; if it does not, record the numbers rather than guessing.
- [ ] W-P5 Chapters appear as gate detents; a file without chapters gets 5-minute detents.
- [ ] W-P6 Every shortcut on the `?` cue sheet does what it says — the sheet is the contract (I11).
- [ ] W-P7 Fullscreen (F) and back (Esc) do not lose the position or the subtitle track.
- [ ] W-P8 An external monitor with a different DPI: moving the window mid-playback does not corrupt the texture.
- [ ] W-P9 Sleep/resume mid-playback recovers.

**Threading and files**
- [ ] W-T1 Drag-and-drop from Explorer works, including a multi-file drop (first file plays, the rest queue or are ignored — whichever the build does, it must not crash).
- [ ] W-T2 A read-only folder: the subtitle falls back to app storage with the one-sentence note.
- [ ] W-T3 A network/UNC path (`\\nas\films\…`) opens, or fails with one honest sentence.
- [ ] W-T4 Hash + search + download + attach completes in **< 3 s** on a 10 Mbit connection (N4) — throttle with the browser dev tools closed and a real network limit if possible, otherwise note the actual bandwidth.

**§13 #7 — the libmpv DLL swap probe** (do this once, on day 1, then only when refreshing)
- [ ] W-D1 Download the current `mpv-dev-lgpl-x86_64-*.7z` from zhongfly's releases (the **`-lgpl`** package, never the plain one — G3).
- [ ] W-D2 Replace `libmpv-2.dll` in the extracted app, keeping the original.
- [ ] W-D3 Run the entire integration suite and the 12-file corpus. Record: launches / crashes / any codec that changed behaviour.
- [ ] W-D4 Restore the original DLL and confirm the app still works. Write the verdict into RESEARCH §8.

**Browser matrix for Marquee Lite (§13 #10)** — on the same PC, against the deployed Pages URL, not a dev server
- [ ] W-B1 Edge, Chrome, Firefox: drop each of the six media fixtures and record play / no-play and the No Print reason. Fill in the table in RESEARCH §5.4.
- [ ] W-B2 In the dev console of each browser, run `VideoDecoder.isConfigSupported({codec:'hvc1.1.6.L93.B0'})` and `{codec:'av01.0.05M.08'}` and record the results — this settles whether Firefox exposes HEVC through WebCodecs.
- [ ] W-B3 The capability line printed by the app matches what the probes actually say (§2.10). If it over-promises, the line is wrong, not the browser.
- [ ] W-B4 An MKV that Chrome plays and Firefox does not shows the No Print card in Firefox within 1 s (N16) — never a black rectangle.
- [ ] W-A1 NVDA walks the Lite landing, Threading, the player and the No Print card; the leader announces four times.
- [ ] W-A2 Windows "Show animations" off (or `prefers-reduced-motion`) removes the beam and dust in Lite and in the native app.
- [ ] W-A3 200 % Windows display scaling: nothing clips in either tier.
- [ ] W-A4 Keyboard-only: complete a full session in Lite (open → subtitle → seek → sync → fullscreen → exit) without touching the mouse.

**PWA**
- [ ] W-W1 Chrome/Edge offer "Install"; the installed app opens at the Lite landing under `/marquee/`.
- [ ] W-W2 Offline after one visit: the shell loads and a previously fetched subtitle is still available (X11).
- [ ] W-W3 A new deploy updates the installed app on the next launch (no stale shell pinned forever).

---

## 16. What CI runs

| Workflow | Trigger | Jobs |
|---|---|---|
| `ci.yml` | every push and PR | `analyze` (`flutter analyze`, `dart format --set-exit-if-changed`, Biome on `web/` and `worker/`) · `dart-test` on `ubuntu-24.04` (`flutter test` incl. goldens, coverage gates) · `web-test` (Vitest, `size-limit`) · `worker-test` (`@cloudflare/vitest-pool-workers`) · `e2e` (Playwright, 3 projects, uploads the HTML report and any diff images) · `checks` (§11 G1–G10, `make-fixtures.sh` diff, `scripts/check-parity.mjs`) · `lighthouse` |
| `pages.yml` | push to `main` touching `web/**` | build + deploy Marquee Lite (DEPLOYMENT §5); runs `npm test -- --run` first so a broken Lite never reaches the live URL |
| `worker.yml` | push to `main` touching `worker/**` | `worker-test` then `wrangler deploy` (DEPLOYMENT §4) |
| `release.yml` | tag `v*` (and `workflow_dispatch` for a dry run) | `test` (Windows integration, §6) → `build` matrix (Windows exe + split-per-ABI APKs) → `publish` (GitHub Release). Size gates N9–N11 and the 25-minute budget N17 live here (DEPLOYMENT §7) |
| `contract.yml` | nightly cron + `workflow_dispatch` | §7.2 against the real API with `OS_API_KEY`; opens an issue on a shape change instead of failing a branch |

A pull request may merge when `ci.yml` is green. A tag may be cut when `ci.yml` is green **and** §14 and §15 have been walked on the actual artifacts.

---

## 17. Release gate — the short version

Before `git tag v…`:

1. `ci.yml` green on `main`, including the golden diff review.
2. `contract.yml` green (or its issue triaged) within the last 24 h.
3. Every open row of §13 has an answer or an explicit mitigation note in RESEARCH's verification log.
4. §14 walked on the phone with the previous release installed first (proves the update path).
5. §15 walked on the PC, including the browser matrix against the live Pages URL.
6. Budgets N1–N18 re-measured by hand for N3, N4 and N17; CI covers the rest.
7. The keystore backup and the OpenSubtitles/Cloudflare credentials are still where DEPLOYMENT §11 says they are.
8. `docs/RESEARCH.md`, `docs/DESIGN.md` and this file agree with what actually shipped — if any golden number moved, the doc moved in the same commit.
