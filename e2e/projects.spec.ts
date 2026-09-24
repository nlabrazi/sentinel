import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';

test.describe('Project details page', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('displays project header, breadcrumbs and sections', async ({ page }) => {
    await page.goto('/');
    await page.locator('main').getByRole('link', { name: "Argan d'ici" }).first().click();
    await expect(page).toHaveURL(/\/projects\/\d+/);

    const breadcrumb = page.locator('main nav').first();
    await expect(breadcrumb).toBeVisible();
    await expect(breadcrumb).toContainText("Argan d'ici");

    await expect(page.locator('#overview')).toBeVisible();
    await expect(page.locator('#overview')).toContainText("Argan d'ici");
  });

  test('can navigate back to dashboard from breadcrumbs', async ({ page }) => {
    await page.goto('/');
    await page.locator('main').getByRole('link', { name: "Argan d'ici" }).first().click();
    await expect(page).toHaveURL(/\/projects\/\d+/);

    const breadcrumbRootLink = page.locator('main nav a[href="/"]').first();
    await breadcrumbRootLink.click();

    await expect(page).toHaveURL(/\/(#.*)?$/);
  });
});
