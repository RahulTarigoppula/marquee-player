# Third-party licences

Marquee's own code is MIT (see `/LICENSE`). These are the texts for what ships alongside it.

| File | Covers | How it is used |
|---|---|---|
| [LGPL-2.1.txt](LGPL-2.1.txt) | [libmpv / mpv](https://github.com/mpv-player/mpv) (LGPL-2.1+, built `-Dgpl=false`) | dynamically linked native library (`libmpv-2.dll`, `libmpv.so`) |
| [LGPL-3.0.txt](LGPL-3.0.txt) | [FFmpeg](https://ffmpeg.org) (LGPL, built `--disable-gpl --enable-version3`) | dynamically linked inside libmpv |
| [GPL-3.0.txt](GPL-3.0.txt) | the GPL-3.0 terms that LGPL-3.0 incorporates by reference (FFmpeg's `--enable-version3` build) | reference text only — nothing in Marquee is GPL |
| [ISC-libass.txt](ISC-libass.txt) | [libass](https://github.com/libass/libass) (ISC) | subtitle renderer inside libmpv |
| [OFL-1.1.txt](OFL-1.1.txt) | the bundled variable fonts (SIL Open Font License 1.1) | assets |
| [ISC-lucide.txt](ISC-lucide.txt) | [Lucide](https://lucide.dev) icons (ISC) | assets |

## Native builds and their source

The LGPL natives are not built in this repository. They come prebuilt through the MIT-licensed
`media_kit_libs_*` packages, which are produced by these build-script repositories (the source,
configure flags and exact versions for every binary Marquee ships):

- Android: [media-kit/libmpv-android-video-build](https://github.com/media-kit/libmpv-android-video-build)
  — the `default` flavour only, never `encoders-gpl`.
- Windows: [media-kit/libmpv-win32-video-cmake](https://github.com/media-kit/libmpv-win32-video-cmake)

Because they are dynamically linked, a user may replace `libmpv-2.dll` (Windows) or the `.so`
files inside the APK with their own build of the same ABI. The Ticket Office shows these notices
and links in the app.
