# Chronicles

Chronicles is a web app to write and play text adventure stories. A story is one JSON
file: locations, exits, items, actions and endings. The server runs the game, so players
never see the story ahead of time. Chronicles is AI-first: AI agents can write, check and
save stories through skills and a small JSON API.

## Getting started

You need Elixir and Erlang (versions in `.tool-versions`) and Postgres on `localhost`
with user `postgres` and password `postgres` (see `config/dev.exs`).

    mix setup
    mix phx.server

Then open [`localhost:9278`](http://localhost:9278). To sign up locally, use the invite
code `dev`. Login links arrive in the dev mailbox at
[`localhost:9278/dev/mailbox`](http://localhost:9278/dev/mailbox).

## Writing stories

- [`docs/story-format.md`](docs/story-format.md) describes the story format and what
  makes a story good. `priv/schemas/version.json` is its JSON Schema.
- [`.claude/skills/game-story`](.claude/skills/game-story/SKILL.md) lets an agent create,
  edit and test stories through the API of a running server.
- [`.claude/skills/detective-story`](.claude/skills/detective-story/SKILL.md) helps an
  agent design a fair, solvable mystery.
- The app also offers a story kit for any AI tool to download: the format, the schema
  and a skill in one zip.

## Acceptance tests

`e2e/` holds Playwright journeys that use the app only in the browser: sign up, write a
story, play it, share it. Start the server first, then:

    cd e2e
    npm install
    npx playwright install chromium
    npx playwright test

They run against `localhost:9278` with the dev invite code, and read login links from
the dev mailbox. Each test makes its own user and deletes it afterwards. Set `E2E_URL`
and `E2E_INVITE_CODE` to test another server.

## License

MIT, see [`LICENSE`](LICENSE).
