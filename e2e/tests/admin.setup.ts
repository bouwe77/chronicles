import { test as setup } from '@playwright/test'
import { ADMIN_EMAIL, ADMIN_STATE, logIn } from './helpers'

// Logs in the admin once, so tests running side by side don't race for the newest login
// link in the mailbox. Every test reuses this session to invite its user.
setup('log in the admin', async ({ page }) => {
  await logIn(page, ADMIN_EMAIL)
  await page.context().storageState({ path: ADMIN_STATE })
})
