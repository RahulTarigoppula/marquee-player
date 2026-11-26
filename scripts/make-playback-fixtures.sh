#!/usr/bin/env bash
# Throwaway media for the real-libmpv smoke test (integration_test/playback_test.dart).
# Made on the CI runner and never committed. Unlike make-fixtures.sh nothing here has to be
# bit-exact: no hash golden depends on these bytes, only on what the files CONTAIN.
#
#   bash scripts/make-playback-fixtures.sh [out-dir]     # default: build/playback-fixtures
#
# Writes:
#   marquee-test.mkv        12 s, 640x360 H.264; AAC "eng" + AAC "hin"; an embedded SRT track;
#                           chapters Intro / Middle / Credits at 0 / 4 / 8 s
#   marquee-test.mp4        the same streams in MP4 (the subtitle as mov_text)
#   marquee-test-hevc.mkv   the same with HEVC video: only when this ffmpeg has libx265
#   marquee-test.en.srt     the sidecar for marquee-test.*
#   marquee-long.mkv        60 s, one audio track. Long enough for the resume rule: a film is
#                           resumable more than 10 s in and more than 30 s from its end, so a
#                           12 s clip can never resume.
#   marquee-long.en.srt     its sidecar: threading attaches it with zero requests
set -euo pipefail

FFMPEG="${FFMPEG:-ffmpeg}"
command -v "$FFMPEG" >/dev/null 2>&1 || {
  echo "::error::make-playback-fixtures: ffmpeg is not on PATH (set FFMPEG=/path/to/ffmpeg)" >&2
  exit 2
}

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/playback-fixtures}"
mkdir -p "$out"
# Every file below is named relative to the output folder: Git Bash on a Windows runner
# rewrites arguments that look like POSIX paths, and a bare file name never does.
cd "$out"
rm -f marquee-test.mkv marquee-test.mp4 marquee-test-hevc.mkv marquee-test.en.srt \
  marquee-long.mkv marquee-long.en.srt embedded.srt chapters.ffmeta

ff() { "$FFMPEG" -hide_banner -loglevel error -nostdin -y "$@"; }

# No pipe into `grep -q`: with pipefail an early exit of grep fails the pipeline (SIGPIPE).
encoders="$("$FFMPEG" -hide_banner -encoders 2>/dev/null || true)"
case "$encoders" in
  *libx264*) ;;
  *) echo "::error::make-playback-fixtures: this ffmpeg has no libx264 encoder" >&2; exit 2 ;;
esac

VIDEO="testsrc2=size=640x360:rate=24"

cat > embedded.srt <<'SRT'
1
00:00:00,500 --> 00:00:03,500
Embedded subtitle, first cue.

2
00:00:04,000 --> 00:00:07,500
Embedded subtitle, second cue.

3
00:00:08,000 --> 00:00:11,500
Embedded subtitle, last cue.
SRT

cat > marquee-test.en.srt <<'SRT'
1
00:00:00,500 --> 00:00:03,500
Sidecar subtitle, first cue.

2
00:00:04,000 --> 00:00:07,500
Sidecar subtitle, second cue.

3
00:00:08,000 --> 00:00:11,500
Sidecar subtitle, last cue.
SRT

cat > marquee-long.en.srt <<'SRT'
1
00:00:01,000 --> 00:00:09,000
Sidecar subtitle for the long film.

2
00:00:12,000 --> 00:00:28,000
Still here after the seek.

3
00:00:30,000 --> 00:00:58,000
The rest of the film.
SRT

cat > chapters.ffmeta <<'META'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=4000
title=Intro
[CHAPTER]
TIMEBASE=1/1000
START=4000
END=8000
title=Middle
[CHAPTER]
TIMEBASE=1/1000
START=8000
END=12000
title=Credits
META

