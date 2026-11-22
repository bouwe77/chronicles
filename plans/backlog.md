# Backlog

Things we chose not to do yet, did differently on purpose, or found along the way. Each
item says why it waits. Remove an item when it is done or dropped.

## Before going live

- **The acceptance tests read the dev mailbox.** `e2e/` logs in through
  `/dev/mailbox/json`, which only exists in development. Against Fly they need another
  way to get a login link (a test-only route).
- **Deployment on Fly with Postgres.** Step 5 of the plan. Includes the secrets and a
  production database.
- **The first admin in production.** There is no sign-up, and only an admin invites
  users. Production needs a way to create the first admin, such as a release task.
- **An email provider for login links.** Production login uses magic links, which need
  a real mail service. Development uses the local mailbox.
- **The production import.** The stories and the saga `the-number`. The import task
  does stories; the saga can go through `PUT /api/sagas/:slug`. The first chapter's
  title is "The Number Rises" in the source file and in dev.
- **The API rate limit counts per machine.** `ChroniclesWeb.RateLimit` keeps its counts
  in memory. With more than one Fly machine, each has its own count; then it needs a
  shared store (Postgres, or Hammer with Redis). Set `RATE_LIMIT` on Fly (default 100).

## Playing

- **Save points.** Not there for now (decision 4). Can come as a `checkpoint`
  field on the game.
- **Undo or replay.** Needs a move history, which we don't store (decision 5).
- **Multiplayer or chat.** Needs a process per game (decision 6).
- **Time mode.** A real date and time ("Sun 5 Jul, 20:30") instead of turns, chosen per
  story. Designed, not built. See `plans/time-mode.md`.
- **Command mode.** Type commands instead of clicking buttons, chosen per story. Low
  priority: no story needs it yet. See `plans/command-mode.md`.

## Writing stories

- **The editor keeps one draft per story, not per tab.** Two tabs on the same story
  overwrite each other's draft; the last change wins. Text that isn't valid JSON yet is
  not kept either. Fine for one author at a time.
- **The editor shows JSON keys in alphabetical order.** `jsonb` and Elixir maps don't keep
  the order an author wrote them in. Harmless, but less readable for big parts.
- **The editor's toolbar alignment.** The rename and connect forms don't line up neatly
  with the buttons. Part of the restyle.
- **Sagas in the app.** Sagas are created and changed through the API only. The saga
  page (`/sagas/:slug`) is the natural place to create and edit them later.
- **Key mapping in a saga.** If one story is used in two sagas with different input
  key names, the saga could map them. Add it when that happens.
- **A picture per location.** An optional photo or picture that the game shows in that
  location. How images are stored and shown is not decided.
- **Regions.** An optional `region` on a location and an `inRegion` condition, so a rule
  like "lose warmth in the forest" needs one condition instead of an `anyOf` of rooms.
  Waits until a story has about 10 rooms that share a rule.
- **Compare two values in a condition.** For example `/agility` against
  `/monster/speed`. One form per comparator or a general `compare`, and whether a side
  can be a supply, is open. Waits until a story needs it.
- **Dialogue trees.** Long branching conversations need many flags and gates today.
  First check how hard `a-word-with-vale` was to write; if it was painful, try a small
  helper (a `node` per conversation in context) before a full dialogue structure.
- **AI chat for writing stories.** A chat in the app where an LLM writes the story and
  the validator's errors go back to it until the story is valid. Waits until the
  editor and upload are not enough. Open: the user's own API key or a server key,
  which providers, a new story only or also changes, and save at once or show first.

## Accounts and admin

- **Some text stays English in Dutch.** The emails (login link, invite), because
  they are built in the core and Gettext lives in the web layer. The months in dates
  ("28 Oct 2026"), because `Calendar.strftime` only knows English names. A few
  validation messages that the core writes itself (the username rules). Errors from the story validator and the sketch stay English on
  purpose: they are for authors and AI tools.
- **No "view as player".** Admins can list every story ("All stories"), but there is no
  switch to see the app as a player sees it. Log in as a player account for that.
- **Creating users is in the app only.** There is no API for it.
- **The header shows your email.** Other places show the username; the header could too.
- **Social login with Google and GitHub.** Library chosen (Assent), not built. See
  `plans/social-login.md`. Waits until logging in by email link feels slow to users.
- **Invite codes.** Admins invite users one by one. Invite codes an admin manages could
  let more people in at once: a code, an optional email it is bound to, an expiry date
  and a maximum number of uses. Waits until inviting one by one is too much work.

## Look and feel

- **The flash covers the header links.** A flash (like "Welcome back") sits over the
  language switch and "Log out" until it is closed or the page changes.

- **The restyle.** The pages work but use the generated look. The login and register
  pages still use daisyUI classes in places (inputs, alerts, dividers, the theme switch);
  `AGENTS.md` asks for our own Tailwind components instead.
