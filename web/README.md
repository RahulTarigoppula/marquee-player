# Marquee Lite

The browser tier of Marquee: a small Vite + TypeScript page (no framework) that plays whatever
the browser can decode, with the same HOUSE LIGHTS look as the native apps. You drop a film (or
open it), the house lights go down and it plays; subtitles come from a file you bring or, when a
server is configured, from OpenSubtitles. It says plainly when it can't play something, and
points to the Windows / Android apps, which play everything.

Live: <https://rahultarigoppula.github.io/marquee-player/> (GitHub Pages, base path
`/marquee-player/`).

## Two modes

**No Worker (the default build).** `VITE_API_BASE` is empty, so nothing is fetched off-origin.
A film goes straight to the player. Subtitles: choose an `.srt` / `.vtt` / `.ass` / `.ssa`
together with the film, drop it anywhere on the page, or use **Add subtitle file…** in the player
or the subtitle booth. Encodings are detected (UTF-8, UTF-16 with a BOM, else windows-1252). The
film's moviehash still keys a local IndexedDB cache, so a subtitle file you added once, your sync
offset and your resume point come back the next time you open the same film. The landing says
that online search needs the native apps or a configured server. There is no ticket office.

**With the Worker** (`worker/`, optional). Set `VITE_API_BASE` to
`https://<name>.<subdomain>.workers.dev/api`. Then the academy leader counts 3-2-1 while the
film is fingerprinted and searched; the best print downloads once you sign in at the ticket
office with a free OpenSubtitles account (the Worker refuses anonymous downloads, which would
spend its own IP's quota). The search sends the 16-digit fingerprint and the title/year from the
file name — never the film. The origin must be listed in the CSP `connect-src` in `index.html`
(`https://*.workers.dev` and `http://localhost:8787` already are) and in the Worker's
`ALLOWED_ORIGIN`.

A "bring your own OpenSubtitles API key" mode was investigated and not built: the API's
preflight allows any origin, but the `/login` and `/download` responses carry no
`Access-Control-Allow-Origin`, and headless/non-browser user agents are blocked, so a browser
cannot complete a download directly.

## Run

```bash
npm ci
npm run dev          # http://localhost:5173 — with the Worker at http://localhost:8787/api
VITE_API_BASE= npm run dev   # the no-Worker mode
npm test -- --run    # Vitest (happy-dom, TZ=Asia/Kolkata): engine goldens + components
npm run e2e          # Playwright — see below
npm run lint         # biome ci .
npm run build        # tsc --noEmit && vite build
npm run size         # size-limit: JS ≤ 120 KB gzipped, lazy JASSUB chunks excluded
```

Configuration is public only:

| Variable | Meaning |
| --- | --- |
| `VITE_API_BASE` | The Worker's `/api` base. Empty or unset in a build = no Worker. Unset in `npm run dev` = `http://localhost:8787/api`. |
| `VITE_BASE_PATH` | `/marquee-player/` on Pages (the repository name), `/` elsewhere. |
| `VITE_APP_VERSION` | Shown nowhere critical; the commit SHA in CI. |
| `VITE_RELEASES_URL` | Optional. On `*.github.io` the Releases link is derived from the URL. |

The OpenSubtitles key lives in the Worker and is never in a `VITE_*` variable.

### End-to-end tests

`playwright.config.ts` builds the site twice into `dist-e2e-worker` (port 4273, `VITE_API_BASE`
= `http://localhost:8787/api`, every `/api/**` call mocked with `page.route`) and
`dist-e2e-lite` (port 4274, no Worker), and never reuses a running server. Projects: `chromium`,
`firefox` (when installed — always in CI), `pixel-7` against the Worker build; `lite-chromium`
and `lite-pixel-7` run `*.lite.spec.ts` against the no-Worker build.

## The player

An overlaid player: title and the way back on top; seek bar (played in tungsten, buffered in
grey, a time tip on hover, 5-minute detents, drag up for FINE), play, ±10 s, volume (remembered),
time, subtitle delay, add subtitle, subtitles, speed, picture-in-picture (when supported) and
fullscreen below. The chrome hides after 2.4 s of stillness while playing; cues step up while it
shows. Mouse: click = play/pause, double-click = fullscreen. Touch: tap = show/hide the controls,
double-tap left/right = ∓10 s (keep tapping to skip further), double-tap the middle =
fullscreen. iPhone uses the video's own fullscreen; phones lock to landscape in fullscreen where
the browser allows. Safe-area insets are respected. Where you stopped is remembered per film
("Resumed from 1:02:13 · Start over"), and the Media Session API puts the title and play/pause/
seek on the lock screen and media keys. If the film plays but the browser lacks its audio
(AC-3, E-AC-3, DTS) or video codec, a note says so without stopping the film.

Keyboard (also in the in-app cue sheet, `?`):

| Key | Action |
| --- | --- |
| Space · K | Play / pause (K as on YouTube) |
| ← / → · Shift | ∓5 s · ∓30 s |
| J / L | ∓10 s |
| 0 … 9 | Jump to 0 % … 90 % |
| ↑ / ↓ · M | Volume · mute |
| F · double-click | Fullscreen |
| C · S | Subtitles on/off · subtitle booth |
| G / H (Shift = 500 ms) | Subtitles 50 ms earlier / later (as in VLC) |
| Shift + G + H | Reset subtitle sync |
| , / . · [ / ] · B | Frame step · speed · A–B loop |
| P · ? · Esc | Picture-in-picture · cue sheet · back one lighting state |

Subtitle sync moved from J/K (the native apps' keys) to G/H on the web because K pauses on
YouTube and J/L skip there; `design/cue-sheet.json` stays the native map.

An installed Lite (PWA) registers `file_handlers`, so "Open with → Marquee Lite" hands the film
(and subtitle files) to it through `launchQueue`.

## Layout

- `src/engine/` is pure (no DOM, `window` or `fetch`; `api.ts` takes an injected fetch): the
  moviehash, the filename grammar, scoring, the leader state machine, tickets, timecodes, the
  sync rule, SRT→VTT, sidecar decoding (`sidecar.ts`), subtitle languages (`languages.ts`), the
  capability probe and the Worker client. Each file has a colocated test. `TEST_NAMES.txt`
  (from `npm run test-names`) is the TypeScript side of the Dart parity check.
- `src/ui/` holds the landing, the leader, the seek bar (`gate.ts`), the booth, the No Print
  card, the ticket office and the auditorium. Text is only ever set with `textContent`. Overlays
  make everything beneath them `inert`; dialogs trap focus and give it back.
- `src/storage/idb.ts` stores subtitles, offsets, resume points and the session in IndexedDB.
  The JWT is sealed with a non-extractable AES-GCM key, and "This session only" keeps it in
  memory. `src/storage/prefs.ts` keeps volume, mute, subtitle size and language in
  `localStorage`.
- `src/styles/tokens.css` is generated by `scripts/tokens.mjs`, so don't edit it.
  `src/styles/app.css` and `src/styles/player.css` use token variables only.

JASSUB (ASS/SSA) is loaded only through a dynamic `import()` when an `.ass`/`.ssa` file attaches.
It runs single-threaded because Pages can't send COOP/COEP, and it is kept out of the precache
(runtime CacheFirst instead).

## Attribution

Subtitles by OpenSubtitles.com. Fonts: Big Shoulders Display, Geist, Geist Mono (OFL 1.1, via
Fontsource). Icons are Lucide path data (ISC). JASSUB (libass, LGPL-2.1+) is loaded on demand.
Our code is MIT.
