import { defineConfig, devices } from "@playwright/test";

// Browser smoke tests. These exist because this repo has twice shipped UI that every
// other gate called green and that no user could actually reach: the Taste Passport was
// built, tested and lint-clean while being imported by nothing, and the venue insights
// v2 client half rendered zeros for weeks. Unit tests prove the brains; db:verify proves
// the database; only a browser proves a click does something.
//
// Kept in ./e2e so `npm test` (vitest, include: tests/**) never picks them up, and out of
// the Next build via tsconfig exclude. Run with `npm run test:e2e` — deliberately NOT part
// of `npm run gates`, which must stay fast and needs no browser download.
export default defineConfig({
  testDir: "./e2e",
  globalSetup: "./e2e/global-setup.ts",
  fullyParallel: false, // the app is one localStorage diary; parallel runs would fight
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? "line" : "list",
  use: {
    baseURL: "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
