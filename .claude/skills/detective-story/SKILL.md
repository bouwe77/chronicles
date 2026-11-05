---
name: detective-story
description: Design a fair, solvable detective or murder-mystery story for Chronicles (the hidden truth, a clue graph, alibis, red herrings and the accusation) and map it onto the story format. Use whenever the user wants to write, plan, extend, review or fix a mystery, whodunit, crime, murder, heist or "find the culprit" story in this repo, or check whether one is fair and solvable without guessing, even if they only say "a story where the player has to find out who did it". Covers design only; the format and saving live in docs/story-format.md and the game-story skill.
---

# Detective story design

You already know the classic theory (means, motive, opportunity, alibis, red
herrings, unreliable witnesses, the helpful culprit). This skill is about two
things you do _not_ get by default:

1. **A work order that keeps the logic in charge.** A mystery written
   atmosphere-first ends up with clues that do not add up. Build the truth
   first, then the clues, then the rooms and the prose.
2. **How the theory maps onto this engine**, so the player can actually _do_
   the detective work with exits, items, actions, context and endings.

For the format itself read [`docs/story-format.md`](../../../docs/story-format.md).
To save, use the [`game-story`](../game-story/SKILL.md) skill. Do not repeat
those rules here; follow them.

## Work order

Do the steps in order. Write steps 1 and 2 down (in the scratchpad, and show
them to the user) before you write any JSON. They hold spoilers, which is fine:
the user is the author.

### 1. The case file (the hidden truth)

- **Victim, killer, method.** The method must be physically possible for the
  killer, and the weapon must exist somewhere in the world.
- **Motive** for the killer, and a _plausible_ motive for every other suspect.
  A suspect with no motive is not a suspect.
