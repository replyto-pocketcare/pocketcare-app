import { test, expect } from "@playwright/test";

/**
 * Smoke tests — run against a freshly built app with no backend dependency.
 * They assert the shell boots, first-run routing works, and nothing crashes.
 */
test.describe("app boot", () => {
  test("loads without a runtime crash and renders the shell", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(String(e)));

    await page.goto("/");
    await expect(page.locator("body")).toBeVisible();
    // Next.js error overlay should not be present.
    await expect(page.locator("text=Application error")).toHaveCount(0);
    // First run redirects unauthenticated users into onboarding/login.
    await expect(page).toHaveURL(/\/(onboarding|login)?$/);
    expect(errors, `page errors:\n${errors.join("\n")}`).toEqual([]);
  });

  test("has an accessible primary heading or CTA", async ({ page }) => {
    await page.goto("/onboarding");
    const headings = page.locator("h1, h2, button, a[role=button]");
    await expect(headings.first()).toBeVisible();
  });
});
