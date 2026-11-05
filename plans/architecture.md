# Architecture: adventure-game on Phoenix LiveView

Status: decided (2026-10-28). Chronicles is a try-out: a rebuild of `../adventure-game`
(a React app with the engine, plus a Node API on MongoDB) as one Phoenix LiveView app.

## The shape

One Elixir app. The server owns all gameplay. The browser shows HTML and sends each click
over the LiveView WebSocket.

```
Browser  ──WebSocket──►  GameLive (one process per open tab)
                              │  handle_event("go", %{"exit" => "north"})
                              ▼
                         Engine (pure functions)  ◄── Version (the story JSON)
                              │  new state + events (log lines, confetti, ...)
                              ▼
                         Contexts: Accounts, Stories, Games
                              ▼
                           Postgres (Ecto)
```

## Decisions

1. **The engine runs on the server.** `app/src/useStory.ts` becomes pure functions:
   `new_game(version, input)`, `view(version, state)` and
   `apply(version, state, command)`, which returns the new state and the events (log
   lines, `confetti`, `shake`, …). The browser never gets the full story, so no spoilers
   and no fake wins. This is the "engine on the server" option from adventure-game's
   `plan-architecture.md`.
2. **Postgres with Ecto, not MongoDB.** The data is relational (stories, versions,
   games, series, users), and Ecto gives foreign keys with cascades, `phx.gen.auth`,
   changesets, migrations and the SQL sandbox for tests. Locally Postgres runs in
   Podman; in production on Fly, next to the app.
3. **The story format stays.** A version's content is the same JSON as in adventure-game,
   stored in a `jsonb` column. The game state is `jsonb` too. Story, version and game
   keep their roles: versions are immutable, a story points at its head, a game pins a
   version. Freeze the format while adventure-game is still in use, or each change
   has to go into both engines.
4. **Autosave after every move.** No Save button and no "Back to last save". After an
   ending: "Play again" or "Back to overview". A finished game stays final. A save point
   can come back later as a `checkpoint` field on the game.
5. **No move history.** Only the current state is stored. Undo or replay, if ever added,
   cannot cover games from before then.
6. **The game lives in the LiveView process.** `mount` loads the game, each event runs
   the engine and writes to the database. No GenServer per game until multiplayer or
   chat; the engine is pure, so that change only moves who calls it.
7. **A small JSON API, only for tools.** The story skills, `model-course.build.mjs`
   and the story tests use HTTP. Chronicles keeps only what they need: login, read a
   story and a version, save a story, series. Token with `Phoenix.Token`. Each route
   calls the same context function as the LiveView.
8. **IDs.** Ecto's default integer ids. Stories get a unique `slug` for URLs such as
   `/stories/the-front-door`.
9. **Login.** `phx.gen.auth` as generated (email, magic link, optional password), plus an
   invite code on signup. Production needs an email provider; development uses the
   local mailbox.
10. **Import.** A one-time script copies the head version of each story worth keeping,
    plus the series. No old versions, games or users: there are no real users yet.
11. **Tests.** The engine tests are ported to ExUnit. adventure-game's Playwright suite
    (`e2e/`) finds things by role and text only, so it is the acceptance test for the
    rebuild.
    Its journeys now live in Chronicles' own `e2e/`, changed for email login, autosave and
    the new pages. The journeys for dropped features (saving, back to last save, asking
    to save when leaving, password login) are gone.

## Steps

1. Postgres in Podman, Chronicles generated with Ecto and `phx.gen.auth`.
2. Port the engine, test first.
3. `GameLive`: play a story from the imported data.
4. The story picker, editor, upload, account pages and series.
5. Deployment on Fly with Postgres.
