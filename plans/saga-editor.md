# Saga editor

Status: built (2026-11-22), both steps. Creating and editing sagas in the app, so
authors don't need the API.

## Decisions

- **Separate pages.** `/sagas/new` and `/sagas/:slug/edit`, like the story pages. The saga
  page (`/sagas/:slug`) stays the page for players. One LiveView for new and edit, in
  `live_session :require_authenticated_user`.
- **Who.** Authors and admins create sagas ("New saga" on the overview, next to "New
  story"). The saga's author and admins edit and delete it ("Edit" and "Delete" on the
  saga page).
- **Only stories you manage can be chapters.** Your own stories, or any story for an
  admin. Then the visibility button and the link editor (which saves two chapters) always
  work. The API (`save_saga/3`) gets the same rule. In the "Add chapter" list, stories
  that can't be added (in another saga, the other visibility) are greyed out, with the
  reason.
- **Save only when valid.** The saga checks run live while editing; Save is disabled
  until there are none. Same as the API.
- **The slug** comes from the title for a new saga (like stories) and stays fixed.
- **Order** with ↑ / ↓ / remove buttons, not drag and drop: works with the keyboard and
  needs no JavaScript library.
- **Changing a saga people play is allowed.** Finished games stay as they are; progress
  on the saga page follows the new order.
- **Deleting a saga** keeps its chapters. The confirm text says that chapters 2 and up
  can't be started anymore.

## Input and output: stored in the chapters, edited together

An ending's `output` and the next chapter's `input` are two halves of one agreement.
They stay stored in the chapters: output values differ per ending, a chapter must stay
valid and testable on its own, and games pin a story version. But the saga editor is the
place to see and edit them together.

- **The link check (step 1).** Between each pair of chapters, read-only: what each win
  ending hands on, what the next chapter needs, and per ending whether it is accepted
  (`Validator.accepts_input?/2`). Loss endings must hand on nothing the next chapter
  accepts. A first chapter with `input` gets a ✕. Fix buttons open the story editor at
  `endings` or at the story part with `input`, which needs `?part=` in the editor's URL.
- **The link editor (step 2).** Per pair, side by side: the endings of chapter N with
  their output values, and the input of chapter N+1. Checked live. "Generate from the
  endings" builds the input schema from the outputs (keys, types, ranges, required).
  "Save link" saves both chapters in one transaction: a new version of each, or neither.
- **Write a new chapter (step 2).** Next to "Add a chapter", for a saga that is already
  saved: it opens `/stories/new?saga=<slug>`, and after "Create" the saga editor opens
  with the new story added at the end, not saved yet. With "Generate from the endings"
  the new chapter can get its `input` at once, so the link is valid right away. Not for
  an unsaved new saga: it only lives in the browser and would be lost.

The schema shows as a short summary per field ("spare · integer, 0–3, required"), with
the JSON folded under it; the JSON shows open for a schema the summary can't describe.

## Steps

1. The saga form: title, chapters in order, add/remove/reorder, the live checks and the
   link check with fix buttons. New, edit and delete. `?part=` in the story editor. The
   API rule for managed stories.
2. The link editor, with "Generate from the endings" and the save of both chapters.
   "Write a new chapter" from the saga editor.
