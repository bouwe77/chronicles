# Command mode

Status: idea, low priority (2026-10-25). No story needs it and no player asked for it. It
is written down because it turned out cheaper than expected. Pick it up when a story asks
for a classic text-adventure feel.

## What it is

The author picks one of two modes per story:

- **buttons** (default, what exists): the player picks from the options on screen.
- **commands**: no option buttons. The player types `go west`, `take candle`,
  `light the lamp`, and the game runs the option that matches.

Command mode is another way to pick from **the same options**. The engine doesn't change.

## Why it is cheap

- `Engine.view/2` already gives the options for the current room: exits, actions,
  items to take and carried items to drop. A command box only matches the typed text to
  one of them and sends the same command to `Engine.move/3`.
- Each option already has text a player could type: an exit's label, an action's
  `description`, an item's `name`.
- The log already writes each move as a command line.

## The real cost: authoring

A command-mode story only works if every label is **the most obvious thing to type**.
Labels in today's stories are prose for a button. So it is a story-level choice, not a
player setting, and the docs and skill need guidance: short, verb + noun, no
punctuation, one obvious wording per option.

## Plan

1. **Format.** `inputMode: "buttons" | "commands"` on the story (default `buttons`), in
   the schema, the validator and `docs/story-format.md`. Validator rule for command mode
   only: in each location, no two options may give the same text after normalising
   (the exit `North` and the action `Go north` clash).
2. **The matcher.** A pure function `match(input, options)`: lowercase, trim, drop
   punctuation and filler words (`go`, `walk`, `the`, `a`, `an`, `to`); short directions
   (`n`, `e`, `s`, `w`, `ne`, `nw`, `se`, `sw`, `u`, `d`); `take`/`get`/`pick up X` and
   `drop X` match item names; otherwise exit and action labels. With a test.
3. **The game page.** For a command-mode story, hide the option buttons and show a text
   input. A match that is enabled runs the move. No match writes the typed text and
   "I don't understand that." to the log. Built-in commands, because the player can't
   see the options: `look`, `inventory`/`i`, `wait` (with `waitEnabled`), `help`.
   Command history with the arrow keys can wait.
4. **Try it** with one small story and watch where players get stuck on wording.

## Open decisions

1. **What does a disabled option answer?** (a) like an unknown command, (b) "You can't do
   that right now.", or (c) a per-option `disabledText`. Leaning (b): fair, and the hint
   is small.
2. **Aliases** (`grab` for `take`, `torch` for `lamp`): an optional `aliases` list on
   actions and items. Skip until the test story shows normalising isn't enough.
3. **Examine:** `examine X` could print the item's `description`. Decide after step 4.
4. **Switching modes as a player:** not in the first version.
