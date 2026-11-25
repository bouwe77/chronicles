# Pursuers

Status: designed (2026-11-25), not built. Check the decisions once more against the
engine before building.

## What it is

An NPC that moves toward the player by itself: the monster in the three doors that comes
to the room you wait in, or the police that drive to the house after someone calls them.
The further away the NPC starts, the later it arrives.

Today an author can only fake this with tick rules: one rule per (NPC room, player room)
pair, with the shortest path worked out by hand. That is rooms × rooms rules per NPC, and
`run_rules` can chain two of them in one turn (each rule sees the state after the rules
before it), so the NPC jumps two rooms.

**The key simplification:** a pursuer is not a new kind of object. Its room is a normal
context value (`/monster` = `"room_a"`). The engine only adds one thing: on each turn it
moves that value one exit closer to the player. Everything else (getting caught, damage,
messages, endings) stays with the existing `rules`, `endings` and conditions.

## Story format

### Top-level `pursuers`

An optional array. Each entry:

| Field        | Type             | Notes |
| ------------ | ---------------- | ----- |
| `path`       | string           | **Required**; JSON Pointer to the context value that holds the pursuer's room, e.g. `"/monster"`. Must root at a key declared in `context.initial` or `context.schema`, like a patch effect. |
| `activeWhen` | condition        | Optional; any [condition](../docs/story-format.md#conditions). The pursuer only moves on a turn where it holds. Omit to chase from turn 1. This is how an alarm starts the chase, or how hiding stops it. |
| `every`      | integer (`>= 1`) | Optional (default `1`); the pursuer moves one exit on each turn where `turn % every == 0`. `2` is half speed. |

```json
"context": { "initial": { "alarm": false, "cop1": "station", "cop2": "harbour" } },
"pursuers": [
  { "path": "/cop1", "activeWhen": { "path": "/alarm", "equals": true } },
  { "path": "/cop2", "activeWhen": { "path": "/alarm", "equals": true }, "every": 2 }
]
```

The pursuer's room can still be set from anywhere else: `context.randomize` for a random
start, an action or timeline effect to move it (`replace /cop1 "station"` sends a cop back).

### New condition: `atPath`

`{ "atPath": "/monster" }` holds when the player's room equals the value at that path.
Without it, "the monster is in my room" needs one `allOf` per room. With it:

```json
"rules": [
  { "when": { "atPath": "/monster" },
    "effects": [{ "supply": "health", "by": -1 }],
    "sideEffects": [{ "type": "log", "text": "The monster lashes out at you!" }] }
],
"endings": [
  { "when": { "anyOf": [{ "atPath": "/cop1" }, { "atPath": "/cop2" }] },
    "outcome": "loss", "message": "A hand lands on your shoulder. \"Evening.\"" }
]
```

The validator checks that its path roots at a declared context key, like a `path` condition.

## Decisions

### When pursuers move

On each turn the clock reaches: timeline events, then **pursuers**, then rules, then
endings. On the last turn of an interaction this happens in `finish_turn`, after the
player's move, so a pursuer heads for the room the player just entered. Rules and endings
then see the pursuer's new room, so "caught" is checked in the same turn.

Interactions that cost no time (take, drop, `timeCost: 0`) reach no new turn, so
pursuers don't move. A `timeCost: 8` sleep moves a pursuer up to 8 times, one per crossed
turn, and an ending can stop the clock halfway, as it does today.

Pursuers move in array order, each one step. A pursuer that already shares the player's
room stays there.

### How the next step is picked

Breadth-first search from the pursuer's room to the player's room over the location
`exits`. The pursuer takes the first exit of a shortest path. A tie goes to the first exit
in the order the engine lists them (map order of the exit labels), so a game always plays
the same way.

The search **respects exit gates**: an exit only counts when its `visibleWhen` and
`enabledWhen` hold over the current state. A locked door keeps the monster out, which is a
mechanic an author will want. If there is no path, the pursuer stays where it is.

The gates are evaluated over the game state as it is. A gate with `at` reads the
_player's_ room, not the pursuer's. That is odd but harmless; document it.

### Bad values at runtime

If the value at `path` is not a location id (missing, `null`, a typo set by an effect),
the pursuer doesn't move. No error: the world can't reject itself.

### Speed counts from turn 0

`every` uses the global turn (`turn % every == 0`), not the turn the chase started. So a
pursuer with `every: 3` that becomes active on turn 5 first moves on turn 6.
`# ponytail: global rhythm; count from activation if authors find the first step feels random.`

### Time mode

If [time mode](time-mode.md) lands first, `every` means minutes there, the same as
`timeline[].every`. Required in time mode, like a rule's `every`, so a pursuer doesn't
move every minute.

## Changes

- **Engine** (`lib/chronicles/engine.ex`): a `move_pursuers/2` step called in `catch_up`
  (before `run_rules`, not on the last step) and in `finish_turn` (before `run_rules`,
  when the clock ticked). A small BFS over `version["locations"][id]["exits"]` filtered with
  `available?/2`. A new `holds?/2` clause for `atPath`. The pursuer's move is a plain
  context write, so no new state fields and no save format change.
- **Validator** (`lib/chronicles/stories/validator.ex`): `pursuers` entries (`path` roots
  at a declared key and doesn't target `/turns`, `activeWhen` is a valid condition, `every`
  is an integer `>= 1`). If `context.initial` (and each `context.randomize` option) gives
  the pursuer's key a string, it must be a location id. `atPath` paths root at a declared
  key.
- **Interruptions**: the "can be interrupted" check in the validator must also count
  `pursuers`, because a gate can read a pursuer's room (`{ "path": "/monster", ... }`).
- **Editor** (`Authoring`, `EditStoryLive`): `pursuers` as a new list part next to
  `timeline` and `rules`.
- **Docs**: a "Pursuers" section in `docs/story-format.md` after "Tick rules", `atPath` in
  the conditions table, and the validation list. The game-story skill follows.

## Check

Engine tests with a small map (hall with rooms a, b, c; a corridor to a far room):

- the pursuer reaches the player's room in exactly the shortest-path number of turns;
- waiting in one room or walking between rooms, it keeps following;
- `every: 2` takes twice as long, `activeWhen` false means it doesn't move;
- a gated (locked) exit is not used; no path means it stays;
- a `timeCost: 3` exit moves it 3 times, and a "caught" ending stops the clock on that turn;
- `atPath` holds only when the rooms match.

Then rewrite the three doors monster with one pursuer and one `atPath` rule through the
game-story skill on port 9278, and play it: wait in a room and the monster arrives.

## Not in v1

- An arrival message on the pursuer itself. A rule with `atPath` and a flag covers it.
- Chasing something other than the player (another context value or an item).
- Random wandering while inactive. Needs randomness during play, which the engine doesn't
  have (only `context.randomize` at game start).
- Pursuers that lose track of the player by distance or line of sight. `activeWhen` covers
  simple cases (a `hidden` flag).
- Showing the pursuer on the game page. Authors use `when`-gated log lines today.