- **Master timeline of the crime**, in story time ("21:40 Rhea leaves the
  galley"). One row per suspect per time slot, so you can see that only the
  killer has the unobserved gap. This is the story's past, told through
  statements and evidence. It is _not_ the engine `timeline`.
- **What each innocent is hiding.** An unreliable witness lies to protect a
  secret unrelated to the murder. Decide the secret and the clue that exposes it.
- **What the killer did to cover up**: a planted red herring, a false alibi,
  "helping" the detective.

**Match the size to the request.** Every suspect adds a full set of clues to
clear them, and every proof clue adds steps. The rigour above does not need a
big story: a fair case can be small. As a guide:

| Request        | Suspects | Rooms | Proof set | Shortest win |
| -------------- | -------- | ----- | --------- | ------------ |
| "short"        | 3        | 4–6   | 2–3 clues | 10–15 steps  |
| default        | 3–4      | 6–8   | 3–5 clues | 15–25 steps  |
| "long", "hard" | 4–5      | 8+    | 5+ clues  | 25+ steps    |

### 2. The clue graph

A table with one row per clue. This is the most important artefact; the
fairness check runs against it.

| Clue              | Where / how found                            | Gate (what must happen first) | Points to                    | Rules out                    |
| ----------------- | -------------------------------------------- | ----------------------------- | ---------------------------- | ---------------------------- |
| laced ration      | galley counter, after "Search the dispenser" | —                             | method: poison at the galley | Vance (never in galley)      |
| Vance's watch log | bridge terminal                              | —                             | —                            | Vance (alibi verified)       |
| torn glove        | Okonkwo's cabin                              | —                             | Okonkwo (red herring)        | —                            |
| clinic receipt    | infirmary desk                               | ask Okonkwo about the glove   | —                            | Okonkwo (explains the glove) |

Then mark the **proof set**: the clues that together name the killer and how.
These gate the winning ending. Include every link the deduction needs, not just
the final ones. If one link is missing from the gate, the player can win
without ever having the logic that proves it.

Read the graph as a chain. Hard clues should be found _because of_ earlier
ones (statement → contradiction → search → evidence), not in the first room.

### 3. Map the graph onto the engine

| Mystery concept                                             | Engine form                                                                                                                                                                                                                                                                                                               |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Physical evidence                                           | An **item**. It shows in the Carrying panel, so the player sees the case grow. Hidden evidence gets `availableWhen` tied to the search action.                                                                                                                                                                            |
| A fact learned (testimony, an observation, a cleared alibi) | An **action** with a `log` line, plus a **catalog item** it `give`s (e.g. "Vance's alibi: confirmed by the watch log"), so the fact stays visible. Use a bare context flag only for internal state the player need not see (searched, asked).                                                                             |
| An anomaly (something missing or wrong)                     | An examine action (`timeCost: 0`) that logs the anomaly and gives a note item. You cannot carry an absence.                                                                                                                                                                                                               |
| Questioning a suspect                                       | Actions in the suspect's room. First ask → their statement + flag `/alibi/<suspect>/heard`. Repeat visits can add detail via `arrivalText` arrays or `/visits/<room>` gates, but never hide a _required_ clue behind a visit count alone; the player cannot see it.                                                       |
| Testing an alibi                                            | A "Confront <suspect> with <clue>" action, `visibleWhen` the statement was heard **and** the clue is carried. Use `visibleWhen`, not `enabledWhen`: a dimmed button still shows its label, and the label tells the player what to look for. It logs the reaction and gives the result (alibi broken, or verified).        |
| Red herring                                                 | Evidence that points at an innocent, _plus_ the rebuttal clue that explains it. Both rows go in the graph.                                                                                                                                                                                                                |
| Helpful culprit                                             | An action where the killer offers help. Their statement contains one detail they could only know if guilty, or one that contradicts physical evidence. That slip is a clue in the graph.                                                                                                                                  |
| Deduction                                                   | `notesEnabled: true`, and a "Review the case" action whose `log` lines are `when`-gated on what the player holds, summing up what is proven and what is still open. It names the open questions ("You still cannot say how the poison reached the glass"), so a player who is one clue short knows it before they accuse. |
| Time pressure (optional)                                    | An engine `timeline` event or a `turnAtLeast` loss ending: the killer leaves on the shuttle at turn 40. Use only if it adds tension, and tell the player the deadline.                                                                                                                                                    |
| Accusation                                                  | See below.                                                                                                                                                                                                                                                                                                                |

#### The accusation

Store the player's choice in context:

```json
"context": {
  "initial": { "case": { "accused": "none" } },
  "schema": { "...": "case.accused is an enum: none + one value per suspect" }
}
```

- One action per suspect, e.g. `accuse_rhea`, `visibleWhen`
  `/case/accused` equals `"none"`, effect `replace /case/accused`. Put them in
  one place (the room where the suspects gather), so accusing is a deliberate
  step.
- Endings, in this order:
  1. **win**: accused is the killer **and** the player holds the proof set.
  2. **loss**: accused is the killer **without** the proof ("right person, no
     proof; they walk free"). This stops a lucky guess from winning.
  3. **loss**: any other suspect accused. The message says _why_ they are
     innocent, so the player learns from it.
- Leave the buttons enabled from the start, so the player can guess and pay
  for it. Gating every accusation on the same evidence adds nothing: once the
  player has it, all buttons open at once.

### 4. Rooms and prose

Now build the map around the clue graph: each clue's location is a room or an
action in a room. Follow the format's text rules (short factual `description`,
prose in `log` side-effects). Write statements in each suspect's own voice, and
let liars sound as confident as truth-tellers. Give every suspect about the
same presence (a place to find them, a statement, something to search), so the
shape of the map does not point at the culprit.

### 5. Fairness check

Walk the graph, and then the JSON, as a player. Report the result to the user.

- **Every proof clue is reachable** from the start without accusing anyone and
  without a step that closes for good (a timeline event, a consumed item, a
  one-way exit).
- **Each innocent is ruled out by at least one clue** the player can find, not
  only by the text of the wrong-accusation ending.
- **Every red herring has a reachable rebuttal.**
- **No winning ending before the proof is found**: check the win ending's
  `when` against the proof set, and that a correct guess without proof hits the
  loss ending.
- **At least one clue points _at_ the killer**, so the case is not solved by
  elimination alone.
- **Statements match the master timeline**, and every lie is exposed by a clue.
- **Nothing the player sees gives the answer early**: no button label, exit
  label or log line names the culprit or the key fact before the evidence for
  it is found. Remember that dimmed buttons and exits show their labels.
- **Write the shortest winning path** as a list of steps. If a step is not
  hinted by an earlier clue or log line, add the hint. Compare its length with
  the size table in step 1.

**Play it with the real engine.** Write a `paths.json` with at least: the shortest
winning path (`"expect": "win"`), the culprit accused at once (`"loss"`), the
culprit accused with all proof but one (`"loss"`), and each innocent accused
with all proof in hand (`"loss"`). Then run, from the repo root:

```bash
mix chronicles.playthrough story.json paths.json
```

A step is `go:<exit label or room id>`, `take:<item id>`, `drop:<item id>`,
`wait` or an action key. The task checks the content like a save, fails when a
path ends wrong, and names the step and what was available when a path breaks. Fix the JSON until every line is `ok`.

Then run the format document's _Self-check before finalising_ and save with the
`game-story` skill.

## Reviewing an existing mystery

Rebuild the case file and the clue graph from the JSON first (fetch the head
content as the `game-story` skill shows). Then run the fairness check and
report each failure with the fix. Common ones: all accusations gated on the
same evidence, innocents only cleared in ending text, a wrong accusation that
costs nothing, and a dimmed button or exit whose label gives the answer away.

Lead with the verdict and the smallest set of fixes that makes the case fair.
Offer a full redesign in one or two lines, and write it out only if the user
asks.
