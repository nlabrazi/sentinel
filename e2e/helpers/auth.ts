import { Page, expect } from '@playwright/test';

export const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
export const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'sentinelpassword';

/**
 * Helper to log in as administrator in Sentinel
 */
export async function loginAsAdmin(page: Page) {
  await page.goto('/users/sign_in');
  await page.fill('input[name="user[username]"]', ADMIN_USERNAME);
  await page.fill('input[name="user[password]"]', ADMIN_PASSWORD);
  await page.click('input[type="submit"]');
  await expect(page).toHaveURL(/\/(#.*)?$/);
  await expect(page.locator('body')).toBeVisible();
}
