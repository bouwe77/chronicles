import { button, createStory, expect, newGame, reload, test, visit } from './helpers'

const HOUSE = `- porch
  - exit: hall "Go inside"
- hall
`

test('switch the language to Dutch and back', async ({ page, user: _ }) => {
  await page.getByRole('link', { name: 'NL', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Verhalen', exact: true })).toBeVisible()

  // The choice stays on the account, whatever the browser says.
  await reload(page)
  await expect(page.getByRole('heading', { name: 'Verhalen', exact: true })).toBeVisible()

  await page.getByRole('link', { name: 'EN', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Stories', exact: true })).toBeVisible()
})

test('notes, when the story allows them', async ({ page, user: _ }) => {
  await createStory(page, HOUSE)
  const story = page.url()
  await newGame(page)
  await expect(button(page, 'Notes')).toHaveCount(0)

  await visit(page, story + '/edit')
  await page.getByRole('checkbox', { name: 'Players get a notes panel' }).check()
  await button(page, 'Save').click()
  await expect(page.getByText('Saved. New games play this version.')).toBeVisible()

  await visit(page, story)
  await newGame(page)
  await button(page, 'Notes').click()
  await page.getByRole('textbox', { name: 'Notes' }).fill('The bell is upstairs.')
  // Notes save as you type.
  await page.waitForTimeout(1000)

  await reload(page)
  await button(page, 'Notes').click()
  await expect(page.getByRole('textbox', { name: 'Notes' })).toHaveValue('The bell is upstairs.')
})
