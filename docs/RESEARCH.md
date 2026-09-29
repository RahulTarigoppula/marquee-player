# Marquee — Research Dossier

**Project:** The No-Hassle Smart Media Player (codename *Marquee*)
**Folder:** `C:/Work/Personal_Projects/08-marquee-media-player`
**Date:** 2026-09-06
**Targets:** Windows desktop app + Android APK (real native-capable player) + mandatory web player (browser-supported codecs)

Confidence legend used throughout: **verified** = read from the primary source (official docs, repo README, package registry) during this research; **likely** = from a secondary source or a search summary; **unsure** = memory or inference, must be checked before relying on it.

---

## 1. Summary & feasibility

**Feasibility: 4 / 5.** Everything required exists, is free, and is open source. The two hard parts — "play ANY codec on Windows + Android from one codebase" and "identify the file and fetch synced subtitles" — are both solved problems with mature building blocks:

- **Playback:** `libmpv` (mpv's embeddable core, ffmpeg-backed, libass inside) is the only engine in the candidate list that gives *identical* codec/container/subtitle coverage on Windows and Android. Flutter's `media_kit` ships prebuilt libmpv for both platforms under an MIT wrapper, and real apps (Kazumi, Mangayomi, Fladder) already ship Windows `.exe` + Android APK from GitHub Actions with it.
- **Identification:** the OpenSubtitles *moviehash* (file size + 64-bit sum of first and last 64 KiB) needs only 128 KiB of I/O, works on a `File` in the browser and on a `RandomAccessFile` in Dart, and a hash hit on OpenSubtitles.com means the subtitle was uploaded for *that exact release*, i.e. it is already in sync. Fallbacks (filename parsing → title/year/S/E → IMDB/TMDB id) are procedural, no LLM needed.
- **Web player:** browsers only natively play H.264/AAC MP4, WebM (VP8/VP9/AV1/Opus) and (Chromium/Safari with hardware) HEVC. Anything else (MKV with AC-3/DTS, HEVC on Firefox) needs a WASM demuxer + WebCodecs path. Libraries for that exist in 2026 (`mediabunny`, `movi-player`) but they are young; the web tier should be scoped as "browser-supported codecs, plus best-effort MKV/HEVC".

What costs the point: (a) the owner has no Visual Studio / Android SDK locally, so a native stack needs the free **VS 2022 Build Tools (C++ workload)** for the Windows dev loop and relies on CI for the APK; (b) OpenSubtitles' free download quota is small (5/day anonymous per IP; 20/day with a free account per the "About the API" help article, while the "Getting started" article says "from 10 for regular users to 1000 for VIP" — plan the UX around **10** as the floor), which forces careful caching and "download only the best candidate" UX; (c) the web tier can never truly be "any codec".

**Recommendation in one line:** Flutter + `media_kit` (libmpv) for Windows + Android from a single Dart codebase, `PlayerConfiguration(libass: true)` for ASS/SSA, OpenSubtitles.com REST API (hash-first) with per-user login and an optional Subdl fallback, a separate Vite/TypeScript web player on Cloudflare Pages with a Cloudflare Worker proxy holding the API key, and a two-job GitHub Actions release workflow (windows-latest → zip/Inno installer, ubuntu-latest → split-per-ABI APKs) publishing to GitHub Releases.

---

## 2. Recommended stack

| Layer | Choice | Why | Alternatives considered |
|---|---|---|---|
| Windows + Android app | **Flutter (stable, ≥3.38) + `media_kit` 1.2.6 / `media_kit_video` 2.0.1 / `media_kit_libs_video` 1.0.7** — libmpv on both platforms, MIT wrapper ([pub.dev](https://pub.dev/packages/media_kit), [repo](https://github.com/media-kit/media-kit)) | Only stack where Windows and Android share the *same* engine (mpv → ffmpeg + libass), so codec and subtitle behaviour is identical; hardware decode via D3D11VA (Windows) and MediaCodec (Android); shipped by real apps; single UI codebase; Flutter's rendering (Impeller, fragment shaders) supports the "premium visuals" bar | Tauri 2 (two different engines, Android player is a separate Activity), Compose Multiplatform + mediamp (mpv on desktop, ExoPlayer on Android → subtitle/codec parity gap, needs JDK locally), React Native (no Windows in `react-native-video`), Electron (no Android; `mpv.js` is dead) — see §5 |
| Subtitle rendering (native) | **libass inside libmpv** via `PlayerConfiguration(libass: true, libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf', libassAndroidFontName: 'Noto Sans')` (verified field names, [source](https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit/lib/src/player/platform_player.dart)) | Full ASS/SSA typesetting; SRT/VTT also fine; Flutter-widget subtitle mode remains as fallback for styling-free SRT | Flutter `SubtitleView` widget (default; no ASS) |
| Subtitle search | **OpenSubtitles.com REST API v1** (`https://api.opensubtitles.com/api/v1`), hash-first, free API consumer key + optional per-user login (JWT) | Only major provider with hash search and a documented, key-based, free API | Subdl (free key, no hash, 2,000 req/day), Podnapisi/Addic7ed (no official API), SubDB (dead) — see §3 |
| Metadata/posters | **TMDB API v3** (free non-commercial key/read token; logo attribution mandatory) — optional, BYO key or proxied | Posters, backdrops, titles from IMDB/TMDB ids that OpenSubtitles already returns | OMDb (free tier 1,000/day, key by email) — not needed |
| Web player | **Vite + TypeScript** static app on **Cloudflare Pages** (or GitHub Pages). Fast path `<video>` + `<input type="file">`/drag-drop + `URL.createObjectURL`; ASS via **JASSUB** 2.5.16; SRT → WebVTT `<track>`; stretch: **mediabunny** (MPL-2.0) or **movi-player** (Apache-2.0) WebCodecs path for MKV/HEVC/AC-3 | 100% client-side, no build server, free hosting; codec reach is a browser property, so scope it honestly | Flutter Web build of the same app (uses HTML5 `<video>`, worse text/UI on web, larger bundle) — not recommended |
| Proxy (web only) | **Cloudflare Worker** (free: 100k req/day) that injects `Api-Key` + `User-Agent` for OpenSubtitles (and optionally TMDB), forwards the user's `Authorization: Bearer` JWT, enforces an `Origin` allowlist | Browsers cannot safely hold the API consumer key; Worker is free with no card | Vercel/Netlify functions (equivalent) |
| CI/CD | **GitHub Actions**: `windows-latest` job → `flutter build windows --release` → zip (+ optional Inno Setup via `inno_bundle`); `ubuntu-latest` job → `actions/setup-java@v4` (Temurin 17) + `subosito/flutter-action@v2` → `flutter build apk --release --split-per-abi`; `ncipollo/release-action@v1` attaches artifacts to a GitHub Release (pattern verified in [Mangayomi's release.yml](https://raw.githubusercontent.com/kodjodevf/mangayomi/main/.github/workflows/release.yml)) | Owner has no Java/Android SDK locally; all free on public repos | — |
| Local dev prerequisites | Flutter SDK + **Visual Studio 2022 Build Tools with "Desktop development with C++"** (free) for `flutter run -d windows`; Android is CI-only (install APK from Releases) | Unavoidable for any native Windows toolchain (Tauri needs MSVC too) | — |
| Licensing posture | App code can be **MIT or Apache-2.0** (GPL is *not* forced): the native builds media_kit ships on **both** platforms are LGPL — Android `default`/`full` flavours build ffmpeg with `--disable-gpl --enable-version3` (→ LGPL-3.0) and mpv with `-Dgpl=false` (→ LGPL-2.1+) ([flavors/default.sh](https://raw.githubusercontent.com/media-kit/libmpv-android-video-build/main/buildscripts/flavors/default.sh), [scripts/mpv.sh](https://raw.githubusercontent.com/media-kit/libmpv-android-video-build/main/buildscripts/scripts/mpv.sh)); the Windows DLL comes from [media-kit/libmpv-win32-video-cmake](https://github.com/media-kit/libmpv-win32-video-cmake) whose `packages/ffmpeg.cmake` is `--disable-gpl --disable-nonfree --enable-version3` and `packages/mpv.cmake` is `-Dgpl=false`. **Avoid the `encoders-gpl` Android flavour** (`--enable-gpl --enable-libx264`, GPLv3) and, if you ever swap the Windows DLL, use zhongfly's `mpv-dev-lgpl-*` package, not the plain (GPL) one. LGPL obligations: ship the licence texts, keep libmpv dynamically linked (it is), point to the build-script repos for source | mpv can be LGPLv2.1+ with `-Dgpl=false`, but "linked libraries still can affect the final license (for example if FFmpeg was built as GPL)" ([mpv Copyright](https://github.com/mpv-player/mpv/blob/master/Copyright)) — verified not to be the case for media_kit's default builds | GPL-3.0 for the app is still fine if you prefer it |

---

## 3. Data sources & APIs

| Name | URL | License / terms | Free tier & limits | Purpose in Marquee | Confidence |
|---|---|---|---|---|---|
| OpenSubtitles.com REST API | `https://api.opensubtitles.com/api/v1` (VIP users get `vip-api.opensubtitles.com` via `base_url` in login response); docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api ; help: https://opensubtitles.tawk.help/article/getting-started | Free for everyone; key created in profile → "API Consumers"; `Api-Key` + descriptive `User-Agent` headers mandatory on every request; free/VIP/professional tiers; keep key secret (docs say treat as credential) | **Search: unlimited** (subject to rate limiting: watch `X-RateLimit-Limit/Remaining/Reset`, `Retry-After` on 429). **Downloads: anonymous 5 / 24 h / IP; free registered user 20 / day ("About the API" article) or "from 10 for regular users" ("Getting started" article — the two help pages disagree; budget for 10); VIP up to 1000 / day.** Per-second cap: **unverified** — the Stoplight docs are a JS app and no reachable help article states a figure; treat the "~5 req/s" number as a guess and rely on `X-RateLimit-*`/`Retry-After` at runtime. Download `link`s are temporary (Bazarr's provider treats HTTP 410 as "Download link has expired"); the validity window is **unverified**. **CORS (probed 2026-09-06):** responses carry `Access-Control-Allow-Origin: *`, but an `OPTIONS` preflight returns **403 with no `Access-Control-Allow-Headers`**, so a browser cannot send the custom `Api-Key` header directly — the Worker proxy is mandatory, not optional | Hash search, filename/IMDB/TMDB search, download `.srt`; returns `feature_details` with `imdb_id`/`tmdb_id` for free metadata linkage | verified (tiers, headers, key process, anon 5/day, CORS-preflight failure) / likely (20/day) / unverified (per-second cap, link TTL) |
| OpenSubtitles moviehash spec + reference code | https://opensubtitles.github.io/oshash/ and https://opensubtitles.stoplight.io/docs/opensubtitles-api/4wccbf76rim38-hash-source-codes | Public algorithm; reference implementations MIT/public | n/a (client-side) | File identification; `hash = size + Σ le_u64(first 64 KiB) + Σ le_u64(last 64 KiB)` mod 2^64, 16 lowercase hex chars, file must be ≥ 128 KiB; test vector `breakdance.avi → 8e245d9679d31e12` | verified |
| OpenSubtitles.org XML-RPC (legacy) | `api.opensubtitles.org/xml-rpc` | Superseded by the REST API ("replaces the older XML-RPC system") | — | **Do not build on it.** Exact shutdown date not confirmable (forum returned 403) | likely deprecated / unsure on date |
| Subdl API | Docs: https://subdl.com/api-doc ; search `GET https://api.subdl.com/api/v1/subtitles?api_key=…&file_name=…|imdb_id=…|tmdb_id=…&languages=EN,FR&type=movie|tv&season_number=&episode_number=&year=`; download `https://dl.subdl.com/subtitle/{url}` (zip) | Free key from account panel; terms (https://subdl.com/terms): follow rate limits, no reselling, may throttle/revoke; no attribution clause found | **2,000 API requests/day (free key); downloads are 300/day/IP and must be made *anonymously* (no `api_key` on the `dl.subdl.com` link) — a free key carries no download quota; only Pro (30,000 req/day) gets 2,000 key-authenticated downloads/day** ([api-doc](https://subdl.com/api-doc)) | Fallback provider when OpenSubtitles quota is exhausted or no hash hit. **No hash search** — `film_name`/`file_name`/`imdb_id`/`tmdb_id`/`sd_id` only | verified |
| Podnapisi | https://www.podnapisi.net | No official public API; `subliminal` uses undocumented JSON/XML search endpoints without a key | none documented | Optional third fallback; fragile (undocumented) | likely |
| Addic7ed | https://www.addic7ed.com | No API; site ToS forbids automated access; `subliminal` scrapes it (and there is a third-party proxy "Gestdown" whose current status I could not confirm — 404 on `api.gestdown.info`) | — | **Skip** for legality/robustness | verified (no API) / unsure (Gestdown) |
| SubDB (thesubdb.com) | — | Service offline for years | — | **Dead; do not plan on it** | likely |
| BSPlayer subtitle API | undocumented SOAP, hash-based (used by subliminal) | unofficial | none documented | Optional; fragile | likely |
| TMDB API v3 | `https://api.themoviedb.org/3`; images `https://image.tmdb.org/t/p/{w342|w500|w780|original}{poster_path}`; `GET /find/{imdb_id}?external_source=imdb_id` → `movie_results`/`tv_results`/`tv_episode_results` (verified). Terms: https://www.themoviedb.org/api-terms-of-use | Free for **non-commercial** use; must show TMDB logo + notice "This product uses the TMDB API but is not endorsed or certified by TMDB"; **no caching > 6 months; no AI/ML use of TMDB content**; commercial use needs written agreement | Free key or "API Read Access Token" (Bearer) from account settings; no published hard limit, "somewhere in the 40 req/s range", respect 429 | Posters/backdrops/overview for the "cinematic" library; resolve IMDB id → TMDB id | verified |
| OpenSubtitles `GET /utilities/guessit?filename=…` | same base URL | same as API | counts as a request | Server-side filename parsing (guessit) so the Dart app needs no parser | **unverified** — the Kong gateway answers 403 "You cannot consume this service" for *both* this route and a made-up route when no valid key is sent, so existence could not be confirmed without a key; confirm with your key on day 1. Documented alternative: OpenSubtitles hosts `https://guessit.opensubtitles.com/api/guessit?filename=…` (guessit-js README: CORS-enabled, batch POST up to 500, but "for testing and evaluation only — never use in production") |
| Google Fonts (Noto Sans etc.) | https://fonts.google.com | SIL OFL 1.1 | free | Bundled `.ttf` for libass on Android (`libassAndroidFont`) and app typography | verified (OFL is well known) |

**Legality note.** Downloading user-contributed subtitles for personal viewing through official APIs (OpenSubtitles, Subdl) is the intended use of those services. Scraping sites that prohibit it (Addic7ed) is the only red flag; the design below never does that. Subtitles are derivative works of copyrighted scripts; the app fetches on the user's request and stores them locally next to the user's own media — same model as VLC's official OpenSubtitles extension (VLsub) and Kodi's official addon.

---

## 4. Key libraries

| Library | Package / URL | License | Purpose | Status (2026) |
|---|---|---|---|---|
| media_kit | `media_kit ^1.2.6`, `media_kit_video ^2.0.1`, `media_kit_libs_video ^1.0.7` — https://github.com/media-kit/media-kit | MIT (wrapper) | Playback engine on Windows/Android (libmpv), texture rendering, subtitle tracks, `glsl-shaders`, screenshots | 1.2.6 published ~Jan 2026 (changelog 1.2.4–1.2.6: only "fix(windows): long file path support"); repo pushed 2026-08-30; libmpv-android build repo last pushed 2026-01-27, last *release* v1.1.7 (2024-10-04) — which is what `media_kit_libs_android_video` 1.3.8 pins in its `build.gradle` |
| media_kit native libs (Android) | `media_kit_libs_android_video 1.3.8` (pulled in by `media_kit_libs_video`) — https://github.com/media-kit/libmpv-android-video-build | MIT wrapper; native code **LGPL** for `default`/`full` (ffmpeg `--disable-gpl --enable-version3`, mpv `-Dgpl=false`, x264 not built); **GPLv3 for `encoders-gpl`** (`--enable-gpl --enable-libx264`). `build.gradle` downloads `default-{arm64-v8a,armeabi-v7a,x86_64,x86}.jar` from release v1.1.7 → the **`default` flavour is what you ship** (verified) | Prebuilt libmpv + ffmpeg (mediacodec, jni, dav1d) + libass, MediaCodec hwdec | last release Oct 2024, repo pushed Jan 2026 |
| media_kit native libs (Windows) | `media_kit_libs_windows_video 1.0.11` — the DLL is downloaded by its `CMakeLists.txt` from **https://github.com/media-kit/libmpv-win32-video-cmake** (fork of shinchiro/mpv-winbuild-cmake), release `20241021`, asset `mpv-dev-x86_64-20241021-git-0f78584.7z` (+ aarch64). The separately mentioned https://github.com/media-kit/libmpv-win32-video-build (fork of zhongfly/mpv-winbuild) is archived (2024-10-09) but is *not* the source of the shipped DLL | MIT wrapper; underlying build is **LGPL** (`--disable-gpl --disable-nonfree --enable-version3`, `-Dgpl=false`) | Prebuilt libmpv for Windows, D3D11VA hwdec, ANGLE texture | **frozen at mpv git 0f78584 / Oct 21 2024** (cmake repo not archived but no release since); mitigation in §8 |
| libass | inside libmpv — https://github.com/libass/libass | ISC | ASS/SSA rendering | actively maintained upstream |
| flutter_animate | `flutter_animate ^4.5.2` — https://pub.dev/packages/flutter_animate | BSD-3-Clause | Declarative animation chains, shimmer/blur/shader effects | Flutter Favorite (verified on pub.dev), 4.5.2 published ~Dec 2024 (21 months old, no newer release) |
| rive | `rive ^0.14.11` — https://pub.dev/packages/rive | MIT (runtime) | Vector/state-machine animations (logo, loading, gesture feedback) | 0.14.11 (Aug 2026) |
| flutter_acrylic | `flutter_acrylic ^1.1.4` — https://pub.dev/packages/flutter_acrylic | MIT | Windows Mica/Acrylic/transparent window materials | 1.1.4 (2 years old; still works on Win11, verify on latest Flutter) |
| window_manager | `window_manager` — https://pub.dev/packages/window_manager | MIT | Frameless window, custom title bar, fullscreen, always-on-top | 0.5.2 (~Jul 2026), verified publisher leanflutter.dev; note it is "being migrated to libnativeapi/nativeapi-flutter" — verified |
| google_fonts / bundled fonts | `google_fonts` | BSD-3 (fonts OFL) | Typography + libass Android font | maintained — likely |
| palette_generator | `palette_generator` 0.3.3+7 | BSD-3 (Flutter team) | Extract dominant colours from posters/frames for ambient UI | **DISCONTINUED** — pub.dev shows "This project has been discontinued, and will not receive further updates" (last publish ~16 months ago). It still compiles, but plan on `material_color_utilities` (`QuantizerCelebi` + `Score`, BSD-3, used by Flutter itself) or a 40-line own quantizer over `image` package pixels |
| Flutter fragment shaders | built-in (`FragmentProgram.fromAsset`) — https://docs.flutter.dev/ui/design/graphics/fragment-shaders | BSD-3 | Cinematic backdrops, glow, film grain; GLSL 100–460; Skia + Impeller; `ImageFilter.shader` Impeller-only | verified |
| Anime4K / FSRCNNX GLSL | https://github.com/bloc97/Anime4K (MIT) | MIT | mpv `glsl-shaders` upscaling on Windows (vo=gpu) | used by Kazumi — verified pattern |
| JASSUB | `jassub 2.5.16` — https://github.com/ThaUnknown/jassub | Mixed: LGPL-2.1+ (libass) AND FTL/GPL-2 (FreeType) AND MIT… (npm registry) | ASS/SSA in the browser (libass→WASM, WebGL, worker); COOP/COEP optional for threads | active |
| mediabunny | `mediabunny 1.55.x` — https://github.com/Vanilagy/mediabunny, docs https://mediabunny.dev | MPL-2.0 | Browser demux/decode (MP4, MOV, MKV, WebM, Ogg, MP3, WAV, AAC, FLAC, MPEG-TS, HLS); AVC/HEVC/VP9/AV1/ProRes via WebCodecs ("availability … depends on the browser"); AC-3/E-AC-3/DTS decode via extension packages; `BlobSource(file)` for local files | 1.55.7 published 2026-09-04, 7.1k stars, very active — verified |
| movi-player | `movi-player 0.4.0` (Aug 14 2026) — https://github.com/mrujjwalg/movi-player | Apache-2.0 | Drop-in `<movi-player>` web component: FFmpeg-WASM demux + WebCodecs (hardware) with **FFmpeg-WASM software fallback** for codecs the browser lacks; MP4/MKV/WebM/MOV/TS/AVI; H.264/HEVC/VP9/AV1/HDR; AAC/MP3/Opus/FLAC/AC-3/E-AC-3 (no DTS listed); SRT/ASS/VTT/PGS/DVB subs. README support matrix: Chrome 110+, Edge 110+, Safari 18+, Firefox 130+ (HDR "limited"); 4K capped at certain frame rates | 0.4.0 published 2026-08-14 (verified on npm); 48 stars, single maintainer, CHANGELOG shows 3 releases in Jul–Aug 2026 — young, exactly the "play anything in a browser" engine, but expect breaking changes |
| parse-torrent-title | `parse-torrent-title 3.0.1` (Apr 25 2026) — https://github.com/clement-escolano/parse-torrent-title | MIT | Filename → title/year/season/episode/resolution/codec/group (JS; small enough to port to Dart) | maintained |
| guessit-js | `guessit-js 4.7.1` (Aug 12 2026) — https://github.com/opensubtitles/guessit-js | **LGPL-3.0** | 100 %-compatible TypeScript port of Python guessit (50 properties), browser + WASM | maintained by OpenSubtitles; LGPL in a bundled web app is a licence gotcha → prefer parse-torrent-title or keep it as a separately loaded module |
| subliminal (reference only) | https://github.com/Diaoul/subliminal | MIT | Reference for provider adapters and subtitle *scoring* (hash > release group > resolution > source > codec…) | maintained |
| Drift (not Isar) | `drift` 2.34.4 (MIT, published Sep 2026) / `isar` 3.1.0+1 (Apache-2, **last stable 3 years ago**, 4.0.0-dev.14 prerelease only) | | Local library DB (files, hashes, watched position, cached subtitle metadata) | **use drift** — verified on pub.dev |
| Cloudflare Workers | https://workers.cloudflare.com | Free plan: 100,000 requests/day (resets 00:00 UTC, error 1027 when exceeded), 10 ms CPU per invocation, 100 Workers, 50 subrequests/request ([limits](https://developers.cloudflare.com/workers/platform/limits/)). "No credit card" is **not stated in the docs** — Cloudflare's billing page only says a payment method is required "to purchase" products; free-plan sign-up without a card is common experience, not a documented guarantee | Key-hiding proxy for the web player | verified (limits) / likely (no card) |

---

## 5. How the core problem is solved

### 5.1 Stack comparison for "play ANY codec on Windows + Android"

| Stack | Windows engine | Android engine | Same codec matrix on both? | ASS/SSA | Effort / verdict |
|---|---|---|---|---|---|
| **Flutter + media_kit** | libmpv (ffmpeg, libass), D3D11VA | libmpv (ffmpeg, libass), MediaCodec | **Yes** | libass both | One codebase, proven by Kazumi/Mangayomi/Fladder. **Recommended.** |
| Tauri 2 (+ `tauri-plugin-libmpv` MPL-2.0 / `tauri-plugin-mpv` IPC) | libmpv via window embedding (Windows tested; Linux embedding broken; macOS untested) | **No libmpv plugin.** `tauri-plugin-videoplayer` opens a *separate fullscreen media3 Activity* (Android-only, early stage) | No | Desktop yes; Android media3 limited | Shared web UI, but two players and the Android one is not embeddable in your UI. Fine for desktop-first; fails "seamless" on Android. |
| Compose Multiplatform + `open-ani/mediamp` 0.3.0 (Apache-2.0) | bundled **mpv** (VLC backend deprecated) | **ExoPlayer/media3** | No (AC-3/DTS need media3 ffmpeg extension; MKV fine) | Desktop "full rendering"; Android "WebVTT and basic SRT" only | Solid KMP option; needs JDK + Android toolchain for *any* local build (owner has none); subtitle parity gap on Android. Second choice. |
| Compose Multiplatform + `ComposeMediaPlayer` (MIT) | **Media Foundation** — README matrix: no AVI/MKV/FLV/WebM on Windows | media3 | No | SRT/VTT only (Compose-rendered) | Not "any codec". Reject. |
| React Native + `react-native-video` v6/v7 | **Windows not listed** as supported platform in README; RN-Windows itself mid-migration to Fabric/WinAppSDK | ExoPlayer/media3 | No | limited | Reject for this project. |
| Electron + `mpv.js` | `mpv.js` needs **PPAPI/Pepper**, removed from Chromium; targets Electron 1.7/2.x (2017-18); CC0 | **Electron has no Android** | — | — | Dead end. (IPTVnator's native-addon approach is macOS-only experimental.) |
| "Just embed mpv" | mpv `--wid` embedding or JSON IPC to an mpv process (works, ugly integration) | fork **mpv-android** (MIT, Kotlin, libmpv JNI) | Yes, but two apps | libass | Two codebases, two UIs. Only if you abandon single-codebase. |

Why libmpv wins on Android specifically: media3/ExoPlayer needs its ffmpeg extension (self-built) for AC-3/E-AC-3/DTS/TrueHD and renders SSA/ASS with "limited styling" (Just Player README); libmpv brings ffmpeg's full decoder set and libass with no extra work, and mpv-android proves MediaCodec hardware decoding + libass coexist on Android. The price is APK size (libmpv+ffmpeg ≈ 30–40 MB per ABI → `--split-per-abi`).

### 5.2 Identification → subtitles pipeline (procedural, no LLM)

```
open file
  ├─ 1. moviehash (128 KiB of I/O) + file size + filename
  ├─ 2. OpenSubtitles GET /subtitles?moviehash=H&languages=en&moviehash_match=include
  │       hit with attributes.moviehash_match == true  → pick best (download_count, hearing_impaired pref, fps)
  ├─ 3. else parse filename (parse-torrent-title port or /utilities/guessit)
  │       → title, year, season, episode → GET /subtitles?query=<title>&year=&season_number=&episode_number=
  │       (or GET /subtitles?query=<raw filename> — the API runs guessit server-side)
  ├─ 4. optional: TMDB /find/{imdb_id} for poster/backdrop (imdb_id/tmdb_id come back in feature_details)
  ├─ 5. POST /download {file_id, sub_format:"srt"} (+ user JWT) → link → save as <video>.<lang>.srt next to the file
  │       cache: hash → {file_id, lang, path}; never re-download; show "remaining" quota
  └─ 6. load: media_kit Player.setSubtitleTrack(SubtitleTrack.uri(path)) ; offer ±delay (mpv sub-delay) and
         Subdl fallback (file_name / imdb_id) when OpenSubtitles returns nothing or 406 quota
```

**Step 1 — hash (Dart, native only; use BigInt on Dart web):**

```dart
import 'dart:io';
import 'dart:typed_data';

Future<String> openSubtitlesHash(File file) async {
  const chunk = 65536;
  final size = await file.length();
  if (size < 2 * chunk) throw ArgumentError('file < 128 KiB: OpenSubtitles rejects it');
  final raf = await file.open();
  Future<int> sum(int offset) async {
    await raf.setPosition(offset);
    final bd = ByteData.sublistView(await raf.read(chunk));
    var s = 0;                       // Dart VM ints wrap at 64 bits — exactly what we want
    for (var i = 0; i < chunk; i += 8) s += bd.getUint64(i, Endian.little);
    return s;
  }
  final h = size + await sum(0) + await sum(size - chunk);
  await raf.close();
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
```

**Same in the browser (works with `<input type="file">` on every browser, mobile included):**

```ts
export async function osHash(file: File): Promise<string> {
  const CHUNK = 65536;
  if (file.size < 2 * CHUNK) throw new Error('file too small');
  const sum = async (b: Blob) => {
    const dv = new DataView(await b.arrayBuffer());
    let s = 0n;
    for (let i = 0; i < CHUNK; i += 8) s += dv.getBigUint64(i, true);
    return s;
  };
  const h = (BigInt(file.size) + (await sum(file.slice(0, CHUNK))) + (await sum(file.slice(file.size - CHUNK)))) & 0xffff_ffff_ffff_ffffn;
  return h.toString(16).padStart(16, '0');
}
```

**Step 2 — search request shape:**

```
GET https://api.opensubtitles.com/api/v1/subtitles?languages=en&moviehash=8e245d9679d31e12&moviehash_match=include&order_by=download_count
Api-Key: <consumer key>
User-Agent: Marquee v0.1.0
Accept: application/json
```
Response (abridged): `data[].attributes { language, download_count, fps, release, hearing_impaired, moviehash_match, files[{file_id, file_name}], feature_details{feature_type, imdb_id, tmdb_id, title, year, season_number, episode_number} }` plus `total_pages`, `total_count`, `page`. Docs advise ordering GET params alphabetically (cache friendliness).

**Step 5 — login + download:**

```
POST /api/v1/login   {"username":"…","password":"…"}   → {token, user{allowed_downloads, level, vip, user_id}, base_url}
POST /api/v1/download {"file_id": 1234567, "sub_format":"srt"}   Authorization: Bearer <token>
                     → {link, file_name, requests, remaining, message, reset_time, reset_time_utc}
```
The `link` is a temporary URL to the `.srt`; store the file, not the link. Anonymous downloads (no JWT) work but count against the 5/day/IP pool shared by everyone behind that IP — so the UX should offer "Sign in to OpenSubtitles (free, 20/day)" once. Never store the password; store only the JWT (it expires; re-login on 401).

**Best-candidate scoring (borrowed from subliminal):** hash match ≫ same release group ≫ same source (BluRay/WEB-DL) ≫ same resolution ≫ same video codec; then `download_count`, non-hearing-impaired unless requested, `fps` equals container fps (mpv exposes it). All fields come straight from OpenSubtitles' `attributes`.

### 5.3 Playback configuration (media_kit)

```dart
final player = Player(configuration: const PlayerConfiguration(
  libass: true,
  libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
  libassAndroidFontName: 'Noto Sans',
  bufferSize: 64 * 1024 * 1024,
  title: 'Marquee',
));
final controller = VideoController(player,
  configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true));
await player.open(Media(path));
await player.setSubtitleTrack(SubtitleTrack.uri(srtPath, title: 'English', language: 'en'));
// desktop extras through the mpv property API:
// (player.platform as NativePlayer).setProperty('glsl-shaders', 'shaders/Anime4K_Clamp_Highlights.glsl;...');
// (player.platform as NativePlayer).setProperty('sub-delay', '0.5');
```
Notes: Android hardware path is MediaCodec. **Verified in `media_kit_video`'s Android controller source:** the defaults are `vo=gpu`, `gpu-context=android`, `hwdec=auto-safe` (or `no` on emulators / when `enableHardwareAcceleration:false`), `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`, `sub-font-provider=none` — so the GPU renderer that libass needs is already the default; `vo=mediacodec_embed` is opt-in via `VideoControllerConfiguration(vo:)`. mpv's manual confirms why not to use it with subtitles: with `mediacodec_embed` "many of mpv's features (subtitle rendering, OSD/OSC, video filters, etc) are not available". When `libass:true` on Android, `media_kit` copies `libassAndroidFont` to the cache dir and sets `config=yes`, `sub-fonts-dir`, `sub-font=<libassAndroidFontName>`, `sub-ass=yes` (verified in `real.dart`) — the font *name* must match the TTF's internal family name. Battery/thermal cost of `vo=gpu` + libass on a real phone is **unverified** (issue #945 is only the question; its comment thread could not be fetched). Windows uses ANGLE/D3D11 textures; `glsl-shaders` work there.

### 5.4 Web player architecture

1. Input: `<input type="file" accept="video/*">` + drag-drop (universal). The **File System Access API** (`showOpenFilePicker`, directory handles persisted in IndexedDB for a "library") is **Chromium-desktop only (Chrome/Edge 105+, Opera 91+); Firefox, Safari, Chrome Android, Safari iOS: no** ([caniuse](https://caniuse.com/native-filesystem-api)) — use it as a progressive enhancement only.
2. Fast path: `video.src = URL.createObjectURL(file)`; check `video.canPlayType`/`MediaSource.isTypeSupported`. Natively OK: MP4/H.264/AAC everywhere; WebM VP8/VP9/AV1/Opus; HEVC only where the OS has a decoder (Windows Chromium needs the HEVC Video Extensions; Safari yes); MKV: Chrome plays some H.264 MKVs but multi-audio/HEVC/AV1 in MKV fail silently.
3. Slow path (stretch): `movi-player` web component or `mediabunny` (`BlobSource(file)` → demux → `VideoDecoder`/`AudioDecoder` → canvas + Web Audio). `VideoDecoder` exists in Chrome 94+, Safari 16.4+, Firefox 130+ (MDN browser-compat-data, verified); *which codecs* it exposes is per browser/OS — HEVC via WebCodecs in Chrome 107+/Edge/Safari 16.4+ comes from movi-player's author's write-up (secondary source), and Firefox's `<video>` HEVC support is Windows 134+ / macOS 136+ / Linux 137+ (MDN) but whether Firefox exposes HEVC through `VideoDecoder` is **unverified** — always gate on `VideoDecoder.isConfigSupported()`, and note movi-player falls back to FFmpeg-WASM software decode where WebCodecs lacks the codec. AC-3/E-AC-3 need software decoders (movi-player via FFmpeg-WASM; mediabunny via extension packages, which also cover DTS — movi-player does not list DTS). "Smooth 1080p MKV+HEVC+AC-3 from a local `File`" is therefore *plausible* on Chromium/Safari with hardware HEVC, but no benchmark was found — treat as a stretch goal to prototype, not a promise.
4. ffmpeg.wasm *transcoding* is not viable for real-time 1080p HEVC on average laptops (measurements cited in 2026 posts: a 2 s segment can take ~6 s on low-end CPUs). Reserve it for nothing; decode-only via WebCodecs is the right tool.
5. Subtitles: SRT → WebVTT conversion (10 lines of code) into a `<track>`; ASS via JASSUB on a canvas over the video (serve with COOP/COEP headers on Cloudflare Pages `_headers` to unlock the threaded fast path; falls back automatically without them).
6. OpenSubtitles through the Worker proxy (`/os/*` → `api.opensubtitles.com/api/v1/*`): the Worker adds `Api-Key`, `User-Agent`, forwards `Authorization`, checks `Origin`, and adds CORS headers. **Probed 2026-09-06:** `api.opensubtitles.com` returns `Access-Control-Allow-Origin: *` on GET responses, but a CORS **preflight `OPTIONS` gets HTTP 403 with no `Access-Control-Allow-Headers`/`Allow-Methods`**, and the custom `Api-Key` header always triggers a preflight — so direct browser calls fail; the proxy is required (also note the Worker must answer `OPTIONS` itself — the sketch below does not yet). Two more gateway behaviours seen: unsorted query strings get a `301` to the alphabetically-sorted canonical URL (so sort params client-side as the docs advise), and the canonical redirect *drops* `moviehash_match=include` while keeping unknown params, i.e. `include` is the default value.

```ts
// worker.ts (Cloudflare) — sketch
export default {
  async fetch(req: Request, env: { OS_API_KEY: string }) {
    const u = new URL(req.url);
    if (!u.pathname.startsWith('/os/')) return new Response('nope', { status: 404 });
    if (req.headers.get('Origin') !== 'https://marquee.pages.dev') return new Response('forbidden', { status: 403 });
    const h = new Headers({ 'Api-Key': env.OS_API_KEY, 'User-Agent': 'Marquee-Web v0.1.0',
                            'Accept': 'application/json', 'Content-Type': 'application/json' });
    const auth = req.headers.get('Authorization'); if (auth) h.set('Authorization', auth);
    const r = await fetch('https://api.opensubtitles.com/api/v1' + u.pathname.slice(3) + u.search,
                          { method: req.method, headers: h, body: req.method === 'POST' ? await req.text() : undefined });
    const out = new Response(r.body, r);
    out.headers.set('Access-Control-Allow-Origin', 'https://marquee.pages.dev');
    return out;
  }
};
```

### 5.5 CI: Windows exe + Android APK from GitHub Actions (owner installs only the APK)

```yaml
name: release
on: { push: { tags: ['v*'] } }
jobs:
  windows:
    runs-on: windows-latest            # has VS 2022 + C++ workload preinstalled
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: flutter build windows --release
      - run: Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath marquee-windows-x64.zip
      # optional installer: dart pub global activate inno_bundle && dart run inno_bundle:build --release
      - uses: actions/upload-artifact@v4
        with: { name: windows, path: marquee-windows-x64.zip }
  android:
    runs-on: ubuntu-latest             # Android SDK preinstalled on the runner image
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      # for updatable installs: decode $SIGNING_KEY_STORE_BASE64 → android/app/upload-keystore.jks + key.properties
      - run: flutter build apk --release --split-per-abi
      - uses: actions/upload-artifact@v4
        with: { name: android, path: build/app/outputs/flutter-apk/*.apk }
  publish:
    needs: [windows, android]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with: { path: dist, merge-multiple: true }
      - uses: ncipollo/release-action@v1
        with: { artifacts: "dist/*", generateReleaseNotes: true }
```
This mirrors Mangayomi's verified workflow (windows-latest + `inno_bundle`, ubuntu-latest + Temurin 17 + `flutter build apk --release --split-per-abi`, `ncipollo/release-action@v1`). **It is quoted verbatim as the *verified* pattern — do not copy the action pins from it.** Marquee's own workflows pin `actions/checkout@v7`, `actions/setup-node@v7`, `actions/setup-java@v6` and `softprops/action-gh-release@v3` per DECISIONS D3 — see DEPLOYMENT §7.2 and IMPLEMENTATION-PROMPT §11.4 for the workflows that actually ship. What survives from this quote is the *shape* (two build jobs + a publish job, Temurin **17**, `--split-per-abi`), not the versions. Sign the APK with a keystore kept in repository secrets so updates install over the previous version; unsigned-debug APKs would require uninstall/reinstall.

---

## 6. Reference projects

| Project | Link | Why it matters |
|---|---|---|
| Kazumi (GPL-3.0) | https://github.com/Predidit/Kazumi | Flutter + media_kit, Windows 10+ / Android 10+ / macOS / iOS / Linux; **ASS via libass**, **Anime4K via mpv glsl-shaders**, danmaku overlay; GitHub Actions releases; Windows code-signing via SignPath. Closest architectural twin. |
| Mangayomi (Apache-2.0) | https://github.com/kodjodevf/mangayomi | Flutter + Rust; **release.yml** is the exact Windows exe (Inno Setup + zip) / Android split-ABI APK / `ncipollo/release-action` pipeline to copy. |
| Fladder (GPL-3.0) | https://github.com/DonutWare/Fladder | Flutter Jellyfin client on Android/iOS/Windows/macOS/Linux/Web with GitHub Actions builds — proves the six-platform Flutter story in a media app. |
| mpv-android (MIT) | https://github.com/mpv-android/mpv-android | Reference Android libmpv build scripts (ffmpeg + libass + MediaCodec hwdec), Kotlin JNI surface (`MPVLib.kt`, `BaseMPVView.kt`); Play/F-Droid/APK. |
| Just (Video) Player (Unlicense) | https://github.com/moneytoo/Player | Android media3 + ffmpeg-extension baseline: shows what ExoPlayer needs to reach AC-3/DTS/TrueHD and that its SSA/ASS is "limited styling" — the reason to prefer libmpv. |
| subliminal (MIT) | https://github.com/Diaoul/subliminal | Provider adapters (`opensubtitlescom.py`, `podnapisi.py`, `addic7ed.py`, `gestdown.py`, `bsplayer.py`, `napiprojekt.py`, `tvsubtitles.py`, `subtitulamos.py`) and the subtitle scoring model to port. |
| Movi Player (Apache-2.0) | https://github.com/mrujjwalg/movi-player | Browser "play anything" engine: FFmpeg-WASM demux + WebCodecs + WebGL2 + Web Audio, SRT/ASS/VTT/PGS/DVB subs, HDR. Blueprint (or dependency) for the web tier's slow path. |
| open-ani/mediamp (Apache-2.0) | https://github.com/open-ani/mediamp | Kotlin Multiplatform counter-proposal (mpv bundled on desktop, ExoPlayer on Android) — read to understand the parity gap. |
| tauri-plugin-libmpv (MPL-2.0) | https://github.com/nini22P/tauri-plugin-libmpv | If you ever go Tauri for desktop: window-embedding libmpv, Windows tested. |

---

## 7. Visual / design enablers ("best of the best")

**Native (Flutter):**
- **Impeller + custom fragment shaders** (`shaders/*.frag`, GLSL 460): animated cinematic backdrops, vignette/film-grain, glow behind the poster; `ImageFilter.shader` for backdrop blur (Impeller only). Verified supported on Windows and Android.
- **Ambient "bias light"**: every ~500 ms take `player.screenshot(format: 'image/jpeg')` (media_kit supports screenshots, including libass subs) → downscale → colour quantizer (`material_color_utilities`; `palette_generator` is discontinued) → animate a blurred radial gradient behind/around the video (YouTube-Ambient-mode look). Cheap and striking.
- **mpv `glsl-shaders`** (Anime4K MIT, FSRCNNX) for real upscaling on Windows; **`tscale`/interpolation** for smooth motion — settings VLC users never get in a nice UI.
- **flutter_animate** for auto-hiding controls, staggered library grids, shimmer skeletons; **rive** for a living logo and gesture feedback; **flutter_acrylic** Mica/Acrylic + **window_manager** frameless window with custom title bar on Windows 11.
- Typography: pair a display serif (e.g., *Instrument Serif* / *Fraunces*, OFL) with *Inter*/*Geist* (OFL/MIT); keep libass font separate (Noto Sans) for subtitle fidelity.
- Poster art from TMDB (`w780` backdrops, `w500` posters) with a colour quantizer (`material_color_utilities`, not the discontinued `palette_generator`) → per-title accent colour; remember the TMDB logo + notice requirement.
- Android: edge-to-edge, gesture volume/brightness/seek with haptics, PiP (`android:supportsPictureInPicture`).

**Web:**
- JASSUB for pixel-exact ASS; CSS `backdrop-filter` glass controls; WebGL (three.js, MIT) or a plain canvas 2D blur for ambient light sampled from the `<video>` frame via `requestVideoFrameCallback`; Motion One / GSAP (GSAP is now free of charge but not OSI — prefer Motion One, MIT) for control choreography; Lucide (ISC) icons; `view-transitions` for library → player.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Windows libmpv frozen at the 2024-10-21 build** (`media-kit/libmpv-win32-video-cmake` has had no release since; the zhongfly-fork repo is archived) → missing ~2 years of mpv/ffmpeg fixes | `media_kit` loads the DLL purely by file name (`libmpv-2.dll`, then `mpv-2.dll`, `mpv-1.dll`, or `LIBMPV_LIBRARY_PATH`) with **no version check** (verified in `native_library.dart`), and libmpv's client API is at 2.5 with the rule "additions bump the minor version, incompatible changes bump the major" (`client.h`), so a newer 2.x DLL *should* be a drop-in. **Not tested by anyone I could find — verify on day 1.** zhongfly/mpv-winbuild publishes daily `mpv-dev-x86_64-YYYYMMDD-git-*.7z` **and an LGPL variant `mpv-dev-lgpl-x86_64-*.7z`** (verified 2026-09-05 release) — use the `-lgpl` one to keep the licence posture; the plain package is a GPL build. Do the swap as a post-build CI step and keep the original DLL as a fallback artifact. |
| media_kit publishing cadence (last pub release ~Jan 2026, Flutter 3.38 supported) vs newer Flutter | Pin Flutter to the version media_kit's changelog names; upgrade deliberately. Kazumi/Mangayomi keep it alive. |
| Android ASS subtitles invisible in `mediacodec_embed` mode; fonts missing | Keep media_kit_video's defaults (`vo=gpu`, `hwdec=auto-safe`) — never set `vo: 'mediacodec_embed'` while libass is on (mpv manual: no subtitle rendering with that vo); ship Noto Sans and set `libassAndroidFont` + `libassAndroidFontName` (the internal family name, e.g. `Noto Sans`); test on a real device early — battery/thermals of the GPU path are unmeasured. |
| OpenSubtitles quota (5/day/IP anon; 10–20/day free login — the two help articles disagree) | Hash cache keyed by `moviehash+lang`; download a single best candidate; show remaining quota from the download response; one-time OpenSubtitles sign-in; Subdl fallback (300 downloads/day/IP, always anonymous — a free key adds search quota only); never auto-download in bulk library scans — only on play. |
| API consumer key embedded in a public Android/Windows app | It is standard (Kodi's official addon ships one) but treat as semi-secret: keep it out of git (inject via `--dart-define` from a repo secret at build time), rate-limit client-side, and rotate if abused. Web build never sees it (Worker). |
| OpenSubtitles CORS: preflight `OPTIONS` returns 403 (probed), so browsers cannot call the API with an `Api-Key` header | Always go through the Worker in the web tier; the Worker must handle `OPTIONS` and echo `Access-Control-Allow-Headers: authorization, content-type`. |
| TMDB terms: non-commercial, logo attribution, 6-month cache cap, no ML use | Keep the app free/OSS, show the TMDB logo + notice in About and library, expire cached metadata at ≤ 6 months, no LLM features over TMDB data. |
| Licence mixing: only the `encoders-gpl` Android flavour and zhongfly's non-`lgpl` Windows packages are GPL; media_kit's default Android and Windows builds are LGPL (verified from the build scripts) | Use the `default` flavour (what `media_kit_libs_android_video` pins) and the `-lgpl` zhongfly package if swapping; the app can stay MIT/Apache-2.0 — include LGPL notices + links to the build-script repos in About. GPL-3.0 for the app remains a valid choice, just not a forced one. |
| `guessit-js` is LGPL-3.0 | Use MIT `parse-torrent-title` (JS) / a Dart port of it, or OpenSubtitles' own `query=<filename>` server-side parsing. |
| Flutter Windows needs VS Build Tools locally (~7 GB) | One-time free install; Android stays CI-only. |
| APK size (libmpv+ffmpeg) | `--split-per-abi`; publish arm64-v8a as the primary asset. |
| Web tier cannot rely on AC-3/DTS/HEVC in Firefox (HEVC via `VideoDecoder` in Firefox unverified; DTS not in movi-player) | Detect with `canPlayType`/`VideoDecoder.isConfigSupported`, fall back to movi-player/mediabunny where possible, otherwise show "Open in Marquee desktop" with a clear codec message; brand the web tier as "Marquee Lite". |
| Filename-only matches may be out of sync | Show fps + release name, offer ±0.1 s/±0.5 s delay nudges (mpv `sub-delay`), remember per-file offset; later: automatic audio-based alignment (ffsubsync-style cross-correlation, procedural). |

---

## 9. MVP in a weekend vs full vision

**Weekend MVP (Windows first; APK from CI):**
1. `flutter create marquee` + media_kit; drag-drop/open file; frameless dark window; auto-hiding glass controls; keyboard shortcuts (space, ←/→, F, S for subtitles).
2. `openSubtitlesHash()` → `GET /subtitles?moviehash=…&languages=en` → auto-pick best → `POST /download` → save `.srt` beside the file → `setSubtitleTrack`. Fallback: `query=<filename>`.
3. Settings: OpenSubtitles sign-in (JWT stored in `flutter_secure_storage`), preferred languages, hearing-impaired toggle.
4. GitHub Actions release workflow from §5.5; install the arm64 APK on the phone.
5. Web: Vite + TS page on Cloudflare Pages: drop a file → `<video>` → hash → Worker → subtitle → VTT `<track>` (ASS via JASSUB).

**Full vision:**
- Library view scanning folders (Drift DB), TMDB posters/backdrops (expire cache ≤ 6 months per TMDB terms), watched progress, "continue watching", ambient bias-light, poster-derived accents (`material_color_utilities`), Rive micro-interactions, fragment-shader backdrops.
- Subtitle centre: multi-provider (OpenSubtitles → Subdl), scoring, multi-language, embedded track listing, PGS/DVB display (libmpv renders them), style editor for SRT (font/size/outline via mpv `sub-*` properties), per-file delay memory, optional audio-alignment auto-sync (procedural).
- Playback power: audio/subtitle track switcher, chapters, speed with pitch correction, A-B loop, frame step, deinterlace, `glsl-shaders` presets (Anime4K), HDR tone-mapping on Windows, gesture controls + PiP on Android, playlists, resume across devices via a simple export.
- Web "Lite": movi-player/mediabunny path for MKV/HEVC/AC-3, File System Access "library" on Chromium desktop, COOP/COEP-enabled JASSUB threading.
- No-LLM by design: identification is hash → filename grammar → TMDB `/find`; "smart" = deterministic. If an AI flavour is ever wanted (e.g., subtitle translation), OpenSubtitles offers paid AI translation; the free procedural alternative is simply fetching the target-language subtitle.

---

## 10. Open questions

1. Exact OpenSubtitles per-second rate limit and download-link expiry — still open after the 2026-09-06 check (Stoplight docs are a JS app; read them in a browser with your key). `moviehash_match` is recognised by the gateway and `include` is its default (canonical redirect drops it); `only` and `/utilities/guessit` could not be confirmed without a key — confirm both with your key on day 1.
2. Does OpenSubtitles require visible attribution (logo/link) for API consumers? Not found in the help centre; add a "Subtitles by OpenSubtitles.com" credit regardless.
3. Confirm *empirically* that media_kit's Windows `libmpv-2.dll` (client API from Oct 2024) can be swapped for a current zhongfly `mpv-dev-lgpl-x86_64-*.7z` build: the loader has no version check and the client API is 2.x-compatible on paper, but nobody has documented doing it.
4. ~~Which media_kit Android flavour does `media_kit_libs_video` pull by default and what is the ffmpeg licence?~~ **Answered 2026-09-06:** `default` flavour (build.gradle pins release v1.1.7 `default-*.jar`); ffmpeg is LGPL-3.0 (`--disable-gpl --enable-version3`), mpv `-Dgpl=false`. Remaining: what the `full` flavour adds over `default` (diff the two flavour scripts).
5. Real-device check: libass rendering with `hwdec=mediacodec-copy` on a mid-range Android phone (battery/thermals) vs `mediacodec_embed` without libass.
6. ~~Whether `api.opensubtitles.com` sets CORS headers~~ **Answered 2026-09-06:** `Access-Control-Allow-Origin: *` on responses but preflight `OPTIONS` → 403, so the Worker cannot be dropped.
7. Subdl: any hidden daily *download* limit for keyed users beyond the 2,000 requests/day, and stability of `dl.subdl.com` zip links.
8. Tauri 2 Android: any 2026 plugin that embeds libmpv or media3 *inside* the webview (would reopen the Tauri option).

---

## Sources (primary, fetched 2026-09-06)

- OpenSubtitles help — About the API: https://opensubtitles.tawk.help/article/about-the-api ; Getting started: https://opensubtitles.tawk.help/article/getting-started ; hash spec: https://opensubtitles.github.io/oshash/ ; API docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api ; apidog walkthrough (headers, rate-limit headers): https://apidog.com/blog/opensubtitles-api/
- Subdl API docs: https://subdl.com/api-doc ; terms: https://subdl.com/terms
- TMDB API terms: https://www.themoviedb.org/api-terms-of-use ; rate limiting: https://developer.themoviedb.org/docs/rate-limiting ; auth: https://developer.themoviedb.org/docs/authentication-application ; find-by-id: https://developer.themoviedb.org/reference/find-by-id
- media_kit: https://pub.dev/packages/media_kit ; changelog: https://pub.dev/packages/media_kit/changelog ; media_kit_video: https://pub.dev/packages/media_kit_video ; Android libs: https://pub.dev/packages/media_kit_libs_android_video , https://github.com/media-kit/libmpv-android-video-build ; Windows libs: https://pub.dev/packages/media_kit_libs_windows_video , https://github.com/media-kit/libmpv-win32-video-build ; PlayerConfiguration source: https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit/lib/src/player/platform_player.dart ; subtitle issue: https://github.com/media-kit/media-kit/issues/945
- mpv licensing: https://github.com/mpv-player/mpv/blob/master/Copyright ; mpv-android: https://github.com/mpv-android/mpv-android
- Tauri: https://v2.tauri.app/ ; https://github.com/nini22P/tauri-plugin-libmpv ; https://github.com/nini22P/tauri-plugin-mpv ; https://github.com/yeonv/tauri-plugin-videoplayer
- KMP: https://github.com/open-ani/mediamp ; https://github.com/kdroidFilter/ComposeMediaPlayer/blob/master/README_VIDEO.MD
- React Native: https://github.com/TheWidlarzGroup/react-native-video ; https://github.com/microsoft/react-native-windows
- Electron: https://github.com/Kagami/mpv.js
- Browser: https://github.com/ThaUnknown/jassub ; https://github.com/Vanilagy/mediabunny ; https://mediabunny.dev/guide/supported-formats-and-codecs ; https://github.com/mrujjwalg/movi-player ; https://dev.to/mrujjwalg/play-hevc-av1-and-mkv-in-the-browser-with-webcodecs-no-server-transcoding-57 ; https://caniuse.com/native-filesystem-api ; https://developer.mozilla.org/en-US/docs/Web/API/Window/showOpenFilePicker
- Filename parsing: https://github.com/opensubtitles/guessit-js ; https://www.npmjs.com/package/parse-torrent-title ; https://github.com/guessit-io/guessit
- Visuals: https://docs.flutter.dev/ui/design/graphics/fragment-shaders ; https://pub.dev/packages/flutter_animate ; https://pub.dev/packages/rive ; https://pub.dev/packages/flutter_acrylic
- CI: https://github.com/subosito/flutter-action ; https://raw.githubusercontent.com/kodjodevf/mangayomi/main/.github/workflows/release.yml
- Reference apps: https://github.com/Predidit/Kazumi ; https://github.com/kodjodevf/mangayomi ; https://github.com/DonutWare/Fladder ; https://github.com/moneytoo/Player ; https://github.com/Diaoul/subliminal


---

## Verification log (2026-09-06)

Adversarial fact-check pass. Method: primary sources only (help-centre articles, package registries, raw build scripts and source files, live `curl` probes against `api.opensubtitles.com`). GitHub's unauthenticated API hit its rate limit mid-check, and the Stoplight API docs are a JavaScript shell that cannot be fetched, so a few items stay **unverifiable** rather than confirmed.

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | OpenSubtitles free account ≈20 downloads/day; anonymous 5/day/IP | **Confirmed with a caveat** — anonymous 5/24 h/IP is stated on both help pages; free registered is "20 subtitles per day" on *About the API* but "from 10 for regular users to 1000 for VIP" on *Getting started*. Design for 10 as the floor. Search is stated to be unlimited. | https://opensubtitles.tawk.help/article/about-the-api ; https://opensubtitles.tawk.help/article/getting-started |
| 2 | ~5 req/s rate limit, download-link expiry, `moviehash_match=include`/`only`, `/utilities/guessit` | **Partly confirmed / partly unverifiable.** Per-second figure: no reachable primary source (help centre silent; Stoplight unreadable) → *unverified*, keep runtime `X-RateLimit-*`/`Retry-After` handling. Link expiry: exists (Bazarr treats HTTP 410 as "Download link has expired"), duration *unverified*. `moviehash_match`: gateway recognises it — the canonical-URL 301 strips `moviehash_match=include` but keeps unknown params (`foo=bar`), so `include` is the default; `only` returned 520/403 without a key → *unverified*. `/utilities/guessit`: Kong returns the same 403 "You cannot consume this service" for this route and for a made-up route without a key → *unverifiable without a key*; OpenSubtitles does host `guessit.opensubtitles.com/api/guessit` (testing only). | live probes 2026-09-06 (see §5.4 pt 6) ; https://raw.githubusercontent.com/morpheus65535/bazarr/master/custom_libs/subliminal_patch/providers/opensubtitlescom.py ; https://raw.githubusercontent.com/opensubtitles/guessit-js/main/README.md |
| 3 | Windows `libmpv-2.dll` can be swapped for a newer zhongfly build | **Plausible, not confirmed.** Corrected provenance: the shipped DLL is `mpv-dev-x86_64-20241021-git-0f78584.7z` from `media-kit/libmpv-win32-video-cmake` (fork of shinchiro/mpv-winbuild-cmake), not from the archived zhongfly fork. `native_library.dart` loads by file name with no version check; libmpv client API is 2.5 and minor bumps are additive (`client.h`). zhongfly publishes daily `mpv-dev-x86_64-*` and `mpv-dev-lgpl-x86_64-*` packages (2026-09-05 release seen). No report of anyone doing the swap with media_kit was found → test before relying on it. | https://raw.githubusercontent.com/media-kit/media-kit/main/libs/windows/media_kit_libs_windows_video/windows/CMakeLists.txt ; https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit/lib/src/player/native/core/native_library.dart ; https://raw.githubusercontent.com/mpv-player/mpv/master/include/mpv/client.h ; https://github.com/zhongfly/mpv-winbuild/releases |
| 4 | `media_kit_libs_video` pulls the MIT `default`/`full` Android flavour with LGPL ffmpeg, not `encoders-gpl` | **Confirmed and strengthened.** `media_kit_libs_video` 1.0.7 → `media_kit_libs_android_video` ^1.3.8 whose `build.gradle` downloads `default-<abi>.jar` from release v1.1.7. `flavors/default.sh` and `full.sh`: `--disable-gpl --enable-version3` (LGPL-3.0 ffmpeg); `scripts/mpv.sh`: `-Dgpl=false`; `encoders-gpl.sh`: `--enable-gpl --enable-libx264`. Bonus: the Windows cmake build is also `--disable-gpl --disable-nonfree --enable-version3` + `-Dgpl=false`. The app is therefore **not** forced to GPL. | https://pub.dev/packages/media_kit_libs_video ; https://raw.githubusercontent.com/media-kit/media-kit/main/libs/android/media_kit_libs_android_video/android/build.gradle ; https://raw.githubusercontent.com/media-kit/libmpv-android-video-build/main/buildscripts/flavors/default.sh ; https://raw.githubusercontent.com/media-kit/libmpv-win32-video-cmake/master/packages/ffmpeg.cmake |
| 5 | libass renders on Android with GPU vo + mediacodec-copy, acceptable battery | **Mechanism confirmed, performance unverifiable.** `media_kit_video`'s Android controller defaults to `vo=gpu`, `gpu-context=android`, `hwdec=auto-safe`, `sub-font-provider=none`; `real.dart` sets `config=yes`, `sub-fonts-dir`, `sub-font`, `sub-ass=yes` when `libass:true` + font asset. mpv manual: `mediacodec_embed` disables subtitle rendering. Issue #945 (opened 2024-09-05, "libass works on Windows, not on Android with libassAndroidFont") — comment thread could not be fetched (GitHub API rate-limited, HTML page did not render comments). No battery/thermal data anywhere. | https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit_video/lib/src/video_controller/android_video_controller/real.dart ; https://raw.githubusercontent.com/media-kit/media-kit/main/media_kit/lib/src/player/native/player/real.dart ; https://raw.githubusercontent.com/mpv-player/mpv/master/DOCS/man/vo.rst ; https://github.com/media-kit/media-kit/issues/945 |
| 6 | movi-player 0.4.0 / mediabunny 1.55 play MKV+HEVC+AC-3 smoothly; WebCodecs HEVC Chrome 107+/Edge/Safari 16.4+, not Firefox | **Versions confirmed; capability claim downgraded to "plausible".** npm: movi-player 0.4.0 (2026-08-14, Apache-2.0), mediabunny 1.55.7 (2026-09-04, MPL-2.0). movi-player README: MKV/HEVC/AC-3 supported, WebCodecs with FFmpeg-WASM software fallback, matrix Chrome 110+/Edge 110+/Safari 18+/Firefox 130+; no DTS. mediabunny docs: HEVC via WebCodecs "depends on the browser", AC-3/E-AC-3/DTS via extension packages. `VideoDecoder` availability: Chrome 94, Safari 16.4, Firefox 130 (MDN BCD). "HEVC in WebCodecs from Chrome 107" only found in the movi-player author's dev.to post (secondary). No smoothness benchmark exists; prototype before promising. | https://registry.npmjs.org/movi-player ; https://registry.npmjs.org/mediabunny ; https://raw.githubusercontent.com/mrujjwalg/movi-player/main/README.md ; https://mediabunny.dev/guide/supported-formats-and-codecs ; https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/VideoDecoder.json ; https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Video_codecs |
| 7 | TMDB free for non-commercial OSS with logo attribution; read token usable from a native app | **Confirmed (terms); token-in-app is not addressed by TMDB.** FAQ: "free to use for non-commercial purposes as long as you attribute TMDB"; commercial = "primary purpose is to create revenue". Terms: logo required and must be less prominent than yours, notice text "This product uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB", no caching > 6 months, no AI/ML training or use. Rate limit "somewhere in the 40 req/s range", respect 429. Nothing in the auth docs forbids or discusses embedding the read token in a client; treat it as semi-public like the OpenSubtitles key. | https://www.themoviedb.org/api-terms-of-use ; https://developer.themoviedb.org/docs/faq ; https://developer.themoviedb.org/docs/rate-limiting ; https://developer.themoviedb.org/docs/authentication-application |
| 8 | Browser need not call OpenSubtitles directly; Cloudflare Worker free tier (100k/day, no card) proxies it | **Confirmed, and the proxy is now *mandatory*.** Live probe: `Access-Control-Allow-Origin: *` on responses, but `OPTIONS` preflight → 403 without `Access-Control-Allow-Headers`, so the custom `Api-Key` header can never pass a browser preflight. Workers Free: 100,000 req/day, 10 ms CPU, 100 Workers, 50 subrequests (docs). "No credit card" is not written in Cloudflare's docs (billing page: payment method required "to purchase") → *likely* from experience, unverified in writing. | live `curl -X OPTIONS` probe 2026-09-06 ; https://developers.cloudflare.com/workers/platform/limits/ ; https://developers.cloudflare.com/fundamentals/subscriptions-and-billing/create-billing-profile/ |

**Whole-file scan results**

| Item | Verdict | Source |
|---|---|---|
| `palette_generator` "maintained — likely" | **Corrected: DISCONTINUED** (pub.dev banner). Replaced with `material_color_utilities` throughout. | https://pub.dev/packages/palette_generator |
| `isar` as a DB option | **Corrected:** last stable 3.1.0+1 is 3 years old (4.0.0-dev only) — use `drift` 2.34.4 (Sep 2026). | https://pub.dev/packages/isar ; https://pub.dev/packages/drift |
| Subdl "300 anonymous downloads/day/IP; 2,000 req/day" | **Corrected nuance:** a free key gives search requests only; downloads must be anonymous (300/IP); only Pro gets 2,000 key-authenticated downloads. | https://subdl.com/api-doc |
| media_kit dates ("repo updated May 2026", "libmpv-android build repo updated May 2026") | **Corrected:** media-kit repo pushed 2026-08-30; android build repo pushed 2026-01-27, last release v1.1.7 2024-10-04. | GitHub API `repos/media-kit/*` (before rate limit) |
| Windows libmpv provenance ("libmpv-win32-video-build, fork of zhongfly, archived Oct 9 2024") | **Corrected:** archive fact is true but the DLL actually comes from `libmpv-win32-video-cmake` release 20241021 (shinchiro-cmake fork, LGPL config). | CMakeLists.txt above |
| Licensing posture ("app GPL-3.0 to be safe") | **Corrected:** all shipped native builds are LGPL; MIT/Apache app licence is fine. | build scripts above |
| guessit-js LGPL-3.0, parse-torrent-title MIT 3.0.1, JASSUB 2.5.16 (mixed LGPL/FTL/MIT), rive 0.14.11 MIT, flutter_acrylic 1.1.4 (2 y old), flutter_animate 4.5.2 Flutter Favorite, window_manager MIT, inno_bundle exists (0.12.0), Kazumi/Fladder use media_kit, Mangayomi release.yml pattern (windows-latest + inno_bundle, ubuntu + Temurin 17 + split-per-abi) | **Confirmed** | npm registry ; pub.dev ; raw pubspec/README/workflow files |
| Flutter "stable ≥3.38" / "media_kit changelog names Flutter 3.38" | Current stable is 3.47.x; the 1.2.4–1.2.6 changelog entries mention no Flutter version → the "3.38" attribution is **unverified**; pin whatever Flutter version builds cleanly and keep it in CI. | https://docs.flutter.dev/release/archive ; https://pub.dev/packages/media_kit/changelog |
| "No API key needed" claims | None made for anything that needs one; moviehash and JASSUB are client-side. Cloudflare "no card" flagged above. | — |
| OpenSubtitles XML-RPC shutdown date, Gestdown status, Podnapisi/BSPlayer endpoints, OpenSubtitles attribution requirement, VIP 1000/day exactness | **Unverifiable this pass** (not reachable / not documented). VIP "1000" appears in the Getting-started article, so that one is *likely*. | — |
| AGPL / non-commercial gotchas | Only TMDB's non-commercial + no-AI terms and guessit-js's LGPL-3.0 (already flagged). No AGPL dependencies found. | — |
