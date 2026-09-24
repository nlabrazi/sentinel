import { test, expect } from '@playwright/test';
import { loginAsAdmin, ADMIN_USERNAME } from './helpers/auth';

test.describe('Authentication flow', () => {
  test('redirects unauthenticated user from protected page to login', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/\/users\/sign_in/);
    await expect(page.locator('h1')).toContainText('Sentinel');
  });

  test('displays error alert when submitting invalid credentials', async ({ page }) => {
    await page.goto('/users/sign_in');
    await page.fill('input[name="user[username]"]', 'invalid_user');
    await page.fill('input[name="user[password]"]', 'wrongpassword123');
    await page.click('input[type="submit"]');

    await expect(page).toHaveURL(/\/users\/sign_in/);
    const alertMessage = page.locator('p.text-red-200, .alert');
    await expect(alertMessage).toBeVisible();
  });

  test('logs in successfully with valid admin credentials', async ({ page }) => {
    await loginAsAdmin(page);
    await expect(page).toHaveURL('/');
    await expect(page.locator('body')).toContainText('Sentinel');
    await expect(page.locator('body')).toContainText(ADMIN_USERNAME);
  });

  test('logs out successfully when clicking sign out', async ({ page }) => {
    await loginAsAdmin(page);

    const signOutButton = page.getByRole('button', { name: /déconnexion|sign out/i });
    await expect(signOutButton).toBeVisible();
    await signOutButton.click();

    await expect(page).toHaveURL(/\/users\/sign_in/);
  });
});
