// Generates the PWA icons: a single lit tungsten bulb over a crimson trim on Auditorium black.
// No dependencies — raw RGBA rows deflated with node:zlib into a PNG. Run: npm run icons
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { deflateSync } from 'node:zlib'

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'icons')

// Token values (tokens.css): --bg, --accent, --accent-2, --bg-elevated, --border.
const BG = [0x07, 0x06, 0x0a]
const ACCENT = [0xff, 0xc5, 0x6e]
const CRIMSON = [0xa3, 0x25, 0x2f]
const BOX = [0x12, 0x0e, 0x15]
const SEAM = [0x2a, 0x23, 0x30]

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c >>> 0
})
const crc32 = (buf) => {
  let c = 0xffffffff
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}
const chunk = (type, data) => {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length)
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(td))
  return Buffer.concat([len, td, crc])
}

function png(size, scale) {
  const rows = []
  const c = size / 2
  const bulbR = size * 0.075 * scale
  const haloR = size * 0.34 * scale
  const boxW = size * 0.62 * scale
  const boxH = size * 0.36 * scale
  const boxTop = c - boxH * 0.62
  const trimY = boxTop + boxH
  const trimH = Math.max(1, Math.round(size / 96))
  for (let y = 0; y < size; y++) {
    const row = Buffer.alloc(1 + size * 4)
    for (let x = 0; x < size; x++) {
      let px = BG
      const inBox = Math.abs(x + 0.5 - c) <= boxW / 2 && y >= boxTop && y < trimY
      const onEdge = inBox && (Math.abs(Math.abs(x + 0.5 - c) - boxW / 2) < 1.5 || y - boxTop < 1.5)
      if (inBox) px = onEdge ? SEAM : BOX
      if (Math.abs(x + 0.5 - c) <= boxW / 2 && y >= trimY && y < trimY + trimH) px = CRIMSON
      const d = Math.hypot(x + 0.5 - c, y + 0.5 - (boxTop + boxH / 2))
      // the halo: a soft tungsten falloff (the only glow allowed)
      const halo = Math.max(0, 1 - d / haloR) ** 2.2 * 0.55
      px = px.map((v, i) => Math.round(v + (ACCENT[i] - v) * halo))
      if (d <= bulbR) px = ACCENT
      else if (d <= bulbR + 1) px = px.map((v, i) => Math.round((v + ACCENT[i]) / 2))
      row.set([...px, 255], 1 + x * 4)
    }
    rows.push(row)
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(size, 0)
  ihdr.writeUInt32BE(size, 4)
  ihdr.set([8, 6, 0, 0, 0], 8) // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(rows), { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

mkdirSync(OUT, { recursive: true })
writeFileSync(join(OUT, 'icon-192.png'), png(192, 1))
writeFileSync(join(OUT, 'icon-512.png'), png(512, 1))
// maskable: everything inside the 80 % safe zone
writeFileSync(join(OUT, 'icon-maskable-512.png'), png(512, 0.72))
