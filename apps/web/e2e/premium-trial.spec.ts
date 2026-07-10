import { test, expect } from "@playwright/test";

/**
 * Premium trial edge cases. Backend-gated (entitlements live server-side).
 * Trial-window math is unit-tested in packages/core/entitlements; these specs
 * assert the UI honors the gate end-to-end once a backend fixture is wired.
 */
const FULL = process.env.E2E_FULL === "1";

test.describe("premium trial edge cases", () => {
  test.skip(!FULL, "needs a live backend — set E2E_FULL=1 with backend env");

  test("insights are locked for a free (non-trial) user", async ({ page }) => {
    await page.goto("/insights");
    await expect(page.getByText(/go premium/i)).toBeVisible();
  });

  test("an active trial unlocks premium surfaces", async ({ page }) => {
    // TODO(backend): seed a user with a trial expiring in the future.
    await page.goto("/insights");
    await expect(page.getByText(/go premium/i)).toHaveCount(0);
  });

  test("an expired trial re-locks premium surfaces (no off-by-one at expiry)", async ({ page }) => {
    // TODO(backend): seed a user whose trial ended yesterday.
    await page.goto("/insights");
    await expect(page.getByText(/go premium/i)).toBeVisible();
  });
});
