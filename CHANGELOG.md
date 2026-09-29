# Changelog

All notable changes to Marquee are recorded here. Versions follow [SemVer](https://semver.org);
tags are `vX.Y.Z` and each one produces a GitHub Release (see `.github/workflows/release.yml`).

## [Unreleased]

### Added
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
