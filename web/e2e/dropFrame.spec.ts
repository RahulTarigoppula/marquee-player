import { expect, test } from '@playwright/test'

test.describe('drop frame', () => {
  test('is reachable by keyboard and Enter opens a real multi-file picker', async ({ page }) => {
    await page.goto('/')
    const doors = page.getByRole('button', { name: /Drop a film here/ })
    await doors.focus()
    await expect(doors).toBeFocused()
    const chooser = page.waitForEvent('filechooser')
    await page.keyboard.press('Enter')
    // multiple: a film and its subtitle file can be chosen together
    expect((await chooser).isMultiple()).toBe(true)
  })

  test('Space opens the picker too, and a real file input exists', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('input[type="file"]')).toHaveCount(1)
    await page.getByRole('button', { name: /Drop a film here/ }).focus()
    const chooser = page.waitForEvent('filechooser')
    await page.keyboard.press(' ')
    await chooser
  })

  test('says a subtitle file needs its film first', async ({ page }) => {
    await page.goto('/')
    await page.locator('input[type="file"]').setInputFiles({
      name: 'film.en.srt',
      mimeType: 'text/plain',
      buffer: Buffer.from('1\n00:00:01,000 --> 00:00:02,000\nHi\n'),
    })
    await expect(page.getByRole('status').first()).toContainText('open the film first')
  })
})
