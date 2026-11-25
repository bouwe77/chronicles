# World and story

Status: designed (2026-11-26), not built. Check the decisions once more against the
engine and editor before building.

## What it is

Today a story holds everything: the map (locations and exits) and the game on top of it
(context, rules, actions, endings). This plan splits the two:

- A **world** is the map: locations, their exits, and what is always there.
- A **story** is a game played on a world: where you start, the state, the rules, the
  items and actions that matter for this story, and the endings.

One world can carry many stories. For example, one big city, with a detective story, a
heist and an escape built on it by different authors.

**The key simplification:** every story has a world, also when only one story uses it.
So there is one model, not two. A story that does not share its world just has its own,
one on one. That is the normal case.

All state lives in the game. A game never changes the world itself; it gets its own copy
of the world's state.

## Decisions

1. **The split.**
   - **World:** locations (`name`, `description`), exits, its own `context` with default
     values, and conditions (`visibleWhen`, `enabledWhen`, ...) that read only that
     context. For example, the bank door is `enabledWhen` `/bank_door_locked` is `false`,
     and the world starts it at `true`.
   - **Story:** everything else: its own context, rules, timeline, actions, items,
     supplies, endings, `starting_location`.
2. **What a story may do with the world.** Add to it (locations, exits, items, actions,
   `sideEffects`, extra conditions on world exits), read and change world state, and
   override a world default in its own `context.initial`. It never removes or renames
   world content; to hide an exit it uses `visibleWhen`. It does not replace a world
   `description` either; it adds text with `sideEffects` or `arrivalText`.
3. **The world never reads story state.** It cannot know which story runs on it. A
   story that ignores a world condition just lives with it: the bank stays locked and
   is not part of that story.
4. **Merge before play.** The server merges world + story into one normal story JSON,
   as it looks today, with one combined context. The engine, the validator (on the
   merged result) and live reload don't change.
5. **World state names are an interface.** A story uses `/bank_door_locked` by name. A
   world version that renames or removes it breaks that story; the check when the story
   moves to that world version catches it.
6. **Visibility controls building, not playing.** A private world: only its author
   builds stories on it. A public world: every author can. If a world becomes private,
   existing stories on it keep working; only new stories, and moving a story to a newer
   world version, are blocked. A public story on a private world is fine: players see
   only the merged result, and "private" protects the world from reuse, not from being
   seen. A world can't be deleted while a story uses it (a foreign key with
   `on_delete: :restrict`).
7. **A story always has a separate world.** Also one on one: then the story has its own
   private world, which nobody else uses. The story JSON names it (`"world": "<slug>"`)
   and has no `locations` of its own, only additions to world locations. So there is
   one way to fetch a world (`game → story version → world version`), one merge and one
   way to version it, whether the world is used once or a hundred times. We chose this
   over a `world` section that is either a slug or an inline world, because those two
   forms would leak into versioning, validation, the editor and the API.
8. **Authoring tools hide the two parts.** "New story" creates the world and the story
   together, with the same slug. The editor shows world and story as two tabs of one
   screen. The `game-story` skill saves the world first, then the story. A one-on-one
   world is a normal world, so its author can make it public later.
9. **Migration.** The app is not live, so every existing story becomes one world plus
   one story, in one go.

## Storage and versions

10. **Own tables: `worlds` and `world_versions`.** Not a `kind` of story. With a world
    behind every story, half of the `stories` rows would be worlds, and every list, the
    picker, sagas, the API and games would need a filter; one missing filter makes a
    world playable, and it has no `starting_location`. Separate tables make that
    impossible, and the database can check that a story pins a world version. The cost
    is a small `Worlds` context and an API controller.
11. **A story version pins a world version** (`world_version_id`, a foreign key with
    `on_delete: :restrict`). The pin is not in the JSON, like a game's pin on a story
    version.
    - A new story pins the world's current head.
    - Every next save copies the pin of the story version before it. So a change to the
      world never reaches a story by itself, and a typo fix never moves the world.
    - Moving to a newer world version is an explicit choice: a button in the editor, or
      a flag in the API. That save checks the story against the new world version and
      is rejected with the usual errors if it doesn't fit.
    - When the editor saves world and story together (decision 8, the one-on-one case),
      the story moves to the new world version in the same save.

Games keep pinning a story version, so a game never changes under a player.

## Not related to sagas

Sagas stay what they are: levels, a chain of chapters. Chapters can share a world or not.
This plan does not change them.

## Merging and editing

12. **Merge rules.** A story's `locations` hold its additions to the world:
    - A story location with a world id merges into that world location: its items,
      actions, `sideEffects` and exits are added.
    - A story location with a new id is a new location.
    - A story exit with the same label as a world exit adds conditions to it; the merge
      combines both with `allOf`. The story can't change the exit's other fields (`to`,
      `timeCost`); the validator rejects that.
    - A story can't set a world location's `name` or `description` (decision 2).
13. **The editor.** One screen with two groups of parts, "World" and "Story". On a shared
    world that is not yours, the world parts are read-only.
    - Reading tools (the overview, `reachable`, problems, "find uses") work on the
      merged content.
    - Writing tools (rename, connect, remove) change the side the part belongs to.
    - One Save button saves the world (if changed), then the story, pinned to the new
      world version (decision 11).
    - A world without a story has its own page, `/worlds/:slug/edit`: the same editor
      with only the world group.
    - The sketch fills both: locations and exits go to the world; items, actions and
      endings go to the story.
14. **The API.** `PUT /api/worlds/:slug` and `PUT /api/stories/:slug`, with an optional
    flag on the story to move to the newest world version.

## Later

Decide these when building:

- The upload page: one file per world and story, or one file with both.
- How the `game-story` skill and `docs/story-format.md` change: probably a world
  section and a story section, and the skill saves the world first.

## Not in v1

- **Items, rules and timeline in a world** (a fixed phone booth, shops that close at
  night). Start with context and conditions only; add them when a world needs them.
