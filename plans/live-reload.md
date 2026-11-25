# Live reload

Status: designed (2026-11-25), not built.

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
   `Chronicles.PubSub`.
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
2. **Randomness: reuse the old picks.** `Engine.new_game/2` is the only place with
   randomness (`context.randomize`). An author game stores its picks. On reload, for each
   key in the new version's `randomize` that has an old pick, the old pick must still be
   one of the allowed values; otherwise the replay fails and the game starts fresh, with
   new random values. Keys without an old pick are picked at random. All picks happen
   before the first move, so "start fresh" is the only option when a pick fails.
3. **Exit labels stay as they are.** An exit's label is its key, so a renamed label stops
   the replay at that move. The author lands one click before it and clicks the renamed
   exit. Whether exits (and endings) should get an id is a separate backlog item.
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
  `["go", label]`, `["act", id]`, `["wait"]`, `["take", id]`, `["drop", id]`.
  `["wait"]` is separate because `{:act, :wait}` would become `["act", "wait"]` in
  JSON and clash with a story action with the id `"wait"`. `{:notes, text}` is not
  recorded: it is not a move.
- `picks`, `:map`: the `randomize` key → the value `new_game` picked.

No migration: `State` is one `jsonb` column.

### `Chronicles.Engine.new_game`

Takes the picks to use: `new_game(version, input \\ nil, picks \\ %{})`. A key in
`picks` gets that value instead of a random one. The check whether old picks are still
allowed lives in `Games.reload/2`, not here.

### `Chronicles.Games`

- `start_game/2` and `continue_game/2` both build a game the same way. One private
  helper inserts it, and sets `commands: []` and `picks` when the user is the story's
  `author`. `picks` is `Map.take(state.context, keys of randomize)`: right after
  `new_game` the context holds the picks. This is the **only** author check.
- `play/2` appends the command when `state.commands` is a list. No author check: `nil`
  means "not recording".
- `reload/2`, new: takes the scope and the old game, and loads the story's head version.
  1. Check the old picks against the new `randomize` (decision 2). On a failure, replay
     no commands.
  2. `Engine.new_game(content, state.context["input"], picks)`.
  3. `Enum.reduce_while/3` over the commands with `Engine.move/3`; stop at the first
     `{:error, _}`.
  4. Copy `context["notes"]` from the old game.
  5. Insert the new game (same user, the new version, the same `from_game_id`), and
     delete the old one with `delete_game/2`, in one transaction.
  6. Return `{:ok, game, flash}`, with `flash` as `{:info | :error, message}`.

### `Chronicles.Stories`

`new_version/2` broadcasts `{:new_version, story_id}` on topic `"story:#{story_id}"`
after the transaction succeeds.

### `ChroniclesWeb.GameLive`

- On a connected mount, subscribe to the story's topic when `state.commands` is not
  `nil`.
- `handle_info({:new_version, _}, socket)`: call `Games.reload/2`, then `put_flash` and
  `push_navigate` to the new game.

## Flash messages

| Case | Kind | Message |
|---|---|---|
| All moves replayed | `:info` | "Reloaded on the new version." |
| A move failed | `:error` | "Replayed 14 of 20 moves. Move 15 (go: front dor) is no longer possible." |
| A pick can't be reused | `:error` | "Started a new game: weapon_room can no longer be attic." |

The failed move is shown as stored, so an action shows its id. All text goes through
`gettext`.

## Tests

- `Games`: an author game records commands and picks; another user's game doesn't;
  `:notes` is not recorded.
- `Games.reload/2`: a full replay; a replay that stops at a renamed exit; a pick that is
  no longer allowed starts fresh; an ending reached during the replay; the old game is
  deleted; notes and `from_game_id` are kept.
- `GameLive`: a new version of the story navigates an author's game to the new game
  with the flash; a non-author's game stays.