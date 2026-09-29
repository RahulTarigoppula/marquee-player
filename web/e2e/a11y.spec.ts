import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'
import { unplayableMkv } from './helpers'

test.describe('accessibility', () => {
  test('the landing has zero axe violations', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('#capline')).toContainText('MKV partial')
    const results = await new AxeBuilder({ page }).analyze()
    expect(results.violations).toEqual([])
  })

  test('the No Print card has zero axe violations', async ({ page }) => {
    await page.goto('/')
    await page.locator('input[type="file"]').setInputFiles(unplayableMkv())
    await expect(page.getByRole('alertdialog')).toBeVisible()
    const results = await new AxeBuilder({ page }).analyze()
    expect(results.violations).toEqual([])
  })

  test('the ticket office has zero axe violations', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('button', { name: /Ticket office/ }).click()
    const results = await new AxeBuilder({ page }).analyze()
    expect(results.violations).toEqual([])
  })
})
