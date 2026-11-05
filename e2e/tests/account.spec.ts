import { test as plain } from '@playwright/test'
import { deleteAccount, expect, logIn, logOut, signUp, submitSignup, test, unique } from './helpers'

plain('sign up, log out, log in again and delete the account', async ({ page }) => {
  page.on('dialog', (dialog) => dialog.accept())
  const username = unique('e2e')
  const email = `${username}@example.com`
  await signUp(page, email, username)

  await logOut(page)
  await logIn(page, email)
  await expect(page.getByText(email)).toBeVisible()

  await deleteAccount(page)
  await expect(page.getByRole('link', { name: 'Log in' })).toBeVisible()
})

plain('signing up needs the right invite code', async ({ page }) => {
  const username = unique('e2e')
  await submitSignup(page, `${username}@example.com`, username, 'not-the-code')
  await expect(page.getByText('is not valid')).toBeVisible()
})

test('a username can be taken only once', async ({ user, browser }) => {
  const other = await browser.newPage()
  await submitSignup(other, `${unique('e2e')}@example.com`, user.username)
  await expect(other.getByText('has already been taken')).toBeVisible()
  await other.close()
})
