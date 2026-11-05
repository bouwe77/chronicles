import { backToStory, button, createStory, expect, games, newGame, reload, room, test, visit } from './helpers'

const HOUSE = `- porch
  - exit: hall "Go inside"
- hall
`

test('a private story is only for its author, until it is public', async ({
  page,
  user,
  other,
}) => {
  const title = await createStory(page, HOUSE)
  const story = page.url()
  await visit(other.page, '/stories')
  await expect(other.page.getByText(title)).toHaveCount(0)

  await button(page, 'Private').click()
  await expect(button(page, 'Public')).toBeVisible()

  // The other user sees it, by its author, can play it, and can't change it.
  await reload(other.page)
  await expect(other.page.getByRole('listitem').filter({ hasText: title })).toContainText(
    `by ${user.username}`,
  )
  await visit(other.page, story)
  await expect(other.page.getByRole('link', { name: 'Edit' })).toHaveCount(0)
  await newGame(other.page)
  await expect(room(other.page)).toHaveText('Porch')

  await button(page, 'Public').click()
  await expect(button(page, 'Private')).toBeVisible()
  await visit(other.page, '/stories')
  await expect(other.page.getByText(title)).toHaveCount(0)
})

test('delete a game, then the story', async ({ page, user: _ }) => {
  const title = await createStory(page, HOUSE)
  for (let i = 0; i < 2; i++) {
    await newGame(page)
    await button(page, 'Go inside').click()
    await backToStory(page)
  }
  await expect(games(page)).toHaveCount(2)

  await page.getByRole('button', { name: 'Delete this game' }).first().click()
  await expect(games(page)).toHaveCount(1)

  await button(page, 'Delete').click()
  await expect(page.getByRole('heading', { name: 'Stories', exact: true })).toBeVisible()
  await expect(page.getByText(title)).toHaveCount(0)
})
