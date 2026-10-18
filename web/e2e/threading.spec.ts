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

  test('lists other prints in the booth and attaches the one picked, spending one ticket', async ({
    page,
  }) => {
    const calls = await mockWorker(page, { signedIn: true })
    await page.goto('/')
    await page.getByRole('button', { name: /Ticket office/ }).click()
    await page.getByLabel('OpenSubtitles username').fill('fixture')
    await page.getByLabel('Password').fill('fixture')
    await page.getByRole('button', { name: 'Sign in', exact: true }).click()
    const buffer = await recordWebm(page)
    await page
      .locator('input[type="file"]')
      .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
    await expect(page.locator('video track')).toHaveCount(1)

    await page.getByRole('button', { name: 'Subtitles', exact: true }).click()
    const booth = page.getByRole('dialog', { name: /Subtitle booth/ })
    await expect(booth).toBeVisible()
    await booth.getByRole('button', { name: 'Find another print' }).click()
    const prints = booth.getByRole('radiogroup', { name: 'Other prints' }).getByRole('radio')
    await expect(prints).toHaveCount(2) // the attached print is never offered again
    expect(calls.filter((c) => c === 'POST /api/download')).toHaveLength(1) // nothing spent yet
    await prints.filter({ hasText: 'WEB-DL' }).click()
    await expect(booth.getByRole('radiogroup', { name: 'Subtitle tracks' })).toContainText('WEB-DL')
    expect(calls.filter((c) => c === 'POST /api/download')).toHaveLength(2)
  })

  test('keeps subtitles off through a sync change', async ({ page }) => {
    await mockWorker(page, { signedIn: true })
    await page.goto('/')
    await page.getByRole('button', { name: /Ticket office/ }).click()
    await page.getByLabel('OpenSubtitles username').fill('fixture')
    await page.getByLabel('Password').fill('fixture')
    await page.getByRole('button', { name: 'Sign in', exact: true }).click()
    const buffer = await recordWebm(page)
    await page
      .locator('input[type="file"]')
      .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
    await expect(page.locator('video track')).toHaveCount(1)
    const mode = () => page.evaluate(() => document.querySelector('video')?.textTracks[0]?.mode)
    await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
    await expect.poll(mode).toBe('showing')
    await page.keyboard.press('c')
    await expect.poll(mode).toBe('hidden')
    await page.keyboard.press('h') // subtitles 50 ms later: the track is re-emitted
    await expect(page.locator('.player__folio')).toContainText('SUB +0.05')
    await page.waitForTimeout(300)
    await expect.poll(mode).toBe('hidden')
  })

  test('Space plays and pauses the film instead of reopening the file picker', async ({ page }) => {
    await mockWorker(page, { signedIn: false })
    await page.goto('/')
    const buffer = await recordWebm(page)
    await page.getByRole('button', { name: /Drop a film here/ }).focus()
    await page
      .locator('input[type="file"]')
      .setInputFiles({ name: NAME, mimeType: 'video/webm', buffer })
    await page.getByRole('button', { name: 'Play without subtitles' }).click()
    await expect(page.getByRole('region', { name: 'Auditorium' })).toBeVisible()
    let chooser = false
    page.on('filechooser', () => {
      chooser = true
    })
    const paused = () => page.evaluate(() => document.querySelector('video')?.paused)
    const before = await paused()
    await page.keyboard.press(' ')
    await expect.poll(paused).toBe(!before)
    await page.keyboard.press('Enter')
    await page.waitForTimeout(300)
    expect(chooser).toBe(false)
    await expect(page.locator('.room')).toHaveAttribute('inert', '')
  })
})
