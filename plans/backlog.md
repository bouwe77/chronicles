# Backlog

Things we chose not to do yet, did differently on purpose, or found along the way. Each
item says why it waits. Remove an item when it is done or dropped.

## Before going live

- **The acceptance tests read the dev mailbox.** `e2e/` logs in through
  `/dev/mailbox/json`, which only exists in development. Against Fly they need another
  way to get a login link (a password, or a test-only route).
- **Deployment on Fly with Postgres.** Step 5 of the plan. Includes the `INVITE_CODE`
  and other secrets, and a production database.
- **An email provider for login links.** Production login uses magic links, which need
  a real mail service. Development uses the local mailbox.
- **The production import.** The stories and the series `the-number`. The import task
  does stories; the series can go through `PUT /api/series/:slug`.
- **The API rate limit counts per machine.** `ChroniclesWeb.RateLimit` keeps its counts
  in memory. With more than one Fly machine, each has its own count; then it needs a
  shared store (Postgres, or Hammer with Redis). Set `RATE_LIMIT` on Fly (default 100).

## Playing

- **Save points.** Not there for now (decision 4). Can come as a `checkpoint`
  field on the game.
- **Undo or replay.** Needs a move history, which we don't store (decision 5).
- **Multiplayer or chat.** Needs a process per game (decision 6).

## Writing stories

- **The editor keeps one draft per story, not per tab.** Two tabs on the same story
  overwrite each other's draft; the last change wins. Text that isn't valid JSON yet is
  not kept either. Fine for one author at a time.
- **The editor shows JSON keys in alphabetical order.** `jsonb` and Elixir maps don't keep
  the order an author wrote them in. Harmless, but less readable for big parts.
- **The editor's toolbar alignment.** The rename and connect forms don't line up neatly
  with the buttons. Part of the restyle.
- **Series in the app.** Series are managed through the API only.
- **Series checks on a story save.** Saving a story doesn't re-check its series, so an
  edited ending can quietly break the link to the next story. `PUT` the series again to
  check it. A warning on save would help.

## Accounts and admin

- **Some text stays English in Dutch.** The emails (login link, confirmation), because
  they are built in the core and Gettext lives in the web layer. The months in dates
  ("28 Oct 2026"), because `Calendar.strftime` only knows English names. A few
  validation messages that the core writes itself ("is not valid" for the invite code,
  the username rules). Errors from the story validator and the sketch stay English on
  purpose: they are for authors and AI tools.
- **No "view as player".** Admins can list every story ("All stories"), but there is no
  switch to see the app as a player sees it. Log in as a player account for that.
- **Creating users is in the app only.** There is no API for it.
- **The API needs a password.** Accounts that log in with email links must set a
  password before they use the API or the story skills.
- **The header shows your email.** Other places show the username; the header could too.

## Look and feel

- **The flash covers the header links.** A flash (like "Welcome back") sits over the
  language switch and "Log out" until it is closed or the page changes.

- **The restyle.** The pages work but use the generated look. The login and register
  pages still use daisyUI classes in places (inputs, alerts, dividers, the theme switch);
  `AGENTS.md` asks for our own Tailwind components instead.
