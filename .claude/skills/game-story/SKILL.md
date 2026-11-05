---
name: game-story
description: Create, edit or delete Chronicles stories through the JSON API on port 9278, and test them with the real engine. Use when the user wants to write, add, change, fix, re-tag or delete a story, or a location/room, exit, item, action or ending in one, anything that saves story content in this repo.
---

# Game story authoring

This skill covers saving, editing, testing and deleting stories. What goes inside a
story (fields, conditions, actions, supplies, endings, where text goes, and what makes a
story good and valid) is in one document:

📖 **[`docs/story-format.md`](../../../docs/story-format.md)**: read it first, then come
back here to save.

## How a save works

`PUT /api/stories/<slug>` with `{"content": {...}}` saves content as the story's new head
version, in one transaction. It never changes an existing version, so games in progress
keep the content they started with; the previous head is deleted when no game plays it.
A new slug creates a **private** story. Leave it private unless the user asks for
public (they switch it on the story page).

The slug is the story's identity and its URL: kebab-case, for example `the-front-door`.
The content has no id or slug field.

## Prerequisites

The app must run on `http://localhost:9278`. If it can't be reached, ask the user to
start it (`mix phx.server` in the repo root).

## Log in

Every API call except the login needs a token. Log in with `CHRONICLES_EMAIL` and
`CHRONICLES_PASSWORD` from the shell profile; if they are not set, ask the user to set
them. The account needs a password: an account that only uses email links sets one in
Settings. The token lasts a day. Keep it in a file, because shell variables do not last
between commands:

```bash
jq -n --arg email "$CHRONICLES_EMAIL" --arg password "$CHRONICLES_PASSWORD" '{email: $email, password: $password}' \
  | curl -s -X POST http://localhost:9278/api/session -H "Content-Type: application/json" --data @- \
  | jq -r .token > "$TMPDIR/chronicles-token"
```

Every call below sends it with `-H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")"`.
A `401` means the token is missing or expired: log in again.

## Whose story?

A new story belongs to **the logged-in user**. Only an author or admin may save; a
player gets `403`. An author changes only their own stories; an admin may change any
story, which keeps its author. If the user did not say whose story it is, ask. An admin
changes roles at `/admin/users`.

## Create or edit a story

Keep the JSON in a temp file outside the repo (for example in your scratchpad).

```bash
# Edit: fetch the head content
curl -s -H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")" \
  http://localhost:9278/api/stories/the-front-door | jq .data.content > "$TMPDIR/story.json"

# … write or edit story.json …

# Save: wrap it as {content} and PUT it
jq '{content: .}' "$TMPDIR/story.json" \
  | curl -s -H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")" -X PUT \
    http://localhost:9278/api/stories/the-front-door -H "Content-Type: application/json" --data @-
```

- **New story:** skip the fetch, and pick a new slug. `GET /api/stories` lists the ones
  you can see; another author's private story is not listed, and saving to its slug
  answers `403`, so then pick another.
- **The save checks first and stores nothing on an error**, so it is also your
  validate step. Answers:
  - `200 {"data": {slug, title, tags, visibility, author, updated_at, content}}`: report
    the slug and the title.
  - `422 {"errors": [...]}`: every problem, one line each. Fix them and save again.
  - `403`: you are a player, or the story belongs to another author.

## Test it before you save

Play scripted paths with the real engine, from the repo root:

```bash
mix chronicles.playthrough "$TMPDIR/story.json" "$TMPDIR/paths.json"
```

`paths.json` maps a name to steps and the expected result:
`{"shortest win": {"steps": ["go:hall", "take:key", "open_door"], "expect": "win"}}`. A
step is `go:<exit label or room id>`, `take:<item id>`, `drop:<item id>`, `wait` or an
action key; `expect` is `win`, `loss`, `none` or `broke`. Add `"input": {...}` for a story
that takes input. The task checks the content like a save does, prints one line per path,
and fails when a path ends otherwise.

## Delete a story

One call removes the story with all its versions and every game of them, other players'
games included:

```bash
curl -s -H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")" -X DELETE \
  http://localhost:9278/api/stories/the-front-door
```

`204` means it is gone. Confirm with the user before you delete. A story that a series
names answers `422`: change or delete the series first.

## Series

A series links stories in order, so that winning one unlocks the next. The stories carry
the link themselves (an ending's `output`, the next story's `input`; see
[Series: input and output](../../../docs/story-format.md#series-input-and-output)). The
series only names them. Save every story first, then the series:

```bash
jq -n '{title: "The Number", stories: ["the-number", "the-number-returns"]}' \
  | curl -s -H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")" -X PUT \
    http://localhost:9278/api/series/the-number -H "Content-Type: application/json" --data @-
curl -s -H "Authorization: Bearer $(cat "$TMPDIR/chronicles-token")" http://localhost:9278/api/series
```

A `PUT` creates or replaces the series, after checking each story's head content; a
series that can't be played answers `422` with the reasons. A story is in at most one
series. Saving a story does not run these checks, so after you change an ending's
`output` or an `input`, `PUT` the series again to check it. `DELETE /api/series/<slug>`
removes a series; its stories stay. Test a sequel with `mix chronicles.playthrough` and
an `"input"` on its paths.

## Workflow

1. Check the app is reachable and [log in](#log-in).
2. For an edit, fetch the head content. Draft the content per
   [`docs/story-format.md`](../../../docs/story-format.md). The save checks the hard
   rules; the conventions in it you check yourself.
3. Run the format's [Self-check before finalising](../../../docs/story-format.md#self-check-before-finalising),
   and play at least the shortest win and one loss with `mix chronicles.playthrough`.
4. **Check the `tags` with the user before you save.** Tags drive the tag filter on the
   story list, so the user decides them. `GET /api/stories` lists every story's tags;
   propose tags for this story, reuse an existing tag where one fits, and save only after
   the user agrees. Do this for a new story and for any edit that changes tags.
5. Save. Report the slug, the title and the story's URL (`http://localhost:9278/stories/<slug>`).
6. On a `422`, read `errors`: each one names the failing field (a JSON Schema path like
   `/locations/hall`, or a content rule). Fix the JSON and save again. The content rules
   only run once the shape is valid, so a second round can show new errors.
