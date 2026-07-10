import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright config for PocketCare e2e. CI boots the Next.js app (against a
 * local/mock backend — see .github/workflows/ci.yml) and runs these specs
 * headless on Chromium. Failures block the production promotion job.
 */
const PORT = Number(process.env.PORT ?? 3000);
const BASE_URL = process.env.E2E_BASE_URL ?? `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: BASE_URL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  // Reuse a running dev server locally; in CI the workflow starts the build+start
  // itself and sets E2E_BASE_URL, so webServer is skipped there.
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "pnpm --filter @pocketcare/web start",
        url: BASE_URL,
        timeout: 120_000,
        reuseExistingServer: !process.env.CI,
      },
});
