# Marquee — The No-Hassle Smart Media Player

**Codename:** Marquee · **Design system:** HOUSE LIGHTS · **Tagline:** *Drop a film. The lights go down. The subtitles are already there.*

Project 08 of 8 · folder `C:/Work/Personal_Projects/08-marquee-media-player` · status **first build pass done (2026-09-29, see docs/STATUS.md)** · written 2026-09-06

---

## 1. The idea

**In the owner's words.** "A rich cross-platform multimedia player (Windows + Android) that plays any video file effortlessly with built-in frictionless subtitle search powered by OpenSubtitles; it hashes/identifies what you are watching and grabs synced subtitles automatically."

**Sharpened.** Marquee is one Flutter codebase that ships a Windows `.exe` and an Android APK on top of the *same* engine — libmpv (ffmpeg + libass) via `media_kit` — so an MKV with HEVC video, AC-3 audio and an ASS subtitle track plays identically on both, with no codec packs, no "unsupported format" and no second app. The moment a file is opened it is fingerprinted with the OpenSubtitles *moviehash* (128 KiB of I/O, ~40 ms), looked up hash-first on OpenSubtitles.com, the best candidate is downloaded, saved beside the file and attached — before the first frame is shown. A hash hit means the subtitle was uploaded for that exact release, so it is already in sync; a filename-only hit is labelled honestly and a per-file sync rule fixes it in 50 ms steps. The whole identification chain is staged as the academy leader counting 3-2-1, so the loading indicator *is* the truth about what the app is doing.

A third, mandatory tier — **Marquee Lite** — is a small Vite + TypeScript web player on GitHub Pages that does the same hash → subtitle ritual for whatever the browser can decode (MP4/H.264, WebM, HEVC where the OS has it), through a Cloudflare Worker that holds the API key. It is honest about what it cannot play and points to the native builds.

## 2. Who it's for

- **The owner**, watching a downloaded or ripped film on a Windows 11 laptop in the evening and finishing it on an Android phone on the train — wanting VLC's reach without VLC's chrome, and wanting subtitles without a browser tab, a zip file and a rename.
- **Anyone who has ever** opened VLC → Subtitles → Download subtitles → waited → picked a wrong one → dragged the delay. Marquee makes the correct case zero-click and the incorrect case one-drag.
- **Not** for people who want a media server, a streaming client, torrents, IPTV or a Play Store listing.

## 3. Why it will be fun and valuable

- **It removes a ritual everyone hates.** The hash lookup is deterministic and cheap; most popular releases hit; the 5–10 downloads/day free quota is turned into a small "tear a ticket" ritual instead of a wall.
- **It is the one project in the portfolio with a different stack** (Flutter + native libs + a real proxy), so it is the deepest learning: Impeller fragment shaders, a Kotlin method channel, LGPL compliance, CI that produces a Windows binary and an APK from a machine that has neither toolchain installed.
- **It is screenshot-worthy by construction.** The room dims, a beam finds the screen, the marquee spells the title bulb by bulb, the walls glow with the colour of the film. Every UI state is a lighting state (DESIGN.md §1).
- **It stays useful after the novelty:** resume positions, per-file subtitle sync memory, chapters as seek detents, PiP on Android, keyboard-complete on Windows.

## 4. The vibe

