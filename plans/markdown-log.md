# Markdown in the log

Status: built (2026-11-23). Two changes from the plan below: one module,
`Chronicles.Markdown`, does both the check and the rendering (no `ChroniclesWeb.Markdown`),
and the ending dialog renders its message as Markdown too.

Authors can write log text in Markdown: paragraphs, headings, lists, block quotes, and a
few inline styles. The log shows it as formatted text instead of one plain paragraph.

## Why

- A log line is one plain string, shown in one `<p>`. Newlines in it collapse into
  spaces, so a long text reads as one block.
- Three stories already write `\n\n` between paragraphs (`my-spaceship`,
  `the-mess-deck-murder`, `the-vanishing`), and `feature-showcase` puts backticks
  around field names. Players see none of it today.
- Teaching text, like the course story, needs structure: a heading, short paragraphs, a
  list, field names in `code`.

## Decisions

1. **Always on.** No per-story flag. A scan of all 19 stories (2026-11-23) found no text
   that Markdown would break, and the four stories above get better without changes.
2. **Only log prose.** Every text the engine writes to the log as an `outcome` line:
   `log` side effects, `arrivalText` and `description` on arrival, item `description`
   and `descriptionByLocation`, `openingLog`, timeline `message`, `interruptedText`,
   and ending `message`. Not Markdown: location names (the log heading), command lines
   (`> Pull the lever`), button labels, `descriptionWhenCarried` (Carrying panel), and
   the story's overview `description`.
3. **The syntax.**
   - Blocks: paragraphs, headings (`#` to `######`), bullet lists, numbered lists, block
     quotes, horizontal rule (`---`).
   - Inline: `**bold**`, `*italic*`, `` `code` ``.
   - Not supported: links, images, raw HTML. Tables and strikethrough are Markdown
     extensions that we keep off, so pipes and tildes simply show as text.
4. **Unsupported syntax is rejected on save.** A link (`[text](url)` or `<https://…>`),
   an image or raw HTML in a log prose field gives a validation error, like the other
   rules: `locations/cellar/sideEffects/0/text: links are not supported in log text`.
5. **One newline is a line break.** An empty line starts a new paragraph. So what the
   author types is what the player sees.
6. **All headings look the same:** body size, semibold, some space above. The location
   name stays the bigger heading. For screen readers every Markdown heading becomes one
   level below the location heading (level 4), whatever the number of `#`.
7. **Library: [MDEx](https://hex.pm/packages/mdex).** It wraps comrak (Rust) and ships
   precompiled, so no Rust toolchain is needed. It gives a parsed tree, which the save
   check and the heading change both need.
8. **The course story gets a full rewrite** in Markdown. See below.

## How it works

### Rendering, when the page shows the log

The engine keeps storing plain strings in `LogEntry.text`; nothing in the game state
changes. `GameLive` renders Markdown when it shows an `outcome` entry. So old saved games
get the new look too, and no data migration is needed.

- A small module `ChroniclesWeb.Markdown` with one function `to_html/1` (it uses the
  parse options from `Chronicles.Markdown`, see Validation):
  1. `MDEx.parse_document!/2` with `render: [hardbreaks: true]` and all extensions off.
  2. Set every heading node's level to 4.
  3. Render to HTML with `unsafe: false` (the default). Raw HTML is never rendered,
     also for old text that was saved before the check existed.
- In `GameLive.render/1`, an `outcome` entry becomes a `<div class="log-prose">` with
  `{Phoenix.HTML.raw(Markdown.to_html(entry.text))}`. It can't stay a `<p>`, because a
  `<p>` can't hold lists or headings. Location and command entries keep their `<p>`
  and plain `log_text/1`.
- Placeholders are filled when the line is written, before any Markdown. A context value
  with Markdown characters (`*`) is formatted too. Story authors control those values,
  so this is fine.

### Styling

Plain CSS rules in `assets/css/app.css` under `.log-prose` (no `@apply`, per
`AGENTS.md`). No typography plugin.

- Paragraphs, lists and quotes: the same `leading-relaxed` text as today, with a small
  gap between blocks inside one entry, smaller than the gap between log entries.
- `h1`–`h6` (all rendered as `h4`): body size, semibold, space above unless first.
- Lists: `disc` and `decimal` markers, indented.
- Block quote: a left border and muted text.
- `code`: monospace, a light background, rounded.
- `hr`: a thin line in the border colour.

### Validation, when a story is saved

In `Chronicles.Stories.Validator`, a new `markdown_errors/1` next to the placeholder
check. Unlike `placeholder_errors`, which walks every string, it visits only the log
prose fields from decision 2. For each text it parses with the same options and reports
`Link`, `Image`, `HtmlBlock` and `HtmlInline` nodes, one error per kind per field.

The validator lives in the core app, so the parse options and the check go in a core
module, `Chronicles.Markdown`. `ChroniclesWeb.Markdown` uses those options and only
renders.

## The course story (`the-model-course`)

A full rewrite through the API, with the `game-story` skill, tested with the real engine.

- Each lesson's notes become one Markdown entry: a heading, short paragraphs, a list
  where there is a list, and `code` for field names, paths and JSON.
- Questions and feedback lines are rewritten in Markdown too. They stay separate log
  effects, because they have their own `when` conditions.
- The lesson about the log gets a short note and one question about Markdown in log
  text (what is supported, what is rejected).
- The course must still pass its own checks: every question reachable, every answer
  correct as written.

## Other changes

- `docs/story-format.md`: a section "Markdown in log text" with the syntax, the
  newline rule, what is rejected, and which fields it applies to. A note in the field
  table rows of those fields.
- `.claude/skills/game-story`: a short note that log prose may use Markdown, and the
  limits.
- `mix.exs`: add `{:mdex, "~> …"}` (pick the current version at build time).

## Tests

- `Chronicles.Markdown`: the check finds a link, an autolink, an image and raw HTML, and
  accepts the supported syntax.
- `ChroniclesWeb.Markdown`: one newline gives `<br>`, `###` renders as `h4`, raw HTML
  in old text is not rendered.
- Validator: a story with a link in a `log` side effect is rejected with the field path;
  a link in `descriptionWhenCarried` is not checked.
- `GameLive`: a game whose log has a Markdown list shows the list inside `#log`
  (`has_element?(view, "#log ul li")`). Check existing selectors on `#log p` still hold.

## Steps

1. Add MDEx; `Chronicles.Markdown` and `ChroniclesWeb.Markdown` with tests.
2. Render outcome entries as Markdown in `GameLive`; CSS in `app.css`.
3. The save check in the validator, with tests.
4. Docs and the `game-story` skill.
5. Rewrite the course story; play it through.
6. `mix precommit`.
