# Time mode

Status: designed (2026-10-27), not built. All decisions below are made; check them once
more against the engine before building.

## What it is

Today the only clock is the turn counter (`State.turns`). Exits and actions move it by
their `timeCost` (default 1). The `turn*` conditions, the `timeline` (`atTurn`, `every`)
and the tick `rules` read it, and the game page shows the raw number.

Time mode lets an author use a real date and time instead: "Sun 5 Jul, 20:30" rather
than "Turn 5". A story is **either** turn-based **or** time-based, never both.

**The key simplification:** the counter stays one integer. In turn mode it counts turns;
in time mode it counts **minutes since the start**. The clock, timeline, rules, endings
and interruptions keep working as they are. Only the unit, the default step, the
condition forms, the rule rhythm and the display change per mode.

## The mode switch

A top-level `clock` object puts a story in time mode. Without it, the story is in turn
mode. The validator rejects the wrong vocabulary (the JSON Schema can't express this):

- time mode rejects `turnAtLeast` / `turnAtMost` / `turnEquals` and `timeline[].atTurn`;
- turn mode rejects `timeAtLeast` / `timeAtMost` / `timeEquals` and `timeline[].atTime`.

`timeCost` and `timeline[].every` keep their names: turns in turn mode, minutes in time
mode.

### `clock`

| Field         | Type             | Notes |
| ------------- | ---------------- | ----- |
| `epoch`       | string           | **Required**; ISO-8601 datetime the game starts at (counter 0), e.g. `"2026-07-05T18:00"`. |
| `defaultStep` | integer (`>= 1`) | Optional (default `1`); minutes an exit, action or the built-in wait costs when it has no `timeCost`. A story in half-hours sets `30`. |
| `display`     | string           | Optional (default `"datetime"`); `"datetime"`, `"time"` or `"date"`: what the clock shows. |

`defaultStep` is at least 1, so wait always moves the clock.

## Decisions

### Conditions and timeline use absolute datetimes

`{ "timeAtLeast": "2026-07-05T20:00" }` and `timeline[].atTime`. They are converted to
minutes since `epoch` and compared as integers. An `atTime` must be after `epoch`, and the
timeline stays strictly ascending, checked on the converted minutes. Durations
(`defaultStep`, `timeCost`, `every`) are whole minutes.

### Rule rhythm: `every`, `from` and `accumulate`, in both modes

| Field        | Type             | Notes |
| ------------ | ---------------- | ----- |
| `every`      | integer (`>= 1`) | **Required in time mode.** Optional in turn mode, default `1`, so existing stories don't change. |
| `from`       | integer / string | Optional; where `every` starts counting. Default the start (counter 0). A turn in turn mode, a datetime in time mode. |
| `accumulate` | boolean          | Optional, default `false`. |

- **Sample** (default): the rule fires on step `s` when `s >= from`,
  `(s - from) % every == 0` and `when` holds at `s`. It fits world rhythms: "every hour
  the guard checks the hall".
- **Accumulate**: each step `s >= from` where `when` holds adds 1 to the rule's count.
  When the count reaches `every`, the rule fires once and the count drops by `every`. It
  fits exposure: "every 10 minutes in the heat".
- **The partial count is kept** when `when` stops holding, so the player can't dodge
  damage by stepping out just in time. An author who wants a reset patches the count to 0.
- **The count lives in context** under the engine-managed key `ruleTime`
  (`/ruleTime/<rule index>`), like `visits`. The index is stable, because a game pins
  its version. Only accumulating rules get an entry. Conditions and placeholders can read
  it; a path must name an accumulating rule.

### During a long exit, rules run in the room the player left

As today: the steps before the last run their rules in the old room, and only the last
step runs at the destination. This matches an interrupted move. The docs advise to keep
long exits away from rooms with `at` rules, or to give a long trip its own room.

### Timeline and rules both stay

Timeline = scheduled events (a start, no condition). Rules = conditions with a rhythm.
Timeline events don't get a `when`, so the overlap doesn't grow. Merging them is a later
step.

### Repeated log lines are collapsed

A long jump can write one line per firing (a night of `every: 10` is about 48 lines).
Identical lines **in a row** from one move become one line with a count (`… ×48`), for
timeline and rules alike. Different placeholder values or alternating lines stay
separate.

### `timeCost` cap per mode

`1000` in turn mode (as today), `10080` (one week of minutes) in time mode.

### The device clock plays no part

In-game time is `epoch` plus the minutes the player's moves added. Never the real time.
Every datetime is read and formatted as UTC, so there are no 23- or 25-hour days, and
every player sees the same clock for the same state. The player's language still picks
the format.

## Where it lands

- **Schema** (`priv/schemas/version.json`): the `clock` object; the three `time*`
  condition forms next to the `turn*` ones; a timeline event takes `atTurn` **or**
  `atTime`; the rule fields `every`, `from`, `accumulate`; the higher `timeCost` cap.
- **Validator** (`Chronicles.Stories.Validator`): the mode check, parsing `epoch` and
  every datetime, `atTime` after `epoch`, timeline order on minutes, `every` required on
  rules in time mode, `from` in the mode's vocabulary, the cap per mode, and `ruleTime`
  reserved like `visits`.
- **Engine** (`Chronicles.Engine`): convert every `time*` condition, `atTime` and rule
  `from` to minutes once per version, so the rest keeps comparing integers. Default cost
  `clock.defaultStep` in time mode. The rule rhythm in `run_rules`. Collapse repeated log
  lines. `view/2` tells the page the mode and the minutes.
- **Game page** (`GameLive`): show the formatted clock instead of the turn number, and a
  minutes label instead of "+N turns" on the buttons. Formatting and its translations
  belong in the web layer (Gettext).
- **Docs**: the "Time & turns" section of `docs/story-format.md` opens with the mode
  choice and covers all of the above; the game-story and detective-story skills follow.

## Open point

`Calendar.strftime` only knows English month and day names. A Dutch clock needs its own
names through Gettext, or the `display` presets must avoid names.

## Check

Write a small time-mode story with the game-story skill on port 9278: `clock` with
`epoch: "2026-07-05T18:00"` and `defaultStep: 30`, `waitEnabled`, a sleep exit with
`timeCost: 480`, a dawn event at `atTime: "2026-07-06T06:00"`, an hourly event, a sampling
and an accumulating rule, and an exit gated on `timeAtLeast: "2026-07-06T06:00"`. Play
it: sleep shows "Mon 6 Jul, 02:00", dawn fires during the skip, the hourly event fires
once per hour, rule lines collapse, the accumulating count survives leaving the room,
wait adds 30 minutes, and the gated exit opens after 06:00. Mixed vocabulary is
rejected. Existing turn-mode stories and their tests don't change.

## Not in v1

- Time-of-day or recurring conditions (`timeOfDayAtLeast`).
- `"1h30m"` duration strings.
- A `{time}` placeholder in texts.
- Merging timeline events and rules (breaks every story with a timeline).
- Skipping quiet minutes during a long jump (only matters for very large jumps).
