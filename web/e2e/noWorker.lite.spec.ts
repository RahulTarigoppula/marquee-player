// The production state while no Worker is deployed: a build with an empty VITE_API_BASE.
// Films go straight to the picture, nothing is ever fetched off-origin, and adding a subtitle
// file is the obvious way to get subtitles.
import AxeBuilder from '@axe-core/playwright'
import { expect, type Page, test } from '@playwright/test'
import { fixture, recordWebm } from './helpers'

const NAME = 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.webm'
const srt = (name = 'The.Third.Man.1949.en.srt') => ({
  name,
  mimeType: 'application/x-subrip',
  buffer: Buffer.from(fixture('sample.srt')),
})

/** Every request that is not for this origin's own files. */
function offOrigin(page: Page, baseURL: string | undefined): string[] {
  const origin = new URL(baseURL ?? 'http://localhost:4274').origin
  const urls: string[] = []
  page.on('request', (r) => {
    const u = r.url()
    if (!u.startsWith(origin) && !u.startsWith('data:') && !u.startsWith('blob:')) urls.push(u)
  })
  return urls
}

test.describe('Lite with no Worker', () => {
  test('says how to get subtitles and offers no ticket office', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('#capline')).toContainText('MKV partial')
    await expect(page.getByRole('button', { name: /Ticket office/ })).toHaveCount(0)
    await expect(page.getByText('Online subtitle search needs the')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Windows / Android app' })).toHaveAttribute(
      'href',
      /github\.com\/.+\/releases\/latest$/,
    )
    await expect(page.getByText('nothing is uploaded')).toBeVisible()
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([])
  })

  test.describe('with a real print', () => {
    test.skip(({ browserName }) => browserName !== 'chromium', 'MediaRecorder WebM fixture')

    test('plays a film straight away without a single off-origin request', async ({
      page,
      baseURL,
    }) => {
      const urls = offOrigin(page, baseURL)
      await page.goto('/')
      const buffer = await recordWebm(page)
      await page
        .locator('input[type="file"]')
        .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
      await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
      await expect(page.getByRole('region', { name: 'Threading' })).toBeHidden()
      await expect(page.getByRole('heading', { name: 'The Third Man' })).toBeVisible()
      await expect(page).toHaveTitle('The Third Man · Marquee Lite')
      await expect(page.locator('.room')).toHaveAttribute('inert', '')
      expect(urls).toEqual([])
    })

    test('attaches a subtitle file chosen together with the film', async ({ page }) => {
      await page.goto('/')
      const buffer = await recordWebm(page)
      await page
        .locator('input[type="file"]')
        .setInputFiles([{ name: NAME, mimeType: 'video/webm', buffer }, srt()])
      await expect(page.locator('video track')).toHaveCount(1)
      await expect(page.getByRole('button', { name: 'Subtitles', exact: true })).toHaveAttribute(
        'aria-pressed',
        'true',
      )
    })

    test('adds a subtitle file from the player, and Off stays off', async ({ page }) => {
      await page.goto('/')
      const buffer = await recordWebm(page)
      await page
        .locator('input[type="file"]')
        .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
      await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
      await page.mouse.move(400, 400) // the controls show on movement
      const chooser = page.waitForEvent('filechooser')
      await page.getByRole('button', { name: 'Add subtitle file…' }).click()
      await (await chooser).setFiles(srt('mine.srt'))
      await expect(page.locator('video track')).toHaveCount(1)

      await page.getByRole('button', { name: 'Subtitles', exact: true }).click()
      const booth = page.getByRole('dialog', { name: /Subtitle booth/ })
      await expect(booth.getByRole('radio', { name: /mine\.srt/ })).toHaveAttribute(
        'aria-checked',
        'true',
      )
      await expect(booth.getByRole('button', { name: 'Find another print' })).toHaveCount(0)
      await booth.getByRole('radio', { name: 'Off' }).click()
      const mode = () => page.evaluate(() => document.querySelector('video')?.textTracks[0]?.mode)
      await expect.poll(mode).toBe('hidden')
      await page.keyboard.press('Escape')
      await expect(booth).toBeHidden()
    })

    test('takes a subtitle dropped anywhere on the page without navigating away', async ({
      page,
    }) => {
      await page.goto('/')
      const buffer = await recordWebm(page)
      await page
        .locator('input[type="file"]')
        .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
      await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
      const prevented = await page.evaluate((text) => {
        const dt = new DataTransfer()
        dt.items.add(new File([text], 'dropped.srt', { type: 'application/x-subrip' }))
        const over = new DragEvent('dragover', { dataTransfer: dt, cancelable: true })
        window.dispatchEvent(over)
        const drop = new DragEvent('drop', { dataTransfer: dt, cancelable: true, bubbles: true })
        document.body.dispatchEvent(drop)
        return over.defaultPrevented && drop.defaultPrevented
      }, fixture('sample.srt'))
      expect(prevented).toBe(true)
      await expect(page.locator('video track')).toHaveCount(1)
      expect(new URL(page.url()).pathname).toBe('/')
    })

    test('a tap on a phone shows the controls instead of pausing', async ({ page, isMobile }) => {
      test.skip(!isMobile, 'touch only')
      await page.goto('/')
      const buffer = await recordWebm(page)
      await page
        .locator('input[type="file"]')
        .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
      const video = page.locator('video')
      await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
      await page.evaluate(() => {
        const v = document.querySelector('video')
        if (!v) return
        v.loop = true // the fixture is two seconds long
        return v.play()
      })
      await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(false)
      const box = await video.boundingBox()
      if (!box) throw new Error('no picture')
      await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2)
      await page.waitForTimeout(500)
      expect(await video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(false)
    })
  })
})
