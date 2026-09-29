import { expect, test } from '@playwright/test'
import { mockWorker, recordWebm } from './helpers'

const NAME = 'The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.webm'

test.describe('threading with a mocked Worker', () => {
  test.skip(({ browserName }) => browserName !== 'chromium', 'MediaRecorder WebM fixture')

  test('lights MATCH on a hash hit, attaches subtitles and plays', async ({ page }) => {
    const calls = await mockWorker(page, { signedIn: true })
    await page.goto('/')
    // Sign in at the ticket office with the fixture account (the Worker is mocked).
    await page.getByRole('button', { name: /Ticket office/ }).click()
    await page.getByLabel('OpenSubtitles username').fill('fixture')
    await page.getByLabel('Password').fill('fixture')
    await page.getByRole('button', { name: 'Sign in', exact: true }).click()
    await expect(page.getByRole('dialog', { name: 'Ticket office' })).toBeHidden()

    const buffer = await recordWebm(page)
    await page
      .locator('input[type="file"]')
      .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
    const leader = page.getByRole('region', { name: 'Threading' })
    await expect(leader.getByRole('radio', { checked: true })).toContainText('MATCH')

    const auditorium = page.getByRole('region', { name: 'Auditorium' })
    await expect(auditorium).toBeVisible()
    await expect(page.locator('video track')).toHaveCount(1)
    await expect(page.locator('html')).toHaveAttribute('data-house', 'down')

    const search = calls.find((c) => c.startsWith('GET /api/subtitles?'))
    expect(search).toMatch(
      /languages=en&moviehash=[0-9a-f]{16}&moviehash_match=include&order_by=download_count$/,
    )
    expect(calls.filter((c) => c === 'POST /api/download')).toHaveLength(1)
    expect(calls.some((c) => c.startsWith('GET /api/subtitle-file?link='))).toBe(true)
  })

  test('stalls with the sign-in sentence instead of spending a ticket when signed out', async ({
    page,
  }) => {
    const calls = await mockWorker(page, { signedIn: false })
    await page.goto('/')
    const buffer = await recordWebm(page)
    await page
      .locator('input[type="file"]')
      .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
    const leader = page.getByRole('region', { name: 'Threading' })
    await expect(leader.getByRole('status')).toContainText('Sign in to OpenSubtitles')
    await expect(leader.getByRole('button', { name: /Sign in at the ticket office/ })).toBeVisible()
    await expect(leader.getByRole('button', { name: 'Play without subtitles' })).toBeVisible()
    expect(calls.filter((c) => c.startsWith('POST /api/download'))).toEqual([])
  })
})
