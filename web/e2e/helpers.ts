import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { Page, Route } from '@playwright/test'

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), '../../test/fixtures')
export const fixture = (name: string): string => readFileSync(join(FIXTURES, name), 'utf8')

/** An unplayable "MKV" that sniffs as HEVC + AC-3, padded past 128 KiB so it hashes. */
export const unplayableMkv = () => ({
  name: 'Film.2019.1080p.x265.mkv',
  mimeType: 'video/x-matroska',
  buffer: Buffer.concat([
    Buffer.from([0x1a, 0x45, 0xdf, 0xa3]),
    Buffer.from('V_MPEGH/ISO/HEVC A_AC3'),
    Buffer.alloc(200_000),
  ]),
})

/**
 * Record a short, noisy (so > 128 KiB) WebM in the page itself: a real, playable print without
 * committing media to the repo.
 */
export async function recordWebm(page: Page, ms = 2000): Promise<Buffer> {
  const b64 = await page.evaluate(async (duration) => {
    const c = document.createElement('canvas')
    c.width = 320
    c.height = 180
    const ctx = c.getContext('2d') as CanvasRenderingContext2D
    const rec = new MediaRecorder(c.captureStream(30), {
      mimeType: 'video/webm',
      videoBitsPerSecond: 4_000_000,
    })
    const chunks: Blob[] = []
    rec.ondataavailable = (e) => chunks.push(e.data)
    rec.start(100)
    const t0 = performance.now()
    await new Promise<void>((resolve) => {
      const frame = () => {
        const img = ctx.createImageData(320, 180)
        for (let i = 0; i < img.data.length; i++) img.data[i] = (Math.random() * 255) | 0
        ctx.putImageData(img, 0, 0)
        if (performance.now() - t0 < duration) requestAnimationFrame(frame)
        else resolve()
      }
      frame()
    })
    const stopped = new Promise((r) => {
      rec.onstop = r
    })
    rec.stop()
    await stopped
    const bytes = new Uint8Array(await new Blob(chunks).arrayBuffer())
    let s = ''
    for (const b of bytes) s += String.fromCharCode(b)
    return btoa(s)
  }, ms)
  return Buffer.from(b64, 'base64')
}

/** Mock the Worker. Every call is recorded so a test can assert what did (not) leave. */
export async function mockWorker(page: Page, opts: { signedIn: boolean }) {
  const calls: string[] = []
  const json = (route: Route, name: string, status = 200) =>
    route.fulfill({ status, contentType: 'application/json', body: fixture(`os/${name}`) })
  await page.route('**/api/**', (route) => {
    const url = new URL(route.request().url())
    calls.push(`${route.request().method()} ${url.pathname}${url.search}`)
    if (url.pathname.endsWith('/login')) return json(route, 'login-ok.json')
    if (url.pathname.endsWith('/infos/user')) return json(route, '401.json', 401)
    if (url.pathname.endsWith('/subtitles')) return json(route, 'search-hash-hit.json')
    if (url.pathname.endsWith('/download')) {
      return opts.signedIn
        ? json(route, 'download-ok.json')
        : route.fulfill({
            status: 401,
            contentType: 'application/json',
            body: JSON.stringify({ error: 'sign-in-required', sentence: 'Sign in first.' }),
          })
    }
    if (url.pathname.endsWith('/subtitle-file')) {
      return route.fulfill({ status: 200, contentType: 'text/plain', body: fixture('sample.srt') })
    }
    return route.fulfill({
      status: 404,
      contentType: 'application/json',
      body: '{"error":"not-found","sentence":"No."}',
    })
  })
  return calls
}
