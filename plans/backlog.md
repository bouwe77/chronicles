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
- **The production import.** The stories and the saga `the-number`. The stories go
  through the upload page or `PUT /api/stories/:slug`, the saga through
  `PUT /api/sagas/:slug`. The first chapter's title is "The Number Rises" in the
  source file and in dev.
- **The API rate limit counts per machine.** `ChroniclesWeb.RateLimit` keeps its counts
  in memory. With more than one Fly machine, each has its own count; then it needs a
  shared store (Postgres, or Hammer with Redis). Set `RATE_LIMIT` on Fly (default 100).

## Playing

- **Save points.** Not there for now (decision 4). Can come as a `checkpoint`
  field on the game.
- **Undo or replay.** Needs a move history, which we don't store (decision 5). Author
  games do store their moves now, for live reload (`plans/live-reload.md`).
- **The same game in two tabs.** Each tab has its own copy of the game and doesn't see
  moves made in the other. A move in an out-of-date tab is saved over the newer game, so
  the other tab's moves are lost. With live reload, the second tab ends on "not found".
  Preferred fix: don't support it. Either refuse a second open tab of the same game (for
  example with a `Registry` per game id), or, if that isn't simple, refuse a save when
  the game changed since the tab loaded it (Ecto's `optimistic_lock`). Waits until
  someone runs into it.
- **A toggle for live reload.** An author's game always follows a new version. Add a
  toggle when an author needs to keep playing the old version, for example to compare.
  It needs state that survives `push_navigate`, such as a URL parameter.
- **Multiplayer or chat.** Needs a process per game (decision 6).
- **Time mode.** A real date and time ("Sun 5 Jul, 20:30") instead of turns, chosen per
  story. Designed, not built. See `plans/time-mode.md`.
- **Command mode.** Type commands instead of clicking buttons, chosen per story. Low
  priority: no story needs it yet. See `plans/command-mode.md`.
- **Random events during play.** A chance on a rule or timeline event ("each turn, 10%
  chance a patrol arrives"). Today randomness only happens at game start
  (`context.randomize`). Fine if live reload can't replay it exactly; it only needs to
  work for players. Not planned yet.

## Writing stories

- **Markdown outside the log.** `descriptionWhenCarried` and the story overview stay
  plain text (decision 2 of the Markdown plan). Add when a story needs structure there.
- **Links in log text.** Rejected on save for now: they lead players out of the game.
  Add (http/https only, new tab) when a story, like the course, really needs one.
- **A Markdown preview in the story editor.** Authors see the result only by playing.
- **More cues.** Effects like `flash`, `blackout`, `heartbeat`, weather and sound. Ideas
  only; no story asked for them yet. See `plans/more-cues.md`.
- **The editor keeps one draft per story, not per tab.** Two tabs on the same story
  overwrite each other's draft; the last change wins. Text that isn't valid JSON yet is
  not kept either. Fine for one author at a time.
- **The editor shows JSON keys in alphabetical order.** `jsonb` and Elixir maps don't keep
  the order an author wrote them in. Harmless, but less readable for big parts.
- **The editor's toolbar alignment.** The rename and connect forms don't line up neatly
  with the buttons. Part of the restyle.
- **Key mapping in a saga.** If one story is used in two sagas with different input
  key names, the saga could map them. Add it when that happens.
- **A picture per location.** An optional picture that the game shows in that location.
  Decided (a banner in the log), not built. See `plans/location-images.md`.
- **Regions.** An optional `region` on a location and an `inRegion` condition, so a rule
  like "lose warmth in the forest" needs one condition instead of an `anyOf` of rooms.
  Waits until a story has about 10 rooms that share a rule.
- **Compare two values in a condition.** For example `/agility` against
  `/monster/speed`. One form per comparator or a general `compare`, and whether a side
  can be a supply, is open. Waits until a story needs it.
- **World and story.** Split the map (a world) from the game on top of it (a story), so
  many stories can share one world. Designed, not built. See `plans/world-and-story.md`.
- **Dialogue trees.** Long branching conversations need many flags and gates today.
  First check how hard `a-word-with-vale` was to write; if it was painful, try a small
  helper (a `node` per conversation in context) before a full dialogue structure.
- **AI chat for writing stories.** A chat in the app where an LLM writes the story and
  the validator's errors go back to it until the story is valid. Waits until the
  editor and upload are not enough. Open: the user's own API key or a server key,
  which providers, a new story only or also changes, and save at once or show first.
- **Exit ids.** The exit key becomes an id with a required `name`, and actions move from
  `description` to `name`. Designed, not built. See `plans/exit-ids.md`. Endings have no
  id either; add one when a feature names an ending.
- **The model course as a saga.** `the-model-course` could be one chapter per part, so
  it shows a saga in practice. Waits because a chapter only opens after the one before
  it is won, so nobody could skip to a later part.

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
