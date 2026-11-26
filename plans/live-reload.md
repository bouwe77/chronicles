# Live reload

Status: built (2026-11-26).

## What it is

An author plays their own story, sees something to improve, and changes the story in
another tab (the editor, the API or an agent). When the new version is saved, the open
game moves to it by itself, at the same point in the story. No new game by hand, no
playing the same moves again.

It works by **replaying the moves**, not by merging state. `Engine.move/3` is a pure
function, so a game's state is the starting state plus every command. Replaying the old
commands on the new version gives exactly the state a real player would have after the
same choices. So the result is correct by construction, and a move that no longer works
shows itself: `move/3` returns an error.

## How it works for the author

1. The author starts a game of their own story. It records its commands and its random
   picks. Other players' games record nothing.
2. The author plays. Each successful move is stored.
3. The author saves a new version in another tab. `Stories` broadcasts it on
   `Chronicles.PubSub` once the save is committed.
4. The open game tab hears it and calls `Games.reload/2`: a new game on the new
   version, the old picks, the old moves replayed. The new game is saved, the old one is
   deleted, and the tab navigates to the new game with a flash.
5. The new game records too, so this repeats with every save.

Saving a draft in the editor doesn't trigger it: only a new version does. A closed tab
doesn't reload; that game stays on its old version, like today.

## Decisions

1. **Record only for the story's author.** A game records when its player is the
   story's `author`. Other games store nothing, to save space. Recording is always on
   for authors, because a replay needs every move from the start; a recording that
   starts halfway can't replay.
2. **Randomness: reuse the old picks.** Some stories pick random values at the start
   (`context.randomize`), for example which room the weapon is in. A reload must reuse
   them. So the game picks the random values first, stores them, and then starts. The
   stored values are then always the real picks.

   On reload, each old pick must still be one of the allowed values in the new version.
   If one isn't, the replay fails and the game starts fresh with new random values.
   Keys without an old pick are picked at random. All picks happen before the first
   move, so "start fresh" is the only option when a pick fails.
3. **Moves are stored by id.** The game stores the id of an exit or action, not its
   button text (`name`). So the author can change button text freely, and the replay
   still works. The replay only stops when an id changes or is removed: the author
   lands one click before that move and clicks the new exit.
4. **Replay until something fails, keep what worked.** One loop over the commands that
   stops at the first error. This also covers "the first move fails" (0 of n) and "the
   new version ends the game earlier" (the next move returns `:ended`). A game that ends
   during the replay shows that ending.
5. **Delete only the replaced game**, through `Games.delete_game/2`, also when the replay
   fails. `delete_game/2` already deletes the old version when nothing uses it. The
   author's other games of the story stay.
6. **No toggle.** A game reloads when it records, so: when the player is the author.
   A toggle would need server state that survives `push_navigate` (the debug panel is
   only shown and hidden in the browser). The only case for not reloading is comparing
   old and new behaviour, which is rare; a toggle is in the backlog for when it isn't.
7. **Flashes.** Full replay: `:info`, hides after 3 seconds. Partial replay or fresh
   start: `:error`, stays until clicked away, because the author was set back.

This changes the backlog's "we don't store a move history": we do now, for author games.

## Code changes

### `Chronicles.Engine.State`

Two fields, both `nil` for games that don't record:

- `commands`, `{:array, :any}`: the successful moves, oldest first, as JSON lists:
  `["go", id]`, `["act", id]`, `["wait"]`, `["take", id]`, `["drop", id]`.
  `["wait"]` is separate because `{:act, :wait}` would become `["act", "wait"]` in
  JSON and clash with a story action with the id `"wait"`. `{:notes, text}` is not
  recorded: it is not a move.
- `picks`, `:map`: the `randomize` key → the value `new_game` picked.

No migration: `State` is one `jsonb` column.

### `Chronicles.Engine.new_game`

Takes the picks instead of making them: `new_game(version, input, picks)`, and merges
`picks` into the context where it now merges the random values. The random values come
from a separate `Engine.random_picks/1`, which `Games`, the test helper `Play` and
`mix chronicles.playthrough` call before `new_game`. The check whether old picks are still allowed lives in `Games.reload/2`,
not here.

Why not read the picks from the game after it started: the first room can already
change those values (its `sideEffects`), so the game could store the wrong ones.

### `Chronicles.Games`

- `start_game/2` and `continue_game/2` both build a game the same way. One private
  helper makes the picks, calls `new_game`, inserts the game, and sets `commands: []`
  and `picks` when the user is the story's `author`. This is the **only** author check.
- `play/2` appends the command when `state.commands` is a list. No author check: `nil`
  means "not recording".
- `reload/2`, new: takes the scope and the old game, and loads the story's head version.
  1. Check the old picks against the new `randomize` (decision 2). Keys without an old
     pick get `Engine.random_picks/1`. On a failure, use only new random picks and replay no
     commands.
  2. `Engine.new_game(content, state.context["input"], picks)`.
  3. `Enum.reduce_while/3` over the commands with `Engine.move/3`; stop at the first
     `{:error, _}`.
  4. Copy `context["notes"]` from the old game.
  5. Insert the new game (same user, the new version, the same `from_game_id`), and
     delete the old one with `delete_game/2`, in one transaction.
  6. Return `{:ok, game, result}`: `:replayed`, `{:stopped, replayed, total, command}`
     or `{:new_pick, key, value}`. `GameLive` turns it into the flash, so the context
     has no UI text. A game that doesn't record gives `{:error, :not_recording}`.

### `Chronicles.Stories`

`save_story/3` and `save_stories/2` broadcast `{:new_version, story_id}` on topic
`"story:#{story_id}"` for each saved story, after their transaction returns `{:ok, _}`.

Why not earlier: when several stories are saved at once, the save can still fail and be
undone. A message sent before the save is final would make the tab reload to a version
that doesn't exist. So the message goes out only after the save is final, and not in
the private `new_version/2`.

`create_story/4` doesn't broadcast: no game of a new story exists yet.

### `ChroniclesWeb.GameLive`

- On a connected mount, subscribe to the story's topic when `state.commands` is not
  `nil`.
- `handle_info({:new_version, _}, socket)`: call `Games.reload/2`, then `put_flash` and
  `push_navigate` to the new game.

## Flash messages

| Case | Kind | Message |
|---|---|---|
| All moves replayed | `:info` | "Reloaded on the new version." |
| A move failed | `:error` | "Replayed 14 of 20 moves. Move 15 (go: front_door) is no longer possible." |
| A pick can't be reused | `:error` | "Started a new game: weapon_room can no longer be attic." |

The failed move is shown as stored, so an action shows its id. All text goes through
`gettext`.

## Tests

- `Games`: an author game records commands and picks; another user's game doesn't;
  `:notes` is not recorded.
- `Games.reload/2`: a full replay; a renamed exit `name` still replays; a replay that
  stops at a removed exit id; a pick that is
  no longer allowed starts fresh; an ending reached during the replay; the old game is
  deleted; notes and `from_game_id` are kept.
- `Stories`: `save_stories/2` that fails on a later story broadcasts nothing.
- `GameLive`: a new version of the story navigates an author's game to the new game
  with the flash; a non-author's game stays.