# 1. MKV: inputs 0 video, 1 + 2 the two audio tones, 3 the subtitle, 4 the chapters.
#    One keyframe a second (-g 24), so a relative seek lands within a second too.
ff -f lavfi -i "$VIDEO" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000" \
  -i embedded.srt \
  -f ffmetadata -i chapters.ffmeta \
  -map 0:v:0 -map 1:a:0 -map 2:a:0 -map 3:s:0 -map_chapters 4 \
  -t 12 \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -g 24 \
  -c:a aac -b:a 96k -ac 2 \
  -c:s srt \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title=English \
  -metadata:s:a:1 language=hin -metadata:s:a:1 title=Hindi \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title=English \
  -disposition:a:0 default -disposition:a:1 0 -disposition:s:0 0 \
  marquee-test.mkv

# 2. MP4: the same packets; MP4 cannot hold SubRip, so the subtitle becomes mov_text.
ff -i marquee-test.mkv \
  -map 0:v:0 -map 0:a -map 0:s:0 -map_chapters 0 \
  -c:v copy -c:a copy -c:s mov_text \
  -metadata:s:a:0 language=eng -metadata:s:a:1 language=hin -metadata:s:s:0 language=eng \
  -movflags +faststart \
  marquee-test.mp4

# 3. HEVC: optional. A build without libx265 (or a failed encode) skips it; the test skips too.
case "$encoders" in
  *libx265*)
    if ! ff -f lavfi -i "$VIDEO" -i marquee-test.mkv \
      -map 0:v:0 -map 1:a -map 1:s -map_chapters 1 \
      -t 12 \
      -c:v libx265 -preset ultrafast -crf 28 -pix_fmt yuv420p -x265-params log-level=error \
      -c:a copy -c:s copy \
      marquee-test-hevc.mkv; then
      echo "::warning::make-playback-fixtures: the HEVC encode failed; the HEVC test will skip"
      rm -f marquee-test-hevc.mkv
    fi
    ;;
  *) echo "::notice::make-playback-fixtures: no libx265 in this ffmpeg; the HEVC test will skip" ;;
esac

# 4. The long film for the resume round trip.
ff -f lavfi -i "$VIDEO" \
  -f lavfi -i "sine=frequency=330:sample_rate=48000" \
  -map 0:v:0 -map 1:a:0 \
  -t 60 \
  -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -g 48 \
  -c:a aac -b:a 64k -ac 2 \
  -metadata:s:a:0 language=eng \
  marquee-long.mkv

rm -f embedded.srt chapters.ffmeta

# ── checks: fail HERE with a plain reason, not later as a confusing test failure ──
size_of() { wc -c < "$1" | tr -d '[:space:]'; }
for f in marquee-test.mkv marquee-test.mp4 marquee-long.mkv; do
  [ -f "$f" ] || { echo "::error::make-playback-fixtures: $f was not written" >&2; exit 1; }
  # Under 128 KiB a file has no moviehash, and without a hash there is no resume point.
  if [ "$(size_of "$f")" -lt 131072 ]; then
    echo "::error::make-playback-fixtures: $f is under 128 KiB ($(size_of "$f") bytes)" >&2
    exit 1
  fi
done

FFPROBE="${FFPROBE:-ffprobe}"
if command -v "$FFPROBE" >/dev/null 2>&1; then
  count() { # count <file> <stream type>
    "$FFPROBE" -v error -show_entries stream=codec_type -of csv=p=0 "$1" | grep -c "$2" || true
  }
  chapters() {
    "$FFPROBE" -v error -show_entries chapter=id -of csv=p=0 "$1" | grep -c '[0-9]' || true
  }
  a="$(count marquee-test.mkv audio)"
  s="$(count marquee-test.mkv subtitle)"
  c="$(chapters marquee-test.mkv)"
  echo "marquee-test.mkv: $a audio, $s subtitle, $c chapters"
  if [ "$a" != 2 ] || [ "$s" != 1 ] || [ "$c" != 3 ]; then
    echo "::error::make-playback-fixtures: marquee-test.mkv should hold 2 audio tracks, 1 subtitle and 3 chapters" >&2
    exit 1
  fi
  echo "marquee-test.mp4: $(count marquee-test.mp4 audio) audio, $(chapters marquee-test.mp4) chapters"
else
  echo "make-playback-fixtures: no ffprobe, the stream check is skipped"
fi

echo "make-playback-fixtures: wrote to $(pwd)"
ls -l
