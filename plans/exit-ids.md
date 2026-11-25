# Exit ids

Status: built (2026-11-26).

## What it is

An exit's label is both the text on its button and its identity: the key in `exits` and
the `{:go, label}` command. So fixing a typo in a label changes which exit it is; for
example, live reload stops its replay there. Exits are also the only part of the format
that works like this.

Every other part follows one pattern: the key (or `id`) is the identity, and a required
field holds the text the player sees. Locations, items and supplies call that field
`name`; actions call it `description`.

## Decisions

1. **The exit key becomes an id, and exits get a required `name`** for the button text:

   ```json
   "exits": {
     "north": { "name": "north", "to": "hall" },
     "turbolift": { "name": "Take the turbolift", "to": "bridge" }
   }
   ```

   Commands use the id: `{:go, id}`. Fixing a typo in a `name` changes nothing else.
2. **Actions move from `description` to `name`.** Then one rule holds for the whole
   format: the key or `id` is the identity, `name` is the short text the player sees.
   `description` keeps meaning a longer text (a location's arrival line, an item's
   look).
3. **The redundancy is small.** In the dev database (19 stories, 426 exits), only 94
   exits (22%) have a label that already works as an id, and all of them are `north`,
   `south`, `east`, `west`, `up` and `down`. The other 78% are texts like "Back to the
   passenger deck", which need a different id anyway.
4. **Ids from names.** The migration, the sketch and the editor's connect form make the
   id from the name in snake_case ("Take the turbolift" → `take_the_turbolift`), so
   authors don't type it twice. An author can rename the id later.
5. **Migration in one go.** The app is not live, so all stories and fixtures change at
   once. Author games recorded before the change can't replay their moves; live reload
   then starts a fresh game, as it already does when a replay fails.

## Changes

- `priv/schemas/version.json`: exits require `name`; actions use `name` instead of
  `description`.
- `Engine`: `view` shows the exit's and action's `name`; the `> ...` log line of a move
  uses the `name`.
- `Validator`: messages name exits by id.
- `Authoring`, `Sketch`, `EditStoryLive`: new exits and actions get a `name`; the connect
  form asks for a name and makes the id.
- `docs/story-format.md`, `docs/story-skill/SKILL.md`, `.claude/skills/detective-story`:
  the new fields. The rule "exit labels are the player's vocabulary" becomes about
  `name`.
- A one-off migration of every version's content, and the test and e2e fixtures.

## Not in v1

- **Ending ids.** Endings are a list without ids. An id would help features that name an
  ending ("endings found: 2 of 5", a saga that branches on the ending reached). Add when
  such a feature comes.
