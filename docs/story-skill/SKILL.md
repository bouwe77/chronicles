---
name: chronicles-story
description: Write or edit a Chronicles story as a JSON file that the user uploads in the Chronicles web app. Use when the user wants to create, change or fix a Chronicles story, or its locations, exits, items, actions or endings.
---

# Chronicles story

You write a story as one JSON file. You cannot save it yourself: the user uploads it in
the web app ("Upload a story"), and the app checks it.

1. Read `story-format.md` in this skill. It describes the content format and what makes
   a story good and valid. `story-schema.json` is the exact JSON Schema of that format.
2. Pick a slug: a kebab-case name such as `the-front-door`. Name the file after it
   (`the-front-door.json`); the upload takes the slug from the file name. To edit an
   existing story, ask the user for its current JSON and its slug.
3. Write the content JSON. It has no id or slug field.
4. Run the format's "Self-check before finalising" and fix what fails.
5. Give the user the complete JSON as a file (or one code block) to upload.

If the upload fails, the app lists every problem and lets the user copy that list.
When the user pastes it back, fix each problem and give the complete JSON again.
