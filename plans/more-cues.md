# More cues

Status: ideas only (2026-11-22). Nothing built. New visual effects that stories can fire
as side effects, next to `confetti`, `defeat`, `explosion` and `shake`.

## How a cue works now

- A story lists it as a side effect: `{"type": "shake"}` on an exit, a location or a rule.
- The allowed names are a closed set in `priv/schemas/version.json`. Unknown names are
  rejected when a story is saved.
- The engine returns the non-`log` side effects as cues. `GameLive` pushes a `"cues"`
  event, and the `Cues` hook in `assets/js/cues.js` plays each one on `#game`.
- Cues are one-shot: they never change game state and are never stored.
- The look of an overlay lives in `assets/css/app.css` (`.defeat-flash`,
  `.explosion-flash`). Every cue respects `prefers-reduced-motion`.

So a new one-shot cue is: a name in the schema, a function in `CUES`, maybe a CSS class,
a line in `docs/story-format.md`, and the `game-story` skill if it lists the cues.

## Ideas

### Light and darkness

- **`flash`**: a short white flash with a small shake. Lightning, a camera flash.
  `explosion` without the fireball.
- **`flicker`**: the screen dims and brightens a few times. A broken lamp; horror.
- **`blackout`**: the screen goes dark within a second, for example when a candle goes
  out. As a one-shot it fades back after a few seconds. Staying dark until a
  `lights_on` cue needs state; see open questions.

### Senses and state of mind

- **`heartbeat`**: a dark red edge pulses two or three times. Fear, low health. A calm
  cousin of `defeat`.
- **`blur`**: the text goes blurry, then sharp again. A blow to the head, drugs, waking up.
- **`dizzy`**: the page sways slowly and the colours shift a little. Poison, seasickness.
- **`glitch`**: text jumps sideways and the colour channels split for a moment. Sci-fi,
  hacking, "reality breaks".

### Weather and surroundings

Short particle bursts. canvas-confetti (already vendored) can do custom shapes, colours,
gravity and drift, so these need no new library.

- **`rain`**, **`snow`**, **`embers`**
- **`dust`**: falling debris after a collapse. Pairs well with `shake`.
- **`smoke`** / **`fog`**: a grey layer that slowly clears. CSS, not particles.
- **`splash`**: blue at the screen edges. Falling into water.
- **`freeze`**: frost grows in from the corners. Cold, or a spell.

### Story beats

- **`sparkle`**: a small shine, for finding an item. Quieter than confetti; small wins.
- **`reveal`**: the new text fades in slowly, line by line, for a twist. This changes how
  the log renders, not an overlay, so it touches `GameLive` too.

### Sound (a different kind)

- **`chime`**, **`alarm`**, **`thunder`**: short sounds. Needs a mute setting first, and
  browsers block sound until the player has clicked once (they always have, since moves
  are clicks). Audio files go in `priv/static`.

## Suggested order

1. **`flash`, `blackout` (one-shot), `heartbeat`.** A few lines of CSS and JS each. They
   cover the most common adventure moments (lightning, darkness, danger), and you cannot
   build them from today's cues.
2. **`flicker`, `blur`, `glitch`.** Also small; more genre-specific.
3. **Weather particles.** Nice for mood, but they mark an event less clearly.
4. **`reveal`** and **sound.** Each needs more than a new entry in `CUES`.

## Open questions

- **Lasting effects.** A dark room or ongoing rain is a state, not a one-shot cue. Option:
  a location field such as `"ambience": "rain"` that the page shows while the player is
  there. Then it comes from the state on every render, also after a reload, and nothing
  new is stored.
- **Too many cues in one move.** Two overlays at once can look messy. Maybe play them one
  after another, or only the last overlay.
- **Testing.** Today the LiveView test checks the pushed event (`assert_push_event`). The
  animation itself is only checked by eye.
