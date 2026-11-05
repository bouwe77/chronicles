import { button, createStory, ending, expect, newGame, test } from './helpers'

test('create a story with an ending and play it to the end', async ({ page, user: _ }) => {
  await createStory(
    page,
    `- porch
  - exit: hall "Go inside"
- hall
  - exit: cellar
- cellar
  - ending: win -> "You found the cellar."
`,
  )
  await newGame(page)
  await button(page, 'Go inside').click()
  await button(page, 'Cellar').click()
  await expect(ending(page)).toContainText('You won!')
  await expect(ending(page)).toContainText('You found the cellar.')
})

test('a loss ending', async ({ page, user: _ }) => {
  await createStory(
    page,
    `- porch
  - exit: pit "Step forward"
- pit
  - ending: loss -> "You fell into the pit."
`,
  )
  await newGame(page)
  await button(page, 'Step forward').click()
  await expect(ending(page)).toContainText('You lost')
  await expect(ending(page)).toContainText('You fell into the pit.')
  await expect(button(page, 'Porch')).toHaveCount(0)
})
