import { backToStory, button, createStory, ending, expect, gameLog, games, newGame, panel, reload, room, test, visit } from './helpers'

const HOUSE = `- porch
  - exit: hall "Go inside"
  - item: umbrella
  - action: ring_bell "Ring the bell" -> "A bell rings upstairs."
- hall
  - exit: cellar
- cellar
  - ending: win -> "You found the cellar."
`

test('items and actions', async ({ page, user: _ }) => {
  await createStory(page, HOUSE)
  await newGame(page)

  await button(page, 'Ring the bell').click()
  await expect(gameLog(page)).toContainText('A bell rings upstairs.')

  await panel(page, 'Items').getByRole('button', { name: 'Take' }).click()
  await expect(panel(page, 'Carrying')).toContainText('Umbrella')
  await expect(panel(page, 'Items')).toHaveCount(0)

  await button(page, 'Go inside').click()
  await expect(room(page)).toHaveText('Hall')
  await panel(page, 'Carrying').getByRole('button', { name: 'Drop' }).click()
  await expect(panel(page, 'Carrying')).toContainText('Nothing yet')
  await expect(panel(page, 'Items')).toContainText('Umbrella')
})

test('every move is saved: a game resumes where it was', async ({ page, user: _ }) => {
  await createStory(page, HOUSE)
  await newGame(page)
  await panel(page, 'Items').getByRole('button', { name: 'Take' }).click()
  await button(page, 'Go inside').click()
  await expect(room(page)).toHaveText('Hall')

  await reload(page)
  await expect(room(page)).toHaveText('Hall')
  await expect(panel(page, 'Carrying')).toContainText('Umbrella')

  // Also from the story page.
  await backToStory(page)
  await games(page).click()
  await expect(room(page)).toHaveText('Hall')
  await expect(panel(page, 'Carrying')).toContainText('Umbrella')
})

test('after an ending, play again', async ({ page, user: _ }) => {
  await createStory(page, HOUSE)
  await newGame(page)
  await button(page, 'Go inside').click()
  await button(page, 'Cellar').click()
  await expect(ending(page)).toContainText('You won!')

  await ending(page).getByRole('button', { name: 'Play again' }).click()
  await expect(ending(page)).toHaveCount(0)
  await expect(room(page)).toHaveText('Porch')

  // The finished game stays finished, next to the new one.
  await backToStory(page)
  await expect(games(page)).toHaveCount(2)
  await expect(games(page).filter({ hasText: 'Won' })).toHaveCount(1)
})

test('editing a story does not change a game in progress', async ({ page, user: _ }) => {
  await createStory(page, HOUSE)
  const story = page.url()
  await newGame(page)
  await button(page, 'Go inside').click()
  await expect(room(page)).toHaveText('Hall')

  // A new attic, reached from the hall one way, written in the editor's JSON.
  await visit(page, story + '/edit')
  await button(page, 'Everything, as one JSON').click()
  const text = page.locator('#part-form textarea')
  await expect(text).toHaveValue(/"locations"/)
  const content = JSON.parse(await text.inputValue())
  content.locations.attic = { name: 'Attic', description: 'Dusty.', exits: {} }
  content.locations.hall.exits['Climb up'] = { to: 'attic' }
  await text.fill(JSON.stringify(content, null, 2))
  await expect(page.getByText('No problems found.')).toBeVisible()
  await button(page, 'Save').click()
  await expect(page.getByText('Saved. New games play this version.')).toBeVisible()

  // The game keeps the version it started on; a new game gets the edit.
  await visit(page, story)
  await games(page).click()
  await expect(room(page)).toHaveText('Hall')
  await expect(button(page, 'Climb up')).toHaveCount(0)

  await backToStory(page)
  await newGame(page)
  await button(page, 'Go inside').click()
  await expect(button(page, 'Climb up')).toBeVisible()
})
