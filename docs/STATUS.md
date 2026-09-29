# Marquee — implementation status

Written 2026-09-29, at the end of the first build pass. This is the honest ledger: what exists,
what was verified and how, what deviates from the plan and why, and what is still open.
`docs/IMPLEMENTATION-PROMPT.md` stays the normative spec; where this file records a deviation,
the deviation wins until the spec is edited to match.

## 1. What exists

| Tier | State | Verified by |
|---|---|---|
| **Engine** (`lib/engine/`, pure Dart) | moviehash, filename grammar (PTT port + anime), frozen scoring, leader state machine, tickets, timecodes, sync rule, detents, SRT→VTT, bias-light extraction, sentences | `dart test test/engine` — every §6 golden reproduces (A/D/C/B = 1414.09 / 414.71 / 232.96 / 63.61, the 2³² hash vector, the byte-exact CRLF+BOM VTT, the 152 px / 160 px detent pair…). Coverage gates pass: 100 % on hash/scoring/timecode/sync_rule/tickets, 95 % on the rest |
| **API** (`lib/api/`) | OpenSubtitles REST v1 client (sorted params, mandatory headers, 401/406/410/429 → typed failures, one Retry-After retry), Subdl client with an in-memory zip reader (traversal + 2 MB guards, anonymous download) | `dart test test/api` against `MockClient` + the shared fixtures |
| **DB** (`lib/db/`, drift) | the eight tables, hash cache with vanished-sidecar invalidation, resume (finished within 30 s), per-hash sync offsets, 24 h search cache, 180-day artwork sweep, app_state, export/import (merge, newer wins, no secrets) | `dart test test/db` on `NativeDatabase.memory()` |
| **App** (`lib/`) | Riverpod providers + `SessionNotifier` (player + leader + cache + sidecar), Lobby, Threading overlay, Auditorium (film gate, sync rule, folio, keyboard map, bias light, edge dimmers, long-press 2×, double-tap ±10 s, PiP), Booth sheet, Ticket Office (sign-in, languages, bulbs, export/import, licence trail), cue sheet from `design/cue-sheet.json`, frameless Windows window with persisted bounds, drag-and-drop, command-line open, Android "Open with" | `flutter analyze` — **no issues**; structural-law tests (engine purity, widgets never import `lib/api`/`lib/db`, one house tween) |
| **Android native** | manifest per §8.2, PKCS12 env signing, `marquee/content` (Open-with URI, stat, chunk reads for hashing `content://`), `marquee/pip`, adaptive icon, splash | XML parses; Kotlin reviewed by hand (no Android SDK on the build machine) |
| **Worker** (`worker/`) | §7.6 superset + three hardening fixes (see §3) | `npm test` — 104 tests, incl. "the key never leaks" after every case; `tsc`, Biome clean |
| **Lite** (`web/`) | see `web/README.md` | Vitest + build (see that README) |
| **CI/CD** | `ci.yml`, `pages.yml`, `release.yml`, `worker.yml`, `contract.yml`, Dependabot, parity / cue-sheet / secrets / licence / coverage checks | YAML parses; each check script run on this tree |

## 2. What could not be verified on the build machine

The machine that produced this pass has **Windows Smart App Control** enabled and **Developer Mode
off**. That blocks, by design, three things — none of them was worked around:

1. `flutter test` (it runs `impellerc.exe` to compile shaders, which Smart App Control refuses).
   Pure-Dart suites were therefore written against `package:test` and run with `dart test`; the
   three widget tests in `test/widgets/` have only been analysed, not executed. **CI runs all of
   them** with `flutter test`.
2. `flutter build windows` (plugin symlinks need Developer Mode).
3. The Workers test pool (`workerd.exe`) — the Worker suite runs in plain Node with a stubbed
   `fetch` and `caches.default` instead.

There is no Android SDK here either, so the APK is CI-built only (as the plan always intended).
**First action for the owner:** push to GitHub and read the `ci` run; then tag `v0.1.0`.

## 3. Deviations from the plan (all deliberate)

| # | Plan said | Built | Why |
|---|---|---|---|
| D1 | Flutter 3.47.0 | **3.47.5** in `.fvmrc` and every workflow | 3.47.5 is the stable that was actually installed and analysed against |
| D2 | `material_color_utilities ^0.11.0` | `^0.13.0` | Flutter 3.47 pins 0.13.0; 0.11 does not resolve |
| D3 | hash miss ⇒ stall, user taps "filename search" | hash miss ⇒ the **name search runs immediately** (free — search is unlimited), then the numeral stalls with the rows already listed; **no ticket is spent without a tap** | saves one click on every non-hash file while keeping "never download on a guess" |
| D4 | bias light: all-black when kept < 5 % | kept < **4 %** | a 64 × 36 frame cannot hold exactly 5 %, and the spec's own "single lamp" golden (a 5 % highlight) fails at 5 % |
| D5 | Worker listing byte-identical to §7.6 as written | §7.6 and DEPLOYMENT §4.3 **updated** to the hardened listing: streamed 2 MB cap (not just `Content-Length`), every upstream `fetch` failure → 502 `WorkerError {error:'upstream'}`, `Retry-After: 60` on the Worker's own 429 | the original let a chunked body bypass the cap and could return non-JSON errors |
| D6 | `flutter_soloud` sounds, `flutter_acrylic` Mica, `flutter_animate`, `grain.frag` | **not added** | sound is optional polish; Mica is decoration (the plan allows a flat Lobby); grain is a seeded `CustomPainter`. No dependency without a use |
| D7 | `P` = PiP in the Windows cue sheet | PiP is Android-only (a transport mark); the Windows cue sheet omits `P` | there is no desktop PiP; the cue-sheet test forbids listing a key the app ignores |
| D8 | engine tests import `flutter_test` | engine/api/db tests import `package:test` | lets them run under `dart test` too (see §2); `flutter test` runs them unchanged |
| D9 | drift data classes named after tables | `MediaRow`, `HashCacheRow`, `ResumeRow`, … | the default names collide with the engine models (`ResumePoint`, `MediaFile`) |
| D10 | `LobbyCard` in the DB layer | in `lib/engine/models/media.dart` | widgets may not import `lib/db` (structural law) — the test caught it |
| D11 | Subdl download inside the API layer only | `SessionNotifier` writes the extracted bytes through the same sidecar writer | one write path, one `.1` collision rule |

## 4. Still open (next pass, in priority order)

1. Watch the first `ci` / `release` runs and fix whatever the Linux/Windows runners disagree with.
2. `integration_test/` against real libmpv on `windows-latest` (§10.4) and the ffmpeg media
   fixtures (`scripts/make-fixtures.sh`, §10.3) — not started; the release workflow skips the step
   while the folder is absent.
3. Gate thumbnails (second `hwdec=no` player), marquee warm-up from TMDB artwork, TMDB posters,
   sounds (§3.9), MediaStore library scan on Android, SAF sidecar writes beside `content://` files
   (today they fall back to app storage, honestly labelled).
4. `tools/libmpv-windows.sha256` — needs the DLL from the first CI build.
5. Day-1 API spike answers (§9.1 0.2) into RESEARCH.md; the nightly contract run records them.
6. Align Dart and TS engine test names so `node scripts/check-parity.mjs --strict` passes.