**Dim · Warm · Honest** (the owner's brief: *seamless and cinematic*).

A single-screen cinema at night that dims for you. The Lobby is a warm room with a sky band that knows the local time and a marquee that remembers what you last watched. Drop a print and the house lights go down over 900 ms, the projector beam widens to the screen, and an academy leader counts down while the file is hashed, searched and threaded. Chrome is replaced by light: controls are small tungsten marks, the seek bar is a strip of 35 mm film with the frame in the gate, subtitle delay is a mono ruler under a fixed caret. Nothing bounces; things dim, warm, sweep and settle. Errors are a stalled numeral and one plain sentence — never a red banner, never a spinner. It must never look like retro-cinema kitsch, "YouTube ambient mode in a dark player", Napkin's paper, or skeuomorphic hardware.

## 5. Success criteria (measurable)

1. **Zero-click subtitles.** Open a ≥ 128 KiB video that has a moviehash hit on OpenSubtitles → English subtitles attached, in sync, MATCH bulb lit, first frame shown within **3 s** of the drop on a 10 Mbit connection, with no click or keypress.
2. **Any codec, both platforms.** Every file in the 12-file test corpus (MKV/HEVC/AC-3, MKV/H.264/DTS, AVI/XviD/MP3, MP4/H.264/AAC, WebM/VP9/Opus, MP4/AV1, MOV/ProRes, TS/H.264, 10-bit HEVC, MKV+PGS, MKV+ASS, MKV+FLAC) plays with video and audio on **both** Windows and Android with hardware decode where available; the same ASS test file renders with identical positioning and styling on both.
3. **A ticket is never wasted.** Re-opening a file whose subtitle was already fetched costs **0** downloads (cache + sidecar hit rate 100 %); the app never downloads more than **1** subtitle per open without an explicit tap; the ticket strip always shows the true `remaining` from the last API response.
4. **Honest loading.** The leader never advances past a phase that has not resolved; a failure stalls the numeral and shows one sentence with the next action (filename search → Subdl → manual → skip) within **500 ms** of the failure.
5. **Fast to the picture.** Cold start to the Lobby < **1.5 s** on Windows and < **2.5 s** on a mid-range Android phone; open → first frame < **1.5 s** for a local 1080p file; controls, gate drag and sync rule run at **60 fps**; the beam shader costs ≤ **2 ms**/frame at its DPR cap.
6. **Usable in the dark.** Every control reachable by keyboard on Windows (cue sheet lists all shortcuts) and by thumb on Android (≥ 44 × 44 px, the gate 56 px); every text token ≥ 4.5 : 1 on its allowed surface; `prefers-reduced-motion` honoured (leader still stalls honestly).
7. **Marquee Lite is honest.** A dropped MP4/H.264 or WebM plays with subtitles within **3 s**; an unplayable file shows the No Print card with container and codec names and the reason ("This browser has no AC-3 decoder") within **1 s** — never a silent black rectangle.
8. **Release is one command.** `git tag v1.0.0 && git push --tags` → Windows x64 zip + arm64-v8a APK (+ armeabi-v7a, x86_64) on a GitHub Release with no manual step, in under **25 min**; the APK installs over the previous version.

## 6. Non-goals

- **No streaming, torrents, IPTV, DLNA/UPnP, Chromecast** in v1 (Chromecast is a "someday" line only). Marquee plays files you already have.
- **No media server, no accounts of our own, no cloud sync, no telemetry, no analytics.** Positions, hashes and subtitles stay on the device; the only network calls are OpenSubtitles (and, if the user opts in, Subdl and TMDB).
- **No transcoding, ever** (ffmpeg.wasm real-time transcoding is not viable; libmpv does not need it).
- **No Play Store / Microsoft Store listing, no code signing certificates, no paid anything.** Sideloaded APK and a zipped exe from GitHub Releases.
- **No LLM features** — identification is hash → filename grammar → TMDB `/find`; "smart" means deterministic. No subtitle translation, no AI summaries, no ML over TMDB data (their terms forbid it anyway).
- **No scraping** of sites without an API (Addic7ed and friends). OpenSubtitles REST and Subdl only, through their documented endpoints.
- **No iOS/macOS/Linux builds** in the plan (Flutter could; not this project's scope).
- **No light theme during playback** — the Auditorium is dark-only by design (DESIGN.md §4 justification); Matinee exists for the Lobby, Booth and Ticket Office only.

## 7. Feature list

### MVP ✅ (the Weekend MVP in PLAN.md)
- Open a file by drag-drop, file picker, "Open with" (Android) or command-line argument (Windows); libmpv playback with hardware decode (`hwdec=auto-safe`), libass subtitle rendering, embedded audio/subtitle track switching.
- **Threading:** moviehash → OpenSubtitles hash search → best candidate by score → download → save as `<video>.<lang>.srt` beside the file (or app storage on Android without a folder grant) → attach; sidecar `.srt`/`.ass` detection first; filename-parse fallback (`BY NAME · CHECK SYNC`); manual search; skip.
- Leader 3-2-1 as the real progress indicator with honest stalls; ticket strip with true `remaining`; 429/406/401 handled as sentences.
- Ticket Office: OpenSubtitles sign-in (JWT in secure storage, password never kept), preferred languages (up to 3), hearing-impaired preference, "save beside file".
- Auditorium: auto-hiding controls (2400 ms), folio (reel · timecode · remaining), film-gate seek (timecode-only), ±10 s, play/pause, CC/audio track pickers, fullscreen, sync rule (J/K, ±50 ms detents) written to mpv `sub-delay` and remembered per moviehash, full keyboard cue sheet on Windows.
- Windows: frameless window, marquee title bar with drag; Android: edge-to-edge, immersive playback, keep-screen-on, predictive back.
- CI: `flutter analyze` + tests on push; on tag → Windows zip + split-per-ABI signed APKs on a GitHub Release; Marquee Lite on GitHub Pages; Worker on Cloudflare.
- **Marquee Lite:** drop → `<video>` → hash → Worker → `.srt` → VTT `<track>`; `.ass` via JASSUB; capability line from `canPlayType`; No Print card; session + subtitle cache in IndexedDB; installable PWA shell.

### v1 🚀
- **Lobby:** library rail from user-chosen folders (Windows) / MediaStore (Android) in drift, resume sprocket track, `PRINT MISSING` state, `±` sync badge, `EN ✓` chip, long-press context; marquee warm-up spelling the identified title; sky band by local time; Matinee palette for the Lobby/Booth/Ticket Office.
- **House lights down / up** (`--house` 0–1, 900 ms), beam fragment shader (Impeller on native, GLSL ES via OGL on web) with static fallback, lobby grain, room tone.
- **Bias light** (wall glow from `player.screenshot` every 500 ms desktop / opt-in 1000 ms Android; `requestVideoFrameCallback` on web).
- **Film gate** with thumbnail strip, chapter detents (mpv `chapter-list`, else every 5 min), FINE mode (drag up, 1/8 speed), spring snap, first-run nudge.
- **Subtitle Booth** sheet: external/embedded/off tracks, size S/M/L, outline, position, sync rule, "Find another print", ticket count.
- Speed (`[`/`]`) with pitch correction, frame-step (`,`/`.`), A–B loop (desktop), PiP (Android), gestures (double-tap ∓10 s, long-press 2×, edge dimmers for brightness/volume, horizontal scrub, pinch fit/fill).
- **Subdl slot** (user's own free key; anonymous zip download) as the fallback when OpenSubtitles has nothing or the quota is out; TMDB posters/backdrops with BYO key or CI-injected read token (logo + notice, cache ≤ 6 months).
- Sounds (synthesised sweep, 2-pop, detent; CC0 projector loop and paper rip) and haptics, each behind one bulb; reduced-motion pass.
- Search-result cache (24 h) and download cache keyed by moviehash + language; quota guard that refuses to spend a ticket when `remaining == 0`.
- Marquee Lite: File System Access "library" on Chromium desktop; JASSUB threaded path when hosted with COOP/COEP (Workers static assets escape hatch).

### Someday 🔮
- Audio-based automatic sync (ffsubsync-style cross-correlation of speech energy vs. cue timing) — procedural, no ML models.
- Anime4K / FSRCNNX `glsl-shaders` presets and `interpolation`/`tscale` in the Ticket Office (Windows); HDR tone-mapping controls.
- Windows `libmpv-2.dll` refresh step in CI from zhongfly's LGPL builds (after the empirical drop-in test).
- "Indic subtitles" font pack download (Noto Sans Devanagari/Tamil) for libass on Android.
- Marquee Lite WebCodecs path (`movi-player` / `mediabunny`) for MKV/HEVC/AC-3 in Chromium/Safari.
- Playlists, "play next in folder", chapters editor, Rive wordmark, Inno Setup installer with file associations, Chromecast, Linux/macOS builds.

## 8. Platforms

| Tier | Target | Engine | Built by | Distributed as |
|---|---|---|---|---|
| Native | **Windows 11 x64** | Flutter 3.47.x + media_kit (libmpv, D3D11VA) | GitHub Actions `windows-latest` | zip on GitHub Releases |
| Native | **Android 8.0+ (minSdk 26), arm64-v8a primary** | Flutter + media_kit (libmpv, MediaCodec) | GitHub Actions `ubuntu-24.04` | signed split-per-ABI APKs on GitHub Releases, sideloaded |
| Web | **Marquee Lite** — evergreen Chromium/Firefox/Safari, phone and desktop | HTML5 `<video>` + JASSUB (+ optional WebCodecs) | GitHub Actions → GitHub Pages | `https://<owner>.github.io/marquee/` (installable PWA) |
| Proxy | Cloudflare Worker (Free) | — | GitHub Actions → `wrangler deploy` | `https://marquee-proxy.<subdomain>.workers.dev` |

The owner's machine needs no Java or Android SDK. For the Windows dev loop only, Flutter SDK + Visual Studio 2022 Build Tools (C++ workload) are installed locally — the one exception allowed by `_shared/GETTING-STARTED.md`; a CI-only path exists too (README Quickstart).

## 9. Constraints

- **Free.** GitHub (public repo, Pages, Actions, Releases), Cloudflare Workers Free (100k req/day, hard-fails, never bills), OpenSubtitles free consumer key + free user account, Subdl free key (user's own), TMDB free non-commercial key. Nothing asks for a card; if something does, stop (DECISIONS §D9.5).
- **Offline-first.** Playback, library, resume, sync memory, sidecar subtitles and previously fetched subtitles work with no network; only search/download need it, and the leader stalls honestly when offline.
- **Privacy.** No analytics, no telemetry, no crash reporting, no accounts of our own. Only the moviehash, file size, filename-derived query and the user's OpenSubtitles JWT leave the device — to OpenSubtitles (directly from native builds; via the Worker from Lite). The Worker logs nothing and stores nothing.
- **Licences.** App code MIT. Native libraries are LGPL (`media_kit` default Android flavour: ffmpeg `--disable-gpl --enable-version3`, mpv `-Dgpl=false`; Windows DLL from `libmpv-win32-video-cmake`, same flags) — dynamically linked, licence texts and build-script links shipped in the Ticket Office. Never the `encoders-gpl` Android flavour, never a non-`lgpl` zhongfly Windows package. Fonts OFL 1.1 (Big Shoulders Display, Geist, Geist Mono, Noto Sans). Icons Lucide (ISC). Sounds CC0. `parse-torrent-title` (MIT) ported to Dart instead of `guessit-js` (LGPL-3.0). TMDB: non-commercial, logo + notice, cache ≤ 6 months, no ML. OpenSubtitles: "Subtitles by OpenSubtitles.com" credit line in the Lobby and Ticket Office.
- **Secrets.** OpenSubtitles consumer key: `wrangler secret` for the Worker; `--dart-define` from a repo secret for native builds (semi-secret, rotate if abused); never in git, never in `VITE_*`. Keystore: PKCS12 from `_shared/scripts/make-keystore.sh marquee`, backed up, base64 in a repo secret.
- **Design contract.** `design/preview.html` and DESIGN.md are binding: HOUSE LIGHTS tokens, Big Shoulders Display / Geist / Geist Mono, one accent per screen, no spinners, no red banners.

## 10. The one-sentence pitch

**Marquee is a cinema that dims for you: drop any film on Windows or Android, and by the time the leader counts 3-2-1 it has been fingerprinted, its subtitles found and threaded, and the walls are already glowing with its colour.**
