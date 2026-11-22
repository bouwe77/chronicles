# Location images

Status: decided, not built (2026-11-22). An optional picture per location, shown as a
banner in the log, to make a story more immersive without taking space from the log or
the buttons.

## Why a banner in the log

The game page has no free space:

- **Desktop (`lg` and up):** the log on the left at a fixed `75vh`, with its own scroll.
  On the right a `22rem` column with panels: Items, Actions, Exits, Time, You, Carrying.
  Actions and Exits are clicked every turn. Anything above them pushes them down.
- **Phone:** one column. The log is only `40vh`, the panels come below it.

The only large area that is always on screen is the log. We compared four options in a
mockup (https://claude.ai/artifact/4gZhEVeUcFkQzoBKTKfxwu):

1. **A banner in the log, above the location heading.** ← chosen
2. A darkened background behind the log. Rejected: the image loses its detail, and text
   contrast is hard in both themes.
3. An image card at the top of the right column. Rejected: pushes Actions and Exits down;
   on a phone it sits below the log.
4. A thumbnail that opens on click. Rejected as the main idea, but kept as a small extra:
   clicking the banner opens the full image.

## Decisions

- **Shape.** A wide banner, `aspect-ratio: 3 / 1`, `object-fit: cover`, rounded, full log
  width. Capped with `max-height` (about `14rem`) so it stays a banner on wide screens.
  On a 375px phone it is about 125px high.
- **Where.** Above the location heading, inside the same log item. It scrolls away with the
  history, so the newest place is near the bottom.
- **When.** On every arrival, like the heading itself. Simplest, and consistent with
  `arrivalText`. Revisit if a story with a lot of back and forth feels heavy (see Later).
- **Click.** The banner is a link to the image (`target="_blank"`). No lightbox code.
- **Source.** An external `https` URL in the story. No uploads in this step.
- **Alt text.** Optional `imageAlt`. Without it the image is decorative (`alt=""`), because
  the arrival text already describes the place.
- **Old games.** Log entries written before this change have no location id, so they show
  no banner. No migration.

## Changes

### Story format

- `priv/schemas/version.json`, under `locations` → `additionalProperties` → `properties`:
  - `"image": {"type": "string", "pattern": "^https://"}`
  - `"imageAlt": {"type": "string", "minLength": 1}`
- `docs/story-format.md`: add both to the locations table (next to `arrivalText`), with
  the advice "wide pictures work best; they are cropped to 3:1".

### Engine

- `Chronicles.Engine.LogEntry`: add `field :location, :string`, the location id, set only
  on `:location` entries. Update the moduledoc. It is embedded in the game state
  (`embeds_many :log`), so there is no migration; old entries load with `nil`.
- `Chronicles.Engine.arrival_lines/2`: set `location: id` on the heading entry. `entry/3`
  builds the struct now; add the field there or build this one entry directly.

### Game page

- `ChroniclesWeb.GameLive`: the log items are now one `<p>` each. A `:location` item
  becomes a wrapper element (it keeps the stream `id`) with the banner and then the heading
  `<p>`, so the `role="heading"` stays on the text only.
- A helper looks up `@game.version.content["locations"][entry.location]["image"]`. A game
  is pinned to one version, so the image can't change under the player.
- The image: `<img src alt loading="lazy">` inside `<a href target="_blank" rel="noopener">`,
  with the fixed aspect ratio, so the log does not jump when it loads and `.ScrollToEnd`
  still lands at the bottom.
- No content security policy is set today, so external images load without config.

### Tests

- Engine: arriving in a location writes a `:location` entry with its id.
- `GameLive`: a location with `image` shows `#log img` with that `src`; one without does
  not. Use a stable id on the banner for the selector.
- Schema: an `image` that is not `https://` is rejected.

The `game-story` skill points to `docs/story-format.md` for fields, so it needs no change.

## Later

- **Uploads.** LiveView uploads stored on a Fly volume or S3-like storage (Tigris on Fly),
  with size limits and resizing. Do this when authors ask, or before going live if broken
  external links are not acceptable.
- **Less repetition.** Show the banner only on the first visit, or only when the last
  banner in the log was a different location. The engine already counts visits.
- **Editor preview.** Show the image next to the location in the story editor.
- **A real lightbox** instead of opening the image in a new tab.
