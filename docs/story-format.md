# Story format

How to write a **good and valid** Chronicles story: the content of one version, as a
plain JSON file. It describes the content object itself, so a human or an LLM can write
it correctly.

## Stories, versions & games

What a player calls "a story" is really two things:

- A **story** is the durable identity: its **slug** (a kebab-case string like
  `the-front-door`, used in its URL), its author, and its visibility: private (only the
  author sees it) or public (every user can see and play it).
- A **version** is an immutable snapshot of the content: everything this document
  describes. A story has one or more versions; exactly one is the head.
- A **game** pins the exact version it was started from.

**This document describes a version's content.** Saving content never changes a
version: it makes a _new_ version and moves the story's head to it, so games in progress
keep playing the version they started with. The slug is not part of the content: it
comes from the upload's slug field or the API URL (`PUT /api/stories/<slug>`).

Saving content (an upload in the app, or an API call) checks everything below first,
**shape** via JSON Schema (`priv/schemas/version.json`) and then the **content rules**,
and rejects bad content with a list of every problem, one readable line each. So treat
the "valid" rules as hard requirements, not advice.

## Data structure

A story is a flat dictionary of locations connected by named exits, plus a
required top-level `context` object (use `{}` if you don't need state). The content has
no id or slug field.

```json
{
  "story_title": "The Front Door",
  "description": "You are locked out of your own house on a cold night. Find a way back inside before you freeze.",
  "tags": ["puzzle", "escape"],
  "starting_location": "outside",
  "locations": {
    "outside": {
      "name": "Outside",
      "description": "You stand on the garden path. The front door is shut.",
      "exits": {
        "front door": { "to": "house", "order": 1, "enabledWhen": { "isCarrying": "house_key" } }
      },
      "items": [
        {
          "id": "house_key",
          "name": "a brass house key",
          "description": "A key glints in the flowerbed.",
          "descriptionByLocation": { "house": "The brass key lies on the table." }
        }
      ]
    },
    "house": {
      "name": "The House",
      "description": "You are back inside the house.",
      "sideEffects": [
        { "type": "log", "text": "Warm light fills the room. The front door leads back outside." },
        {
          "type": "log",
          "text": "The brass key in your pack feels warm here.",
          "when": { "isCarrying": "house_key" }
        }
      ],
      "exits": { "front door": { "to": "outside", "order": 1 } }
    }
  },
  "context": {}
}
```

| Field                                          | Type                 | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `story_title`                                  | string               | Human display title                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `description`                                  | string               | Optional; a two-sentence blurb shown on the game overview page — (1) the setting/background (where & when the story happens) and (2) the player's objective. Display only; nothing in the engine keys off it. Omit if none.                                                                                                                                                                                                                                                                    |
| `tags`                                         | array                | Optional; free-form keyword strings describing the story (e.g. `["puzzle", "escape"]`). Display/discovery only — nothing in the engine keys off them. Omit if none.                                                                                                                                                                                                                                                                                                                            |
| `notesEnabled`                                 | boolean              | Optional (default `false`). When `true`, the player gets a notes button in the game header that opens a free-form notes panel. The text is persisted in the game's `context` under the reserved `notes` key. See [Notes](#notes).                                                                                                                                                                                                                                                              |
| `openingLog`                                   | array                | Optional; scene-setting lines written into the narrative log the instant a new game begins, before the player acts. Array of non-empty strings, each an `outcome` line stamped at turn 0. Use for an intro/framing that doesn't belong to the starting room's own entry text. See [The opening log](#the-opening-log).                                                                                                                                                                         |
| `starting_location`                            | string               | **Must** be a key in `locations`                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `starting_inventory`                           | array                | Optional; items the player **begins carrying**. Array of (reduced) item objects — see [Starting inventory](#starting-inventory). Omit if the player starts empty-handed                                                                                                                                                                                                                                                                                                                        |
| `items`                                        | object               | Optional; the item catalog: items placed nowhere at the start, keyed by id, that a `give` effect brings into play. See [Item catalog](#item-catalog)                                                                                                                                                                                                                                                                                                                                           |
| `supplies`                                     | object               | Optional; carried, countable quantities (currency, ammo, …) the player holds and spends/earns. Map of supply-id → definition; see [Supplies](#supplies-carried-quantities). Omit if none                                                                                                                                                                                                                                                                                                       |
| `timeline`                                     | array                | Optional; scheduled world events that fire at absolute turns (rising water, a patrol, dawn). Array of `{ atTurn, every?, message?, effects }`; see [Scheduled events (the timeline)](#scheduled-events-the-timeline). Omit if none                                                                                                                                                                                                                                                             |
| `rules`                                        | array                | Optional; tick rules checked on every turn the clock reaches (a monster that hurts you while you share its room). Array of `{ when, effects, sideEffects? }`; see [Tick rules](#tick-rules). Omit if none                                                                                                                                                                                                                                                                                      |
| `locations`                                    | object               | Map of location-id → location                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `actions`                                      | object               | Optional; map of action key → action, the buttons a location can show; see [Actions](#actions)                                                                                                                                                                                                                                                                                                                                                                                                 |
| `context`                                      | object               | **Required** (may be `{}`). Story-wide world state; see [Context](#context)                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `input`                                        | object               | Optional; `{ schema }`, a JSON Schema for the input a game of this story starts from: the `output` of a finished game of the story before it in a series. A story with `input` can only start from such a game. See [Series: input and output](#series-input-and-output)                                                                                                                                                                                                                       |
| `locations[id].name`                           | string               | Display name of the location. The engine writes it to the log as a heading line on every arrival (and for the starting room when a game begins). Never built into a sentence                                                                                                                                                                                                                                                                                                                   |
| `locations[id].arrivalText`                    | string or array      | Optional, non-empty; the full arrival line written to the log when the player enters (e.g. `"Je bent in de gang."`, `"You sit down on the couch."`). An array gives one line per visit (first visit, second visit, …); the last line repeats on every later visit. See [Visit counts](#visit-counts). Omitted = the location's `description`, which is usually already the right line ("You are in the kitchen."). Set it only when the arrival should read differently from the `description` |
| `locations[id].description`                    | string               | The default arrival line, written to the log under the name heading on every arrival. Keep it **short and factual — where the player is, nothing about how it looks.** All flavor, atmosphere, and state prose goes to the narrative **log** via `sideEffects`, so the arrival stays a terse "you are here" line. See [Where text goes](#where-text-goes-the-log-vs-the-panels)                                                                                                                |
| `locations[id].sideEffects`                    | array                | Optional; effects fired when the player **enters** this location (by any exit). This is where a room's descriptive prose goes: a `log` effect (optionally `when`-gated) writes a line to the narrative log on every entry. Each `{ type, when?, text? }`; see [Side effects](#side-effects)                                                                                                                                                                                                    |
| `locations[id].exits`                          | object               | Map of exit label → exit (see below)                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `locations[id].exits[label].to`                | string               | Target location-id                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `locations[id].exits[label].order`             | number               | Optional; display sort order, ascending (default `0`)                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `locations[id].exits[label].timeCost`          | integer (`0`–`1000`) | Optional (default `1`); the turn cost of taking this exit. `0` = free, `n` = advance the clock by `n`. See [Time & turns](#time--turns)                                                                                                                                                                                                                                                                                                                                                        |
| `locations[id].exits[label].visibleWhen`       | condition            | Optional; exit is hidden unless it passes. See [Conditions](#conditions)                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `locations[id].exits[label].enabledWhen`       | condition            | Optional; exit renders disabled (dimmed, non-clickable) unless it passes                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `locations[id].exits[label].interruptedText`   | string               | Required when the exit [can be interrupted](#scheduled-events-the-timeline), else optional; non-empty. The log line when the world closes this exit while the player is taking it (e.g. `"The bridge swings up under your feet; you scramble back."`). Supports [placeholders](#text-placeholders)                                                                                                                                                                                             |
| `locations[id].exits[label].sideEffects`       | array                | Optional; cosmetic effects fired when **this exit** is taken. Each `{ type, when? }`; see [Side effects](#side-effects)                                                                                                                                                                                                                                                                                                                                                                        |
| `locations[id].actions`                        | array                | Optional; list of action keys (strings) from `actions` shown in this room                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `locations[id].items`                          | array                | Optional; objects the player can take                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `locations[id].items[].id`                     | string               | Stable item id (identity for take / drop, and `isCarrying` checks)                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `locations[id].items[].name`                   | string               | Display string shown to the player (e.g. `"a brass key"`)                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `locations[id].items[].description`            | string               | Optional; flavor text written to the narrative **log** on entry while the item is in that room (once per entry, for each present item)                                                                                                                                                                                                                                                                                                                                                         |
| `locations[id].items[].descriptionByLocation`  | object               | Optional; map of location-id → string, overriding `description` in the on-entry log line when the item is in that location                                                                                                                                                                                                                                                                                                                                                                     |
| `locations[id].items[].descriptionWhenCarried` | string               | Optional; shown in the Carrying panel while the item is in the player's inventory. Omit → no description shown while carried. Lets an item read differently in-hand vs on the floor                                                                                                                                                                                                                                                                                                            |
| `locations[id].items[].takeLabel`              | string               | Optional; overrides the take button's label for this item (e.g. `"Pocket the key"`). Must be non-empty if present. A literal string — **not** localized, so it shows verbatim regardless of UI language. Omit → the UI's default ("Take")                                                                                                                                                                                                                                                      |
| `locations[id].items[].availableWhen`          | condition            | Optional; the item is **hidden from the take list** until this condition passes (over `context` + carrying). Use for an item sealed inside a container the player must open first (a screwed-shut panel, a locked drawer). Omit → always available. The gate travels with the item, so a dropped item re-gates. See [Conditions](#conditions)                                                                                                                                                  |

Items declared on a location are its _starting_ contents. At runtime the player can
take them into their **carrying** inventory and drop them again; that carried/room
state plus `context` live in the **game**, not the story. Conditions _can_ read the
carrying inventory via the `isCarrying` primitive (see below).

⚠️ **Games in progress keep playing the version they pinned.** A version's items and
`context.initial` are copied into a game when that game is first created, and the game
reads the rest of the version live — but versions are immutable, so this is safe.
Editing a story mints a _new_ version and moves the story's head to it; existing games
stay on their old version. Start a new game to play the new version (or patch a game
directly to migrate it).

`additionalProperties` is `false` everywhere — extra fields are rejected. A full
story (POST/PUT) requires all fields (including `context`); a partial update (PATCH)
accepts any subset.

## Starting inventory

The optional top-level `starting_inventory` seeds the player's **carrying**
inventory at game creation — items the player already holds before taking a single
step (a detective's notebook, a key they own from the outset). It's an array of
item objects with a **reduced** shape compared to location items:

| Field                    | Type   | Notes                                                                                                                                                                          |
| ------------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `id`                     | string | Stable item id. **Must be globally unique** — no duplicates within `starting_inventory`, and it must not collide with any location item id (so `isCarrying` stays unambiguous) |
| `name`                   | string | Display string shown in the Carrying panel                                                                                                                                     |
| `description`            | string | Optional; flavor text used if the item is later dropped into a room                                                                                                            |
| `descriptionByLocation`  | object | Optional; per-location `description` overrides, used after the item is dropped                                                                                                 |
| `descriptionWhenCarried` | string | Optional; shown in the Carrying panel from turn one                                                                                                                            |

`takeLabel` and `availableWhen` are **rejected** here — both only govern an item's
appearance in a room's take list, which a starting item never has. (If dropped and
re-taken later, the item shows the default "Take" label with no gate.)

Starting-inventory ids join the universe `isCarrying`, `give` and `consume` can
reference, so an exit or action can gate on an item the player starts with. Like all items, these begin in
the **game**, not the version, the moment the game is created — editing
`starting_inventory` mints a new version and leaves games already in progress untouched.

## Item catalog

The optional top-level `items` map holds items that are **placed nowhere** when the game
starts: no room, no starting inventory. A `give` effect brings one into play (see
[Giving and consuming items](#giving-and-consuming-items)). The key is the item id; the
value has the same reduced shape as a starting-inventory item, without `id`:

```json
"items": {
  "sword": { "name": "a sword", "descriptionWhenCarried": "Freshly forged, still warm." }
}
```

A catalog id must not also be a room item or a starting-inventory item, so every item
has exactly one definition. Catalog ids join the universe `isCarrying`, `give` and
`consume` can reference.

## Conditions

A **condition** gates an exit or action via `visibleWhen` (hide when false) or
`enabledWhen` (disable when false). Omitted → always true. Conditions are evaluated
against the live game `context`, the player's carrying inventory, and supplies. The forms are:

| Form                                          | Meaning                                                                                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{ "path": "/a/b", "equals": <value> }`       | JSON-Pointer `path` into `context` strictly equals `value`                                                                                                 |
| `{ "path": "/a/b", "atLeast": <n> }`          | Numeric value at `path` is `>= n`. **False if the value isn't a number**                                                                                   |
| `{ "path": "/a/b", "atMost": <n> }`           | Numeric value at `path` is `<= n`. False if not a number                                                                                                   |
| `{ "path": "/a/b", "greaterThan": <n> }`      | Numeric value at `path` is `> n`. False if not a number                                                                                                    |
| `{ "path": "/a/b", "lessThan": <n> }`         | Numeric value at `path` is `< n`. False if not a number                                                                                                    |
| `{ "isCarrying": "<item_id>" }`               | The player is currently carrying an item with this `id`                                                                                                    |
| `{ "supply": "<supply_id>", "atLeast": <n> }` | The carried amount of `supply` (absent = 0) is `>= n`. Also takes `atMost`/`greaterThan`/`lessThan`/`equals`. See [Supplies](#supplies-carried-quantities) |
| `{ "turnAtLeast": <n> }`                      | The game's turn counter is `>= n`. See [Time & turns](#time--turns)                                                                                        |
| `{ "turnAtMost": <n> }`                       | The turn counter is `<= n`                                                                                                                                 |
| `{ "turnEquals": <n> }`                       | The turn counter is exactly `n`                                                                                                                            |
| `{ "at": "<location_id>" }`                   | The player is currently in this location. Must name a real location                                                                                        |
| `{ "anyOf": [<cond>, …] }`                    | OR — at least one sub-condition holds                                                                                                                      |
| `{ "allOf": [<cond>, …] }`                    | AND — every sub-condition holds                                                                                                                            |
| `{ "not": <cond> }`                           | Negation                                                                                                                                                   |

These nest arbitrarily — so a gate requiring **a combination of items** is just an
`allOf` of `isCarrying`s, e.g. `{ "allOf": [ { "isCarrying": "key" }, { "not": { "path": "/door/jammed", "equals": true } } ] }`.
Each condition object must use exactly one form (`oneOf` — no mixing keys).
To gate on how often the player has entered a room, use a `path` condition on
`/visits/<location_id>` (see [Visit counts](#visit-counts)).

## Side effects

`sideEffects` is a list of fire-and-forget effects. Put it on a **location** (fires
when the player enters it, however they arrive — **including the starting location at
game start**, since a new game "enters" it: its `log` lines seed the opening scrollback
and its `confetti`/`defeat`/`explosion`/`shake` cues play once on load), an **exit** (fires only when that
exit is taken), or an **action** (fires when the action is clicked).

On a transition the engine fires the **union** of the exit's and the destination
location's effects (one pass per move). Their `log` lines print in a fixed chronological
order: the **exit's** `log` effects first (journey flavor), then the automatic
room-transition **arrival lines** (the location's `name` as a heading, then the anchor line: its `arrivalText`, else its `description`), then the **destination's** `log`
effects (the room describing itself on arrival), and finally the prose of any items
present in that room. So the log reads the room's name, then _"You are in X."_, and then
how X looks — the arrival lines head the room's own description, which is why a location's descriptive prose belongs in a
(usually unconditional) destination `log` effect. On an **action** the effects fire on
every click — because a click is an event, a `log` line is appended fresh each press.

Each entry is `{ type, when?, text? }`:

| Field  | Type      | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `type` | string    | **Required**; the effect to run. A closed set: `"confetti"` (a celebratory win burst), `"defeat"` (a loss cue — the screen shakes and a red vignette flashes), `"explosion"` (a blast, visual only — a hard screen shake and a white-to-red fireball flash that flickers out), `"shake"` (the screen shakes for about a second, nothing else — a hit, a tremor), or `"log"` (append a line to the permanent narrative log). Unknown values are rejected. |
| `text` | string    | **Required for `log`** (the message appended to the log as an `outcome` line), ignored otherwise.                                                                                                                                                                                                                                                                                                                                                        |
| `when` | condition | Optional; gate (same forms as [Conditions](#conditions)) over the live `context` + carrying. Omitted = always fires.                                                                                                                                                                                                                                                                                                                                     |

`confetti`, `defeat`, `explosion` and `shake` never change game state and are never persisted. A `log` effect
appends a permanent line to the game's narrative log (which _is_ persisted), but nothing
in the flow can depend on any side-effect — removing every `sideEffects` leaves the game
logically identical. Validation: any `isCarrying` inside a `when` must resolve to a real
item, and every `log` effect must have non-empty `text`.

The narrative log is the game's running scrollback, shown to the left of the room. The
engine writes to it automatically — a `command` line each time the player takes an exit
(`> <label>` — the exit label as-is, so write labels as commands), fires an action (`> <label>`), or takes/drops an item
(`> take <item>` / `> drop <item>`), and an `outcome` line for the room transition (the
anchor line above). Taking and dropping are free (they don't tick the turn counter), but
they're still recorded. A `log` side-effect adds your own `outcome` line on
top of that, for flavor an author wants recorded ("The keypad buzzes red — nothing
happens.").

### Where text goes: the log vs. the panels

**All prose belongs in the log.** The panels next to the log only hold the interactive
lists (items, actions, exits) and the player's state (time, supplies, carrying). On every
arrival the engine writes the location `name` as a heading and then the short factual
`description` ("You are sitting next to Vale."), or the `arrivalText`. Everything about
how the room _looks_ or what has _happened_ also goes to the log, so the log is the single
running account of the world.

Match each kind of text to where it fires:

- **How the room looks on arrival** — atmosphere, description, what's on the walls — is a
  (usually unconditional) `log` side-effect on the **location**. It fires on every entry,
  right after the room's name heading and anchor line, so the log reads like walking in and looking around.
- **Enduring state that reads differently as the world changes** — a drawer that now
  stands open, an NPC's mood, a hint that appears once you hold a key — is a **`when`-gated
  `log` side-effect on the location**, so on each entry the log restates only the lines
  whose condition currently holds. For state the player changes _while standing in the
  room_ (and would want to see immediately, not just on the next entry), put the line on
  the **action** that flips the flag instead.
- **An action's response** — the dialogue it draws, a one-time reveal, transaction
  narration — is a `log` side-effect on that **action**, timestamped in sequence with the
  command that caused it.
- **World events that happen on their own** at a given turn — dawn breaking, a tide
  rising — are a [`timeline`](#scheduled-events-the-timeline) event `message`.
- **Item prose** (`description` / `descriptionByLocation`) is logged automatically on
  entry for each item present — you don't write a side-effect for it.

Rule of thumb: keep the `description` to the bare "where you are" and move the rest into a
`log` side-effect.

```json
"freedom": {
  "name": "Outside the Study",
  "description": "You are free!",
  "sideEffects": [{ "type": "confetti" }],
  "exits": {}
}
```

```json
"fiddle_keypad": {
  "description": "Start punching in random numbers",
  "sideEffects": [{ "type": "log", "text": "The keypad buzzes red. Nothing happens." }]
}
```

### Text placeholders

A text can show a current value with a placeholder in curly braces:

| Placeholder     | Filled with                                                                |
| --------------- | -------------------------------------------------------------------------- |
| `{/a/b}`        | The context value at JSON-Pointer `/a/b`. A missing value fills as nothing |
| `{supply:<id>}` | The amount of that supply the player carries                               |

```json
{ "type": "log", "text": "The dial points to {/dial}. You have {supply:credits} credits left." }
```

The engine fills placeholders in every text it writes to the log: `log` side-effects,
`arrivalText` and `description` on arrival, item descriptions, `openingLog` lines,
timeline `message`s and ending `message`s. It fills them **once, when the line is
written**, with the state at that moment, so an old log line keeps the value it showed.
On an action, that state already includes the action's own effects.

Other text in braces (`{like this}`) is not a placeholder and stays as written.
Validation: a `{/path}` must root at a key declared in `context.initial` or
`context.schema` (or be `/visits/<location_id>`), and a `{supply:<id>}` must name a
declared supply.

## Context

The top-level `context` object holds story-wide world state:

| Field               | Type   | Notes                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `context.initial`   | object | Starting state copied into a new game's `context`                                                                                                                                                                                                                                                                                                                                                                                   |
| `context.schema`    | object | Optional JSON Schema for the context, **enforced two ways**: (a) _author time_ — the story is rejected if `context.initial` doesn't satisfy it (or the schema itself is invalid, or uses a keyword draft-07 doesn't know, such as a typo like `requried`); (b) _runtime_ — after an action's `effects`, the engine re-validates the context and _rejects_ the action (no state change, warning logged) if it fails. Use it to keep effect-driven state well-formed so conditions read it reliably |
| `context.randomize` | object | Optional; map of a top-level `context.initial` key → an array of at least 2 values. When a game is created, each key gets one value picked at random, so every playthrough can differ (which room hides the weapon). Each key must exist in `context.initial`, and each value must keep `context.initial` valid against `context.schema`. See [Random starting values](#random-starting-values)                                     |

```json
"context": {
  "initial": { "door": { "locked": true } },
  "schema": {
    "type": "object",
    "properties": {
      "door": {
        "type": "object",
        "properties": { "locked": { "type": "boolean" } },
        "required": ["locked"],
        "additionalProperties": false
      }
    },
    "additionalProperties": false
  }
}
```

### Random starting values

`context.randomize` makes a new game start from a random value. The pick happens once,
when the game is created, and is stored in the game's `context`. A reload keeps it.
`context.initial` holds a valid placeholder value for the key, so patches and conditions
see it declared. Combine it with `availableWhen` to place an item at random:

```json
"context": {
  "initial": { "weapon_room": "cellar" },
  "randomize": { "weapon_room": ["cellar", "attic", "shed"] }
}
```

Then the item in each of the three rooms carries
`"availableWhen": { "path": "/weapon_room", "equals": "<that room>" }`, so only one of
them can be taken.

### Counting in context (abstract numbers)

For **world/abstract** numbers that aren't something the player carries — a global
alarm level, an NPC's mood score, a counter of how many levers you've pulled — keep
a number in `context`, mutate it with the `inc` patch op, and gate with the numeric
comparators. Keep it well-formed with a `context.schema` — a `minimum: 0` makes
going negative **impossible**: the engine re-validates after every patch and rejects
an action whose result would break the schema.

> **Carried currency belongs in [Supplies](#supplies-carried-quantities), not here.**
> If the number is money/ammo/rations the _player holds_, declare it as a supply so
> it shows in the Carrying panel and uses `{ supply, by }` effects + `{ supply, … }` gates.
> Use context `inc` only for numbers that aren't in the player's pack. The example
> below uses `context` to illustrate the op in isolation.

```json
"context": {
  "initial": { "coins": 10 },
  "schema": {
    "type": "object",
    "properties": { "coins": { "type": "integer", "minimum": 0 } },
    "required": ["coins"],
    "additionalProperties": false
  }
},
"actions": {
  "buy_lantern": {
    "description": "Buy the brass lantern (3 coins)",
    "enabledWhen": { "path": "/coins", "atLeast": 3 },
    "effects": [{ "op": "inc", "path": "/coins", "value": -3 }]
  },
  "do_odd_job": {
    "description": "Haul crates for the dockmaster (+5 coins)",
    "effects": [{ "op": "inc", "path": "/coins", "value": 5 }]
  }
}
```

Always gate a spend action with `enabledWhen` (here `atLeast: 3`) so the button
**disables** when the player can't afford it. The schema `minimum` is a safety
net — without the `enabledWhen`, an unaffordable click is just silently rejected,
which reads as a broken button. To hand over a bought item, add a `give` effect
next to the `inc`.

## Actions

The top-level `actions` object maps an action key to an action. An **action** is a
button, shown in every room that lists its key in `locations[id].actions`. When clicked,
it applies its `effects` (changes to `context`, supplies and items), and it can also move
the clock:

| Field             | Type                 | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `description`     | string               | Button label                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `order`           | number               | Optional display sort order (default `0`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `timeCost`        | integer (`0`–`1000`) | Optional (default `1`); the turn cost of firing this action. `0` = free, `n` = advance the clock by `n` (e.g. a `sleep` action with `"timeCost": 8`). See [Time & turns](#time--turns)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `visibleWhen`     | condition            | Optional; hide the button unless it passes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `enabledWhen`     | condition            | Optional; disable the button unless it passes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `interruptedText` | string               | Required when the action [can be interrupted](#scheduled-events-the-timeline), else optional; non-empty. The log line when the world cancels this action before it completes. Supports [placeholders](#text-placeholders)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `effects`         | array                | Optional; the changes the action makes, in one list. Each entry is **either** a context JSON-Patch op `{ op: "add"\|"remove"\|"replace"\|"inc", path, value? }` **or** a supply delta `{ supply, by }` **or** an item effect `{ give: <item_id> }` / `{ consume: <item_id> }` (see [Giving and consuming items](#giving-and-consuming-items)), the same forms as a timeline event's `effects`. `inc` adds a (possibly negative) numeric `value` to the number at `path` (base `0` if absent); its `value` is **required and must be a number**. Each op's path must root at a key declared in `context.initial` or `context.schema` (a nested key under a declared root is fine), and none may target the engine clock (`/turns`); both are rejected. At runtime, an op whose parent is missing or not an object (e.g. `/lever/down` while `lever` is `false`) is skipped. A supply delta earns with a positive `by` and spends with a negative one; each `supply` must be declared, see [Supplies](#supplies-carried-quantities). The **whole action is rejected** (no state change, no time, nothing consumed) if the result violates `context.schema` or pushes a supply outside its `[min, max]`, so gate spends with `enabledWhen: { supply: <id>, atLeast: <n> }` |

```json
"actions": {
  "unlock": {
    "description": "Unlock the door",
    "enabledWhen": { "isCarrying": "house_key" },
    "effects": [{ "op": "replace", "path": "/door/locked", "value": false }]
  }
}
```

A location then opts into the button with `"actions": ["unlock"]`. Exits can react to
the resulting state with `"enabledWhen": { "path": "/door/locked", "equals": false }`.

### Giving and consuming items

Two effects move items in and out of the player's **carrying** inventory:

- `{ "give": "<item_id>" }` puts the item in the player's inventory. If it lies in a
  room, it moves from there, so an item is never in two places. If it is nowhere (a
  catalog item, or one consumed earlier), it is made from its definition. Giving an item
  the player already carries does nothing.
- `{ "consume": "<item_id>" }` removes the item from the player's inventory. The item is
  destroyed, not dropped into the room. Consuming an item the player doesn't carry does
  nothing, so gate the action with `enabledWhen: { "isCarrying": "<id>" }` so it
  disables once spent.

Each id must resolve to a real item: a room item, a starting-inventory item, or an
[item catalog](#item-catalog) entry. Both effects also work in timeline events and rules,
so the world can hand over or take away an item too.

```json
"turnstile": {
  "description": "Feed the ticket into the turnstile",
  "enabledWhen": { "isCarrying": "ticket" },
  "effects": [
    { "consume": "ticket" },
    { "op": "replace", "path": "/gate/open", "value": true }
  ],
  "sideEffects": [{ "type": "log", "text": "The turnstile swallows your ticket and clicks open." }]
},
"ask_smith": {
  "description": "Ask the smith for a blade",
  "enabledWhen": { "supply": "credits", "atLeast": 10 },
  "effects": [{ "supply": "credits", "by": -10 }, { "give": "sword" }],
  "sideEffects": [{ "type": "log", "text": "The smith hands you a sword, still warm." }]
}
```

## Supplies (carried quantities)

**Supplies** are countable things the player carries — currency, ammo, rations,
fuel — that go **up and down**. They're the third kind of state, distinct from
items and context:

| Kind                                     | What it's for                         | Identity                                       | Reference / mutate                                  |
| ---------------------------------------- | ------------------------------------- | ---------------------------------------------- | --------------------------------------------------- |
| **items** (`items`/`starting_inventory`) | unique objects you hold               | each is a singular thing (a key, a painting)   | `isCarrying` / take, drop, `give`/`consume` effects |
| **supplies** (`supplies`)                | carried _amounts_                     | fungible — "5 credits", no per-unit identity   | `{ supply, atLeast }` / `{ supply, by }` effect     |
| **context** (`context`)                  | world/abstract state not in your pack | a named value (mood, door locked, alarm level) | `{ path, … }` / `{ op, path }` effect (`inc`)       |

Rule of thumb: a discrete object → **item**; a countable thing you carry →
**supply**; a flag/scalar that isn't on your person → **context**. In the UI,
supplies appear in the **Carrying** panel alongside items (they're "stuff you
carry"), shown as `count name`.

Declare supplies in a top-level `supplies` map (supply-id → definition):

| Field        | Type    | Notes                                                               |
| ------------ | ------- | ------------------------------------------------------------------- |
| `name`       | string  | **Required**; singular display name (e.g. `"credit"`)               |
| `namePlural` | string  | Optional; plural display (default `name` + "s")                     |
| `initial`    | integer | Optional starting amount the player carries (default `0`)           |
| `min`        | integer | Optional floor (default `0`) — a change below it rejects the action |
| `max`        | integer | Optional ceiling — a change above it rejects the action             |

Actions earn/spend with a `{ supply, by }` effect, and gate affordability with a `supply`
condition. A spend that would breach `[min, max]` rejects the whole action, so the
`atLeast` gate (which disables the button) is what the player actually sees:

```json
"supplies": {
  "credits": { "name": "credit", "namePlural": "credits", "initial": 2, "min": 0 }
},
"actions": {
  "haul_keg": {
    "description": "Haul a keg for the barkeep (+8 credits)",
    "effects": [{ "supply": "credits", "by": 8 }]
  },
  "buy_drink": {
    "description": "Buy a drink (5 credits)",
    "enabledWhen": { "supply": "credits", "atLeast": 5 },
    "effects": [{ "supply": "credits", "by": -5 }]
  }
}
```

An action may combine all of it: a supply effect to spend a carried resource, a patch
effect to change `context` (e.g. give an NPC money via `inc`), and a `consume`
effect to destroy an item — all atomic (if any part is rejected, none of it applies).

## Time & turns

Every game carries a **turn counter** — a monotonically increasing integer that
starts at `0` and lives in the game state (not in `context`, so it can't be reached
by a JSON-Patch). It's the game's clock.

**What advances it.** Taking an **exit** or firing an **action** advances the counter
by its `timeCost` (default `1`) — _after_ the interaction's condition gates
(`visibleWhen`/`enabledWhen`) have passed, and atomically with the interaction's own
mutations. An action that is rejected (a schema-violating effect, an unaffordable supply
spend) makes no state change and so does **not** tick. Taking / dropping items and
typing notes are free — they never tick.

**Turn cost.** `timeCost` on an exit or action is an **integer from 0 to 1000** controlling
how much the clock advances: omitted = **1**, `0` = free (runs its mutations and
side-effects but leaves the clock where it was), and any `n` = advance by `n` at once.
Use `0` for flavor buttons and examine-style exits; use a larger integer for time-skips
(`"timeCost": 8` for a `sleep` action that fast-forwards the night). Every turn the cost
crosses is a real turn — [scheduled events](#scheduled-events-the-timeline) along the way
all fire.

**Reading it.** Gate exits, actions, items, and side-effects on the
clock with the [conditions](#conditions) `turnAtLeast` / `turnAtMost` / `turnEquals`.
The engine is **pull-based**: a condition re-reads the current turn every render, so a
gate like `{ "turnAtLeast": 5 }` simply starts passing once the counter reaches 5 — no
scheduling, no events. Combine with `anyOf`/`allOf`/`not` like any other condition.
(For a line that should appear in the log _the moment_ a turn is reached rather than on
the next entry, use a [`timeline`](#scheduled-events-the-timeline) event `message`.)

```json
"exits": {
  "vault": { "to": "vault", "enabledWhen": { "turnAtLeast": 10 } }
},
"sideEffects": [
  { "type": "log", "text": "Dawn breaks — light spills through the window.", "when": { "turnAtLeast": 8 } }
]
```

> **Abstract counters still belong in `context`.** The turn counter measures _player
> actions taken_, globally. A count of "how many levers pulled" or "alarm level" is
> per-thing world state — keep those in `context` with `inc` (see
> [Counting in context](#counting-in-context-abstract-numbers)). Reach for `turn*`
> conditions only when you mean the passage of time itself.

## Scheduled events (the timeline)

Where `turn*` conditions are **pull** (the world reacts when you look at it), the
top-level `timeline` is **push**: authored events that fire _by themselves_ when the
clock crosses their turn, changing game state whether or not the player is looking.
Use it for a world that moves on its own — a tide that floods a chamber at turn 5, a
guard who returns at turn 8, an alarm that escalates every few turns.

The `timeline` is an array of event blocks:

| Field     | Type             | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `atTurn`  | integer (`>= 1`) | The absolute turn at which this event first fires. Events must be listed **strictly ascending** by `atTurn` — no two with the same `atTurn`, none out of order (rejected)                                                                                                                                                                                                                                                                |
| `every`   | integer (`>= 1`) | Optional; repeat the event every `every` turns after `atTurn`, with no end (`atTurn: 3, every: 12` fires at 3, 15, 27, …). A repeat may land on the same turn as another event; events on one turn fire in array order                                                                                                                                                                                                                                |
| `message` | string           | Optional; a narrative line describing what happened in the world. Pushed into the game's narrative log as an `outcome` line (stamped with `atTurn`) when the event fires, so the player sees the world move. Omit for a silent state change                                                                                                                                                                                                           |
| `effects` | array            | Mutations applied to game state when the event fires. Each entry is **either** a context JSON-Patch op `{ op, path, value? }` (`add`/`remove`/`replace`/`inc`) **or** a supply delta `{ supply, by }` **or** an item effect `{ give }` / `{ consume }`, the same forms as an action's `effects`. A patch path must root at a declared `context` key and a supply must be declared; nothing may target the engine clock (`/turns` or a `turns` supply) |

```json
"timeline": [
  { "atTurn": 5, "message": "Cold water surges up over the tunnel floor.", "effects": [ { "op": "replace", "path": "/mine/flooded", "value": true } ] },
  { "atTurn": 8, "effects": [ { "op": "inc", "path": "/alarm", "value": 1 }, { "supply": "torch_fuel", "by": -2 } ] }
]
```

**How it runs (the catch-up phase).** When a turn-costing interaction fires, before its
own payload is applied the engine walks the clock forward one turn at a time — from the
current turn+1 up to current turn+cost — and fires every timeline event scheduled for each
crossed turn (including the repeats of an `every` event), in array order (applying its `effects` and appending its `message` to the log). So
a single `"timeCost": 8` sleep triggers _every_ event in that 8-turn span, not just the
last. Supply deltas that would breach `[min, max]` **saturate**
at the bound (a scheduled event is the world acting, not a player choice, so it can't be
rejected).

**Interruption.** After the catch-up phase advances the clock, the engine re-checks the
player's interaction against the _new_ state. If a timeline event just flipped a flag
that now disables (or hides) the exit you were walking through — or the action you fired —
the interaction is **cancelled**: the world's changes and the clock stick, but your
move/patch does not. The log then shows the crossed events' own `message` lines (what
changed in the world), then the exit's or action's `interruptedText` (what that means
for the player). This is how a flooding chamber can strand you mid-step. (An action whose
_own_ effects are invalid is a different case — it rejects atomically and costs no time at
all.)

An exit or action **can be interrupted** when all three hold:

- it costs at least one turn (`timeCost` `>= 1`, the default),
- it has a `visibleWhen` or `enabledWhen`, and
- the story has a `timeline` event or a `rules` entry with `effects`, or that gate reads the turn (`turnAtLeast`,
  `turnAtMost`, `turnEquals`).

Such an exit or action **must** have an `interruptedText`; the save rejects it otherwise.
The check is deliberately coarse: it also asks for a line where the gate reads nothing the
world ever changes. Write the line from the player's point of view, about this exit or
action, not about the event: the event's `message` already describes the world.

## Tick rules

The timeline fires at fixed turns, whatever the player does. A **tick rule** fires on
_every_ turn its condition holds. Use it for a danger that depends on the player's
situation, such as a monster that hurts you while you share its room. The top-level
`rules` array holds the rules:

| Field         | Type      | Notes                                                                                                                                                                                                  |
| ------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `when`        | condition | **Required**; any [condition](#conditions). An `at` condition makes the rule depend on the player's room                                                                                               |
| `effects`     | array     | **Required**; the same effects as a timeline event (context patch ops, supply deltas, which saturate, and give/consume)                                                                                |
| `sideEffects` | array     | Optional; [side effects](#side-effects) fired each time the rule fires, after its `effects` (so a `when` gate reads the new state). A `log` line is stamped with the turn; a cue such as `shake` plays |

```json
"rules": [
  {
    "when": { "allOf": [{ "at": "lair" }, { "path": "/monster", "equals": "lair" }] },
    "effects": [{ "supply": "health", "by": -1 }],
    "sideEffects": [{ "type": "shake" }, { "type": "log", "text": "The monster lashes out at you!" }]
  }
]
```

**When rules run.** A rule is checked once for every turn the clock reaches, after
that turn's timeline events, in array order. For the last turn of an interaction, the
rules run _after_ the interaction itself: after the move, so `at` reads the room the
player just entered, or after the action's payload. A rule also runs when an interaction
is interrupted, because the world's changes stick; `at` then reads the room the player
stayed in. Endings are checked after the rules. Interactions that cost no time
(`timeCost: 0`, take, drop) reach no new turn, so no rules run.

A rule fires on every turn its `when` holds. To fire once per visit, add a flag to the
`when` (`struck: false`), set it in the rule's effects, and reset it from the timeline.

## Endings (win/loss)

An optional top-level `endings` array turns the game from open-ended exploration into
something winnable and losable. Each entry is a **terminal rule**: when its `when`
condition holds over the committed game state, the game ends, the board locks (no more
exits, actions, or take/drop), and a win or loss modal appears with the ending's
`message`. A story with no `endings` never terminates on its own — exactly today's
behaviour.

| Field     | Type      | Notes                                                                                                                                                                                                                                                            |
| --------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `when`    | condition | **Required**; any [condition](#conditions) (`path`/`supply`/`isCarrying`/`at`/`turn*`/`anyOf`/`allOf`/`not`); `{ "at": "<location_id>" }` makes reaching a room a win or loss. For an always-true fallback ending, use `{ "turnAtLeast": 0 }`.                   |
| `outcome` | string    | **Required**; `"win"` or `"loss"`. Selects the cue (a confetti burst for a win, the screen-shake + red flash for a loss) and the modal styling.                                                                                                                  |
| `message` | string    | **Required, non-empty**; the ending's narrative line — shown in the modal and appended to the log as an `outcome` line stamped with the turn it fired.                                                                                                           |
| `output`  | object    | Optional; what this ending hands on to the next story of a series, as a fixed object. The next story accepts it when it passes that story's `input.schema`. An ending without `output` unlocks nothing. See [Series: input and output](#series-input-and-output) |

```json
"endings": [
  { "when": { "supply": "health", "atMost": 0 }, "outcome": "loss",
    "message": "Your wounds overcome you. You collapse in the dark." },
  { "when": { "allOf": [{ "isCarrying": "crown" }, { "path": "/throne/claimed", "equals": true }] },
    "outcome": "win", "message": "The crown is yours. The kingdom is at peace." }
]
```

**Priority is array order.** Endings are checked top to bottom; the **first** whose
`when` holds wins and shorts the rest. List specific, flavourful endings _above_ general
fallbacks — e.g. a specific item-based victory before a generic `turnAtLeast` deadline
loss.

**When endings are evaluated.** After every committed state change: an action's payload,
an item taken or dropped, and — crucially — **each step of a timeline catch-up**. During
a multi-turn time skip the engine applies each crossed turn's effects, saturates
supplies, then checks endings; the **first** turn that satisfies one **halts the skip on
that exact turn**. No further turns or scheduled events run, the clock stops at the fatal
(or triumphant) turn rather than the full jump, and the interaction that started the skip
does not complete. This is how a rising flood can drown you mid-journey, or a supply
running dry at turn 6 of an 8-turn trek ends the story at turn 6.

**Persistence.** The terminal state is recorded on the game (`game.ending`), so a
finished game reloads already locked and shows the modal again, without re-deriving the outcome.

## Series: input and output

A **series** links stories in order: a finished game of one story unlocks the next
story, and the way it ended is the next game's **input**. Each story stays a normal
story. It knows nothing about the stories before or after it; the series is the only link.
The link is two small parts that the author designs together:

- **Output**: an ending's `output`, a fixed object. It has its own shape. It does not
  mirror the story's context, items or rooms, so the story can change those freely. For
  different outputs, write more endings, one per output.
- **Input**: the next story's `input.schema`, a JSON Schema. A finished game's output
  is correct input when it passes this schema. The keys match exactly: the output holds
  the keys and values the schema expects.

```json
"endings": [
  { "when": { "allOf": [{ "path": "/value", "equals": 7 }, { "path": "/moves", "atMost": 3 }] },
    "outcome": "win", "message": "Seven, in 3 moves.", "output": { "spare": 3 } },
  { "when": { "path": "/moves", "atLeast": 6 }, "outcome": "loss",
    "message": "Six moves used. The rooms go dark." }
]
```

```json
"input": {
  "schema": {
    "type": "object",
    "properties": { "spare": { "type": "integer", "minimum": 0, "maximum": 3 } },
    "required": ["spare"]
  }
}
```

**In the game.** A game of a story with `input` starts from a finished game of the
story before it in the series, and holds that game's output in its `context` under the
reserved `input` key. Conditions and placeholders read it like any context value
(`{ "path": "/input/spare", "equals": 3 }`, `{/input/spare}`). Nothing may declare or
patch `input`: it is read-only, and the engine leaves it out of the `context.schema`
check. Starting over keeps the input.

**Items.** Stories do not share items. To hand on an item, the output says what
happened (`"took_lamp": true`) and the next story decides what that means in its own
world: an item with `availableWhen: { "path": "/input/took_lamp", "equals": true }`
exists only for a player who earned it.

**The series checks.** A series is saved through the API (see the `game-story` skill).
The save checks the head content of each story, in order:

- the first story has no `input`, so it can start;
- every next story has `input`, and at least one **win** ending of the story before it
  has an `output` that this `input.schema` accepts;
- no **loss** ending of the story before it has an accepted `output`.

A story is in at most one series, and a story a series names can't be deleted until the
series changes.

## The opening log

A new game can start with text already in the narrative log, before the player takes a
single turn. Three sources feed it, in this order, all stamped at **turn 0**:

1. **`openingLog`** (top-level array of strings) — author's scene-setting/framing that
   isn't tied to the first room ("Three days since the storm. The radio has been silent
   ever since."). Each string becomes one `outcome` line.
2. **The starting location's arrival lines** — its `name` heading and its anchor line
   (`arrivalText`, else `description`), exactly as on any arrival. Always written; there
   is nothing to author.
3. **The starting location's on-entry `sideEffects`** — because a fresh game "enters"
   the starting location, its `log` side-effects seed the log (after the arrival
   lines) and its `confetti`/`defeat`/`explosion`/`shake` cues play once on load. This is the same
   entry-effect behaviour any room has; the starting room is no exception.

Use `openingLog` for prose that stands apart from the room, and the starting location's
`sideEffects` for text that reads as _entering that specific room_. Both only apply to a
**fresh** game — a resumed game restores its saved log verbatim and re-seeds nothing.

### Visit counts

The engine counts how many times the player has arrived in each room. The count lives in
the game's `context` under the reserved `visits` key, as a map of location id to
number: `{ "visits": { "hall": 2, "cellar": 1 } }`. The starting room counts as visited
once when the game begins. A room the player has never entered has no entry, which reads
as 0 for the numeric conditions below.

Read it like any other context value:

- **Gate** with a `path` condition, for example a line only on the first visit:
  `{ "type": "log", "text": "Dust everywhere.", "when": { "path": "/visits/attic", "equals": 1 } }`.
  Arrival side-effects already see the new count.
- **Show** it with a placeholder: `"You have been here {/visits/attic} times."`.
- **Vary the arrival line** with an `arrivalText` array:
  `["The corridor is quiet.", "Still quiet.", "Nothing but dust."]` writes the first line
  on the first visit, the second on the second, and the last on every visit after that.

`visits` is **engine-managed**: do not declare it in `context.initial` or
`context.schema`, and no patch effect may target `/visits`. The engine leaves it out of
`context.schema` validation, like `notes`.

## Notes

Set `"notesEnabled": true` at the top level to give the player a notes button in
the game header. It opens a side panel with a free-form notes field.
Whatever the player types is stored in the game's `context` under the reserved
`notes` key (a string) and persists with the game like any other context state.

This is purely a player convenience — nothing in the engine reads `notes`, and no
condition should gate on it. `notes` is an **engine-reserved, engine-managed key**:
you do **not** declare it in `context.initial` or `context.schema`, and you must not
use `notes` as a top-level context key for your own state. The engine excludes the
`notes` key from `context.schema` validation, so a strict
(`additionalProperties: false`) schema keeps working unchanged once the player starts
typing notes.

## Waiting

Set `"waitEnabled": true` at the top level to give the player a **Wait** button in
every location. It costs one turn and does nothing else, so the world moves on while
the player stays put: [scheduled events](#scheduled-events-the-timeline),
[tick rules](#tick-rules) and [endings](#endings-winloss) fire as they do for any other
one-turn action. The button sorts after the location's own actions. The default is
`false`: no Wait button anywhere.

For waiting in only some locations, or with a custom label, cost, condition or
effect, add a normal [action](#actions) (for example `"timeCost": 3` and the label
"Lie still in the hay") and list it in those locations. Do not combine the two in one
location: with `waitEnabled` on, a location that also lists its own wait action shows
two wait buttons. The engine does not prevent this.

## What makes a good and valid story

The JSON Schema checks **shape** only. The content rules enforce point 1 and item-id
resolution: content that breaks them is rejected. Point 2 is not checked: a save accepts
an unreachable room, so walk the map yourself. The rest are conventions for a story that
plays well.

1. **Every exit must resolve.** Each exit's `to` must match an existing
   location id. Dangling exits strand the player.
2. **No orphan rooms.** Every location should be reachable from
   `starting_location` by following exits. Walk the graph mentally.
3. **Prefer two-way exits.** If `room_1` has `east → { to: room_2 }`, `room_2`
   usually wants `west → { to: room_1 }` so the player can backtrack. Intentional
   one-way drops (trapdoors, transporters) are fine — just deliberate.
4. **Exit labels are the player's vocabulary.** Use directions (`north`, `east`)
   for spatial maps, or named portals (`Turbolift`, `Captain's Quarters`) for
   evocative ones. Stay consistent within a story.
5. **Keep `description` a short factual "where you are."** One line, no atmosphere or
   appearance ("You are sitting next to Vale."). Mention a door/path only if it helps the
   player, but put the real flavor and any exit-motivating prose in a location `log`
   side-effect (which lands in the narrative log on entry), not the card.
6. **Location ids stay stable and snake_case** (`captain_quarters`); they are
   internal keys, not shown to the player. Edit `name`/`description` freely, but
   renaming an id means updating every `exits` reference and possibly
   `starting_location`.
7. **`order` is display-only.** It sorts a location's exit buttons ascending and
   has no effect on connectivity. Give exits within a location distinct orders to
   control button sequence; omit it (defaults to `0`) when sequence doesn't matter.
8. **Gate, don't strand.** Prefer `enabledWhen` (visible but dimmed) over
   `visibleWhen` (hidden) for locked exits, so the player sees the goal and knows
   to look for the key. Reserve `visibleWhen` for secrets that shouldn't be hinted.
9. **`isCarrying` references an item `id`, not its `name`.** Make sure the gated id
   actually exists as an item somewhere reachable, or the gate can never open.
10. **Don't bake item state into the room.** Put "a key glints here" on the item's
    `description` (with `descriptionByLocation` overrides) — it's logged on entry and
    follows the item as it's moved — never on the location `description`, which stays a
    fixed one-liner.
11. **Gate items sealed in containers.** An item declared in a location's `items`
    is grabbable the moment the player enters — there is no implicit "open the
    drawer first." If the prose says an item is locked away (in a drawer, safe, or
    behind a screwed panel), give it an `availableWhen` that passes only once the
    opening action has fired (e.g. `{ "path": "/desk/drawer_unlocked", "equals": true }`),
    or the player can take it without doing the puzzle.
12. **Narrate items revealed mid-visit.** An item's `description` is logged only on
    room entry. When an action makes an item available while the player is in the
    room, the item appears in the take list with no log line. If the player should
    notice the reveal, say so in that action's `log` side-effect (e.g. "Something
    clatters to the floor: a small screwdriver was tucked behind the frame.").

## Self-check before finalising

- `context` present (even `{}`); `starting_location` is a real location.
- Every exit `to` resolves; no orphan rooms.
- Every `isCarrying`, `at` location, action key, and condition `path` resolves to something real.
- Each condition object uses exactly one form; no extra fields anywhere.
- Any item whose prose says it's sealed in a container has an `availableWhen` gate
  tied to the action that opens it — it isn't a free starting take.
- Any item an action reveals mid-visit is mentioned in that action's `log`, unless the
  silent reveal is deliberate.
- `starting_inventory` ids are unique and don't collide with any location item id,
  and carry no `takeLabel`/`availableWhen`.
- Every `give`/`consume` effect names a real item (room, starting inventory or `items`
  catalog), no catalog id is also placed somewhere, and an action that consumes an
  item is gated on `isCarrying` of it so it disables once spent.
- Every patch effect (in an action, a timeline event or a rule) roots its `path` at a key
  declared in `context.initial`/`context.schema`, and none target the engine clock
  (`/turns`).
- Any `inc` op carries a numeric `value`; every spend action is gated with a
  numeric comparator (`atLeast`) so it disables when unaffordable, and any
  spendable number has a `context.schema` `minimum` so it can't go negative.
- Every `supply` condition and `{ supply, by }` effect names a declared supply; each
  supply's `initial` is within its `[min, max]`; every supply-spending action is
  gated with `{ supply, atLeast }` so it disables when the player can't afford it.
- Any `turnAtLeast`/`turnAtMost`/`turnEquals` gate reads a whole-game clock (player
  actions taken), not an abstract counter that belongs in `context`; any exit/action
  meant to be free of time cost carries `"timeCost": 0`, and any `timeCost` is an
  integer from 0 to 1000.
- Every `ending` has an `outcome` of `"win"`/`"loss"` and a non-empty `message`; its
  `when` references only real items (`isCarrying`) and declared supplies; and endings are
  ordered specific-before-general (the first matching one wins and shorts the rest).
- In a series: each win ending that should unlock the next story has an `output` that
  story's `input.schema` accepts, and no loss ending has one. A story with `input` only
  reads `/input/...` keys its `input.schema` declares, and never declares or patches `input`.
- Every exit and action that [can be interrupted](#scheduled-events-the-timeline) has an
  `interruptedText` that tells the player what stopped them.
- `timeline` events are sorted strictly ascending by `atTurn` (each `>= 1`, no two with
  the same `atTurn`; any `every` is an integer `>= 1`); every patch effect's path roots at a key declared in `context.initial`
  or `context.schema`, every `{ supply, by }` effect names a declared supply, and no
  effect touches the engine clock (`/turns` path or a supply named `turns`). An optional
  `message` narrates the event into the log as an `outcome` line.
- Every `rules` entry's effects follow the same rules as timeline effects, its `when`
  and side-effect gates reference only real items, supplies and locations, and every
  `log` side effect has text. A rule that should fire
  once per visit gates on a flag it sets itself.
- Every `{/path}` placeholder roots at a declared context key or `/visits/<location_id>`,
  every `{supply:<id>}` names a declared supply, and nothing declares or patches the
  reserved `visits` key. A `{/input/...}` placeholder needs a declared `input`.
- Every `context.randomize` key exists in `context.initial`, has at least 2 values,
  and each value satisfies `context.schema`.
- Any `sideEffects` entry (on a location, exit, or action) has a known `type`
  (`confetti`, `defeat`, `explosion`, `shake`, or `log`); any `isCarrying` inside its `when` resolves to a real
  item; every `log` effect has non-empty `text`.
- Each location `description` is a short factual one-liner (where the player is, nothing
  about how it looks); all atmosphere, room state, and item prose lives in the narrative
  **log** — a location `log` side-effect for how the room looks (unconditional) or its
  enduring state (`when`-gated), an action `log` side-effect for a reply/reveal, and a
  `timeline` `message` for a world event at a given turn.
