# Changelog

All notable changes to Marquee are recorded here. Versions follow [SemVer](https://semver.org);
tags are `vX.Y.Z` and each one produces a GitHub Release (see `.github/workflows/release.yml`).

## [2.0.0] - 2026-11-26

### Added
- **Device library.** A Library tab beside Home: every video on the phone (MediaStore, by
  folder) or in the folders you add on Windows, with search, sort, thumbnails, resume bars,
  details, share / show in folder. Next and previous episode now work on Android too.
- **Picture controls:** rotate, zoom, brightness / contrast / saturation / gamma, deinterlace,
  beside the fit modes. **Sound:** voice / bass / treble / night profiles, loudness evening,
  inline audio delay. **Speed** up to 4× with a fine slider. **Repeat** one / folder.
- **Skip intro / recap / credits** from chapter titles. **Video details** overlay (`I`).
  **Keep on top** (`T`). A second subtitle track. Subtitle colour.
- **Seek preview** frame on the desktop seek bar; **swipe to seek**, pinch to fill, touch lock
  and picture-aware rotation on Android; audio focus (pauses for calls and unplugged
  headphones).
- **Per-film memory:** audio track, subtitle choice, picture adjustments.
- **Updates:** a private, opt-in check against GitHub Releases in Settings → About.
- **CI:** a real libmpv playback test on `windows-latest` (MKV / MP4 / HEVC, tracks, chapters,
  sidecar attach, resume through the real app); installer smoke test; `Marquee-Windows-Setup.exe`
  and `Marquee-Android.apk` on every release.

### Changed
- **A film never waits for subtitles.** When the automatic search stalls (offline, no key, no
  exact match, a timeout) the film starts and one sentence offers the Subtitle booth.
- **By-name search results are listed, not downloaded.** Only an exact fingerprint match is
  fetched without a tap; a typed or filename search shows rows to pick from, in the Booth,
  while the film keeps playing.
- Settings is split into sections with plain-language help; Back and Esc work there.
- The seek buttons and double-tap use the jump size you choose (5 / 10 / 15 / 30 s).

### Fixed
- Dead or unsupported links no longer show a black "playing" screen forever.
- Sidecar subtitles are no longer listed twice; "Play without subtitles" really turns them off.
- Android: "Export library" works; files of unknown size resume; "Open with" reuses the
  running app; "Load subtitle file" no longer shrinks the film into picture-in-picture.
- Windows: the window no longer restores off-screen or forgets it was maximised.
- An expired OpenSubtitles sign-in is dropped instead of stalling every search; signing in
  can no longer hang on "signing in".

## [1.1.0] - 2026-10-18

Playback fixes, overlay player, redesigned Lobby and Settings, installer, screenshot pipeline.
See docs/STATUS.md §5.

## [1.0.0]

### Added
- Flutter app for Windows + Android on media_kit/libmpv: Lobby, Threading leader, Auditorium
  (film gate, sync rule, keyboard cue sheet, bias light, gestures, PiP), Subtitle Booth, Ticket
  Office; zero-click hash-matched subtitles with sidecar + cache so a re-open costs no ticket.
- Pure-Dart engine with the §6 golden tables, OpenSubtitles + Subdl clients, drift database with
  export/import.
- Marquee Lite (`web/`): the same ritual in the browser through the Worker.
- `marquee-proxy` Cloudflare Worker (`worker/`): origin allow-list, server-side `Api-Key`, path
  allow-list, sorted query params, sign-in gate on `/download`, `/api/subtitle-file` with a
  streamed 2 MB cap, optional TMDB route, per-IP soft cap, no logging and no storage.
- CI (`ci.yml`), Pages, release, Worker deploy and nightly API contract workflows; Dependabot.
- Repo checks: Dart↔TS engine test parity report, keyboard cue-sheet generator for the README,
  secrets/telemetry grep, Dart licence allow-list, engine coverage gates.
- MIT `LICENSE` and the third-party licence trail in `LICENSES/` (LGPL-2.1, LGPL-3.0, libass ISC,
  OFL-1.1, Lucide ISC).

## [0.1.0] — planned

First usable release: Windows zip and split-per-ABI Android APKs from one tag, Marquee Lite live on
GitHub Pages behind the Worker. Toolchain pinned to Flutter 3.47.5.
