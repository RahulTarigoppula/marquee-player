import { expect, test } from '@playwright/test'
import { mockWorker, unplayableMkv } from './helpers'

test.describe('No Print card', () => {
  test('names the exact missing decoder within a second', async ({ page }) => {
    const calls = await mockWorker(page, { signedIn: false })
    await page.goto('/')
    const t0 = Date.now()
    await page.locator('input[type="file"]').setInputFiles(unplayableMkv())
    const card = page.getByRole('alertdialog')
    await expect(card).toBeVisible()
    expect(Date.now() - t0).toBeLessThan(1000 + 500) // N16 budget + harness slack
    await expect(card).toContainText("This print can't be projected here.")
    await expect(card).toContainText(/This browser has no (HEVC|AC-3) decoder\./)
    await expect(card).toContainText('MKV · HEVC · AC-3')
    expect(calls.filter((c) => c.startsWith('POST /api/download'))).toEqual([])
  })

  test('never paints --danger as a background', async ({ page }) => {
    await page.goto('/')
    await page.locator('input[type="file"]').setInputFiles(unplayableMkv())
    await expect(page.getByRole('alertdialog')).toBeVisible()
    const danger = await page.evaluate(() => {
      const probe = document.createElement('i')
      probe.style.color = 'var(--danger)'
      document.body.append(probe)
      const c = getComputedStyle(probe).color
      probe.remove()
      return c
    })
    const backgrounds = await page
      .locator('.noprint *')
      .evaluateAll((els) => els.map((e) => getComputedStyle(e).backgroundColor))
    expect(backgrounds).not.toContain(danger)
  })

  test('offers exactly the native builds and another film, never a WebCodecs path', async ({
    page,
  }) => {
    await page.addInitScript(() => {
      Reflect.deleteProperty(window, 'VideoDecoder')
    })
    await page.goto('/')
    await expect(page.locator('#capline')).toContainText('· WebCodecs unavailable')
    await page.locator('input[type="file"]').setInputFiles(unplayableMkv())
    const card = page.getByRole('alertdialog')
    await expect(card).toBeVisible()
    await expect(page.getByRole('button', { name: 'Try the WebCodecs path' })).toHaveCount(0)
    await expect(card.getByRole('link', { name: /Open in Marquee for Windows/ })).toBeVisible()
    await expect(card.getByRole('button', { name: 'Open another film' })).toBeVisible()
    await expect(card.getByRole('link').or(card.getByRole('button'))).toHaveCount(2)
  })
})
