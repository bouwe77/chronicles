import { expect, test as base, type Page } from '@playwright/test'

// The invite code of the server under test (config/dev.exs has "dev").
const INVITE_CODE = process.env.E2E_INVITE_CODE ?? 'dev'

// Waits until the page's LiveView is connected, so clicks and forms reach the server.
export const connected = (page: Page) => page.locator('[data-phx-main].phx-connected').waitFor()

// A full page load of `path`, ready to use.
export const visit = async (page: Page, path: string) => {
  await page.goto(path)
  await connected(page)
}

// A reload, ready to use.
export const reload = async (page: Page) => {
  await page.reload()
  await connected(page)
}

// The flash sits over the header's links (language, log out) until it is closed.
export const closeFlash = async (page: Page) => {
  for (const alert of await page.getByRole('alert').all()) await alert.click()
  await expect(page.getByRole('alert')).toHaveCount(0)
}

// A new name on every call, so tests never share a user or a story.
export const unique = (prefix: string) =>
  `${prefix}-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`

// The newest login link sent to `email`, from the dev mailbox.
const loginLink = async (page: Page, email: string) => {
  let link: string | undefined
  await expect
    .poll(async () => {
      const { data } = await (await page.request.get('/dev/mailbox/json')).json()
      const mail = data.find((m: { to: string[][] | string[] }) =>
        JSON.stringify(m.to).includes(email),
      )
      link = mail?.text_body.match(/https?:\/\/\S+\/users\/log-in\/\S+/)?.[0]
      return link
    })
    .toBeTruthy()
  return new URL(link!).pathname
}

// Fills in and sends the signup form, by default with the right invite code.
export const submitSignup = async (
  page: Page,
  email: string,
  username: string,
  inviteCode = INVITE_CODE,
) => {
  await visit(page, '/users/register')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Username (shown to other players)').fill(username)
  await page.getByLabel('Invite code').fill(inviteCode)
  await page.getByRole('button', { name: 'Create an account' }).click()
}

export const signUp = async (page: Page, email: string, username: string) => {
  await submitSignup(page, email, username)
  await expect(page.getByText(`We sent an email to ${email}`)).toBeVisible()
  await visit(page, await loginLink(page, email))
  await page.getByRole('button', { name: 'Confirm and stay logged in' }).click()
  await expect(page.getByRole('heading', { name: 'Stories', exact: true })).toBeVisible()
  await connected(page)
  await closeFlash(page)
}

// Asks for a login link and opens it.
export const logIn = async (page: Page, email: string) => {
  await visit(page, '/users/log-in')
  await page.getByLabel('Email').first().fill(email)
  await page.getByRole('button', { name: 'Log in with email' }).click()
  await expect(page.getByText('you will get an email to log in')).toBeVisible()
  await visit(page, await loginLink(page, email))
  await page.getByRole('button', { name: 'Keep me logged in on this device' }).click()
  await expect(page.getByRole('heading', { name: 'Stories', exact: true })).toBeVisible()
  await connected(page)
  await closeFlash(page)
}

export const logOut = async (page: Page) => {
  await page.locator('[popovertarget=user-menu]').click()
  await page.getByRole('link', { name: 'Log out' }).click()
  await expect(page.getByRole('link', { name: 'Log in' })).toBeVisible()
}

export const deleteAccount = async (page: Page) => {
  await visit(page, '/account')
  await page.getByRole('button', { name: 'Delete my account' }).click()
  await expect(page.getByText('Your account is deleted.')).toBeVisible()
}

type User = { email: string; username: string }

// A fresh account, logged in on `page`, deleted afterwards with everything it made.
// Every confirm() is accepted.
const withUser = async (page: Page, use: (user: User) => Promise<void>) => {
  page.on('dialog', (dialog) => dialog.accept())
  const username = unique('e2e')
  const user = { email: `${username}@example.com`, username }
  await signUp(page, user.email, user.username)
  await use(user)
  await deleteAccount(page)
}

// `test` with a `user` on `page`, and on request `other`: a second user in a browser of
// their own.
export const test = base.extend<{ user: User; other: User & { page: Page } }>({
  user: async ({ page }, use) => withUser(page, use),
  other: async ({ browser }, use) => {
    const context = await browser.newContext()
    const page = await context.newPage()
    await withUser(page, (user) => use({ ...user, page }))
    await context.close()
  },
})

export { expect }

// Creates a story from a sketch on "New story". Ends on the story's page and returns its
// title.
export const createStory = async (page: Page, sketch: string) => {
  const title = unique('E2E story')
  await visit(page, '/stories/new')
  await page.getByLabel('Title').fill(title)
  await page.getByLabel('Sketch').fill(sketch)
  await page.getByRole('button', { name: 'Create the story' }).click()
  await expect(page.getByRole('heading', { name: title })).toBeVisible()
  return title
}

// From the story page: a new game.
export const newGame = async (page: Page) => {
  await button(page, 'New game').click()
  await expect(gameLog(page)).toBeVisible()
}

// The game screen: buttons by their text, and the panels by their heading.
export const button = (page: Page, name: string) => page.getByRole('button', { name, exact: true })
export const panel = (page: Page, heading: string) =>
  page.locator('section').filter({ has: page.getByRole('heading', { name: heading, exact: true }) })
export const gameLog = (page: Page) => page.getByRole('region', { name: 'Log' })
// The room you are in: the last room name in the log.
export const room = (page: Page) => gameLog(page).getByRole('heading').last()
export const ending = (page: Page) => page.getByRole('dialog')
export const backToStory = (page: Page) =>
  page.getByRole('link', { name: 'Back to the story' }).first().click()
// The games on a story's page.
export const games = (page: Page) => page.locator('#games').getByRole('link')
