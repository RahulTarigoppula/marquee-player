import { expect, test } from '@playwright/test'

test.describe('Lite landing', () => {
  test('renders the lit sign and a computed capability line', async ({ page, browserName }) => {
    await page.clock.setFixedTime(new Date('2026-09-06T21:14:00+05:30'))
    await page.goto('/')
    await expect(page.getByRole('heading', { name: 'Marquee Lite' })).toBeVisible()
    await expect(page.locator('html')).toHaveAttribute('data-sky', 'night')
    const line = page.locator('#capline')
    await expect(line).toContainText('MKV partial')
    if (browserName === 'chromium') await expect(line).toContainText('WebM/VP9 ✓')
    if (browserName === 'firefox') await expect(line).toContainText('AC-3 ✗')
    await expect(page.getByRole('link', { name: /Open in Marquee for Windows/ })).toBeVisible()
  })

  test('makes no off-origin request and loads no JASSUB bytes', async ({ page, baseURL }) => {
    const urls: string[] = []
    page.on('request', (r) => urls.push(r.url()))
    await page.goto('/')
    await expect(page.locator('#capline')).toContainText('MKV partial')
    await page.evaluate(() => document.fonts.ready.then(() => undefined))
    const origin = new URL(baseURL ?? 'http://localhost:4173').origin
    expect(urls.filter((u) => !u.startsWith(origin) && !u.startsWith('data:'))).toEqual([])
    expect(urls.filter((u) => /jassub|\.wasm/.test(u))).toEqual([])
  })

  test('puts the house lights down with one custom property', async ({ page }) => {
    await page.goto('/')
    const house = () =>
      page.evaluate(() =>
        getComputedStyle(document.documentElement).getPropertyValue('--house').trim(),
      )
    expect(await house()).toBe('1')
  })
})
