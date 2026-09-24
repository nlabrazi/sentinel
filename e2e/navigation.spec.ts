import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';

test.describe('Global navigation and sidebar', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('navigates to Deployments page', async ({ page }) => {
    await page.goto('/');

    await page.locator('aside nav a[href="/deploys"]').click();
    await expect(page).toHaveURL(/\/deploys/);
    await expect(page.locator('main')).toContainText(/déploiements|deployments/i);
  });

  test('navigates to Settings page', async ({ page }) => {
    await page.goto('/');

    await page.locator('aside nav a[href="/settings"]').click();
    await expect(page).toHaveURL(/\/settings/);
    await expect(page.locator('main')).toContainText(/paramètres|settings/i);
  });

  test('navigates to Documentation page', async ({ page }) => {
    await page.goto('/');

    await page.locator('aside nav a[href="/documentation"]').click();
    await expect(page).toHaveURL(/\/documentation/);
    await expect(page.locator('main')).toContainText(/documentation/i);
  });

  test('toggles dark mode via theme switcher button', async ({ page }) => {
    await page.goto('/');

    const toggleButton = page.locator('#dark-mode-toggle');
    await expect(toggleButton).toBeVisible();

    const initialIsDark = await page.evaluate(() => document.documentElement.classList.contains('dark'));

    // Toggle theme
    await toggleButton.click();

    const updatedIsDark = await page.evaluate(() => document.documentElement.classList.contains('dark'));
    expect(updatedIsDark).toBe(!initialIsDark);
  });
});
