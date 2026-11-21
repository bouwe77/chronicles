import { test as plain } from '@playwright/test'
import { deleteAccount, expect, invite, logIn, logOut, submitInvite, test, unique } from './helpers'

plain('get invited, log out, log in again and delete the account', async ({ browser, page }) => {
  page.on('dialog', (dialog) => dialog.accept())
  const username = unique('e2e')
  const email = `${username}@example.com`
  await invite(browser, page, email, username)

  await logOut(page)
  await logIn(page, email)
  await expect(page.getByText(email)).toBeVisible()

  await deleteAccount(page)
  await expect(page.getByRole('link', { name: 'Log in' })).toBeVisible()
})

plain('nobody can sign up on their own', async ({ page }) => {
  await page.goto('/users/log-in')
  await expect(page.getByText('Chronicles is invite-only')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Sign up' })).toHaveCount(0)
})

test('a username can be taken only once', async ({ user, browser }) => {
  const admin = await submitInvite(browser, `${unique('e2e')}@example.com`, user.username)
  await expect(admin.page.getByText('has already been taken')).toBeVisible()
  await admin.close()
})
