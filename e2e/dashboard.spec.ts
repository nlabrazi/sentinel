import { test, expect } from '@playwright/test';
import { loginAsAdmin } from './helpers/auth';

test.describe('Dashboard and project listing', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsAdmin(page);
  });

  test('displays dashboard metrics and project cards', async ({ page }) => {
    await page.goto('/');

    await expect(page.locator('main')).toBeVisible();

    const projectLink = page.locator('main').getByRole('link', { name: "Argan d'ici" }).first();
    await expect(projectLink).toBeVisible();
  });

  test('filters projects with the search input', async ({ page }) => {
    await page.goto('/');

    const searchInput = page.locator('main form input[name="q"]').first();
    await expect(searchInput).toBeVisible();

    await searchInput.fill('Argan');
    await searchInput.press('Enter');

    await expect(page.locator('main').getByRole('link', { name: "Argan d'ici" }).first()).toBeVisible();
  });

  test('navigates to project details when clicking on a project', async ({ page }) => {
    await page.goto('/');

    const projectLink = page.locator('main').getByRole('link', { name: "Argan d'ici" }).first();
    await projectLink.click();

    await expect(page).toHaveURL(/\/projects\/\d+/);
    await expect(page.locator('main')).toContainText("Argan d'ici");
  });
});
