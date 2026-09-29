#!/usr/bin/env bash
# Bit-exact media fixtures (§10.3). Same command, any ffmpeg 6/7 build → same bytes → same
# moviehash. Run on ubuntu-24.04 (the reference) and commit test/fixtures/media + hashes.json
# together: a fixture change moves every hash golden.
#
#   bash scripts/make-fixtures.sh            # writes test/fixtures/media/*
#   BREAKDANCE=1 bash scripts/make-fixtures.sh   # also fetches breakdance.avi to a temp dir
set -euo pipefail

command -v ffmpeg >/dev/null || { echo "make-fixtures: ffmpeg is required" >&2; exit 2; }

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/test/fixtures/media"
mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

BITEXACT=(-fflags +bitexact -flags:v +bitexact -flags:a +bitexact -map_metadata -1)
SRC=(-f lavfi -i "testsrc2=size=320x180:rate=24000/1001" -f lavfi -i "sine=frequency=1000" -t 10)

cat > "$tmp/chapters.ffmeta" <<'META'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=3000
title=Leader
[CHAPTER]
TIMEBASE=1/1000
START=3000
END=6000
title=Reel 1
[CHAPTER]
TIMEBASE=1/1000
START=6000
END=10000
title=Reel 2
META

# 1. MKV / H.264 / AAC + chapters + embedded SRT and ASS tracks
ffmpeg -y -loglevel error "${SRC[@]}" \
  -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 64k \
  "${BITEXACT[@]}" "$tmp/base.mkv"
ffmpeg -y -loglevel error -i "$tmp/base.mkv" -i "$tmp/chapters.ffmeta" \
  -i "$root/test/fixtures/sample.srt" -i "$root/test/fixtures/sample.ass" \
  -map 0 -map 2 -map 3 -map_chapters 1 -c copy \
  -metadata:s:s:0 language=eng -metadata:s:s:0 title=SRT \
  -metadata:s:s:1 language=eng -metadata:s:s:1 title=ASS \
  -fflags +bitexact "$out/testsrc-10s-h264-aac.mkv"

# 2. MP4 / H.264 / AAC (the web fast path)
ffmpeg -y -loglevel error -i "$tmp/base.mkv" -map 0 -c copy -movflags +faststart \
  "${BITEXACT[@]}" "$out/testsrc-10s-h264-aac.mp4"

# 3. WebM / VP9 / Opus
ffmpeg -y -loglevel error "${SRC[@]}" -c:v libvpx-vp9 -b:v 200k -c:a libopus \
  "${BITEXACT[@]}" "$out/testsrc-10s-vp9-opus.webm"

# 4. MKV / HEVC / AC-3 (the No Print path on the web; HEVC hwdec on native)
ffmpeg -y -loglevel error "${SRC[@]}" -c:v libx265 -x265-params log-level=0 -crf 24 \
  -c:a ac3 -b:a 96k "${BITEXACT[@]}" "$out/testsrc-10s-hevc-ac3.mkv"

# 5. AVI / MPEG-4 part 2 / MP3 ("any container")
ffmpeg -y -loglevel error "${SRC[@]}" -c:v mpeg4 -q:v 4 -c:a libmp3lame \
  "${BITEXACT[@]}" "$out/testsrc-10s-h264.avi"

# 6. Under 128 KiB — the silent too-small branch
ffmpeg -y -loglevel error -i "$out/testsrc-10s-h264-aac.mkv" -map 0:v -c copy -fs 102400 \
  "${BITEXACT[@]}" "$out/tiny-100kib.mkv"

# 7. 200 KiB of deterministic noise — the undecodable print
openssl enc -aes-256-ctr -pass pass:marquee -nosalt -pbkdf2 < /dev/zero 2>/dev/null \
  | head -c 204800 > "$out/corrupt.mkv"

# 8. The bias-light quantizer golden: 64×36, 60 % tungsten, 30 % crimson, 10 % exit green
python3 - "$out/frame-bias.png" <<'PY'
import struct, sys, zlib
w, h = 64, 36
rows = []
for y in range(h):
    row = bytearray([0])
    for x in range(w):
        i = y * w + x
        n = w * h
        c = (0xFF, 0xC5, 0x6E) if i < n * 0.6 else (0xA3, 0x25, 0x2F) if i < n * 0.9 else (0x5F, 0xD4, 0x8A)
        row += bytes(c)
    rows.append(bytes(row))
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) \
    + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY

# Freeze the hashes (V6): both suites assert these.
node - "$out" "$root/test/fixtures/hashes.json" <<'JS'
const fs = require('node:fs'), path = require('node:path')
const [dir, outFile] = process.argv.slice(2)
const MASK = 0xffffffffffffffffn
const sum = (b) => { let s = 0n; for (let i = 0; i < 65536; i += 8) s = (s + b.readBigUInt64LE(i)) & MASK; return s }
const out = {}
for (const f of fs.readdirSync(dir).sort()) {
  const buf = fs.readFileSync(path.join(dir, f))
  if (buf.length < 131072) { out[f] = null; continue }
  const h = (BigInt(buf.length) + sum(buf.subarray(0, 65536)) + sum(buf.subarray(buf.length - 65536))) & MASK
  out[f] = h.toString(16).padStart(16, '0')
}
fs.writeFileSync(outFile, JSON.stringify(out, null, 2) + '\n')
console.log(`make-fixtures: ${Object.keys(out).length} files, hashes frozen in ${path.basename(outFile)}`)
JS

if [[ "${BREAKDANCE:-0}" == "1" ]]; then
  bd="$tmp/../breakdance.avi"
  curl -fsSL -o "$bd" "https://static.opensubtitles.org/addons/avi/breakdance.avi" \
    && echo "export MARQUEE_BREAKDANCE=$bd BREAKDANCE_AVI=$bd" \
    || echo "make-fixtures: breakdance.avi unavailable — V1 will skip with a warning" >&2
fi
