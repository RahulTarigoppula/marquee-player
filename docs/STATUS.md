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
| D12 | Dart and TS engines behave identically | Agreed on auto-pick (first human row), score reasons (`HI ±30`, `downloads +x.xx`), folio dash for unknown/infinite/≤ 0 durations, SRT tag/arrow/trim handling and spoken zero. **Still different, on purpose:** the ticket strip (Dart: VIP with 0 left stays `VIP`, signed-in-unknown reads `SIGNED IN · TICKETS UNKNOWN` and login fills `remaining`; TS: `exhausted` and `20 TICKETS A DAY`, plus reset refill / 406 / user-info in the strip) and threading (Dart: a hash timeout falls through silently to a name search, `retry()` after a failed manual search re-runs the hash/name rung, the sweep loops each second, a download stall offers no filename search; TS: stalls with `timeout`, repeats the typed query, holds the sweep at `SWEEP_HOLD`, offers filename search) | each is listed with a reason in `scripts/parity-allow.json`; `check-parity.mjs --strict` keeps the list honest |

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

## 5. Pass 2 (2026-10-18)

The first pass was green locally but **red on GitHub**: format gate tripped on build_runner output,
the token check ran `dart format` without a package config, Biome failed on UTF-8 mojibake
(PowerShell 5.1 rewrote files as cp1252), Playwright ran without a mocked API base, the Windows
release lacked the MSVC runtime, the APK check mis-read apksigner, and Pages was never enabled.
All fixed; see the commits of 2026-10-18.

| Area | What changed |
|---|---|
| CI/CD | tracked-file format gate; `--reporter github`; Windows release bundles the MSVC runtime and ships an **Inno Setup per-user installer** (Start menu, "Open with" for 15 video types) beside a portable zip; robust APK signature check with a debug-key note in the release notes; Pages skips with one warning when off; grouped monthly Dependabot |
| Screenshots | `test/screens` renders every room on Linux CI (`screenshots.yml`) to the `screenshots` branch — the review loop for a build machine that cannot run Flutter |
| Playback | ~25 runtime defects from a static audit (Android picker copied whole films to cache, film played under the leader, fullscreen trap, negative seeks, laggy bias light, focus loss, re-entrant open, resume fragility…) and an overlay player with volume/audio/subtitle/speed/picture/chapter/sleep menus, next-in-folder with Up next, thumbnails, single-instance Windows, PiP button |
| Lobby / Settings | thumbnail-led Lobby (hero, Continue watching, grid, Undo remove, Open URL); Settings in plain-language sections; component kit; repaint fixes |
| Lite | see web/README.md |

New deviations:

| # | Plan said | Built | Why |
|---|---|---|---|
| D13 | libass renders all subtitles | On **Android**, text subtitles whose language/script libass's single bundled font cannot draw are rendered by Flutter (`SystemFontSubtitles`, system fonts) with mpv's own subtitles hidden; bitmap subs stay with mpv | libass on Android sees one font file; loading `/system/fonts` would load every font into memory. ASS positioning is lost only for those tracks |
| D14 | bias light on by default | **off** by default, one unlocked JPEG every 3 s when on | the 500 ms full-resolution screenshot held the player lock and made seeks lag |
| D15 | resume "finished" = position 0 | finished stored as position = duration | a film closed at 0 s looked fully watched |
| D16 | zip-only Windows release | installer + portable zip | friends need Start menu and "Open with" |

Still open: C++ single-instance and Kotlin picker/PiP changes are verified only by CI compile
and real devices; Android has no folder-sibling "next episode" (needs a SAF tree grant);
Media Session / SMTC integration; seek-bar thumbnails.
