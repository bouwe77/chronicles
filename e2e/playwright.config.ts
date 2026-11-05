import { defineConfig } from '@playwright/test'

// Acceptance tests that use Chronicles only in the browser, like a player would. They
// read the dev mailbox for login links, and know nothing else about the server.
// Start the app first (mix phx.server); E2E_URL points at it.
export default defineConfig({
  testDir: 'tests',
  // Every test signs up and logs in through the mailbox first.
  timeout: 60_000,
  use: {
    baseURL: process.env.E2E_URL ?? 'http://localhost:9278',
    // The tests match English texts; a user's language follows the browser.
    locale: 'en-US',
  },
})
