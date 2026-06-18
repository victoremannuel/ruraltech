---
name: brain-sync
description: Sync implementation progress into existing brain notes using Graphify first, strict read budgets, and incremental updates.
argument-hint: "[optional-scope: file, folder, module, note, or topic]"
disable-model-invocation: true
allowed-tools: Read,Write,Edit,MultiEdit,Bash(find:*),Bash(ls:*),Bash(cat:*),Bash(test:*),Bash(pwd),Bash(git status:*),Bash(git diff:*),Bash(git rev-parse:*),Bash(graphify:*)
---

Synchronize the current implementation state of the project into existing Obsidian brain notes using Graphify first, existing notes second, and raw file inspection only when strictly necessary.

Argument:
$ARGUMENTS

Accepted forms:
- empty → sync only the most relevant recent hotspots
- a repository file path
- a repository folder path
- a module/component name
- a note path inside `brain/`
- a topic name

Examples:
- `/brain-sync`
- `/brain-sync app/`
- `/brain-sync gateway`
- `/brain-sync brain/projetos/ruraltech.md`
- `/brain-sync src/gateway/lora.ts`

## Goal

- reconcile implementation progress with the current brain
- use Graphify as the primary source of repository structure and change context
- identify what was implemented, what changed, what is still pending, and which notes should be updated
- update only clearly impacted notes
- preserve note structure whenever possible
- avoid broad repository scanning
- avoid rewriting notes that are already accurate
- refresh inline links after note updates using `brain-links`

## Allowed brain targets

Prefer updating existing notes inside:

- `brain/projetos/*`
- `brain/arquitetura/*`
- `brain/decisoes/*`
- `brain/tarefas/*`
- `brain/conhecimento/*`
- `brain/sessoes/*` only if a session checkpoint is clearly justified

Ignore:
- notes tagged with `plugin`
- notes unrelated to `ruraltech` when tags are present

Preserve existing tags.
If a new note must be created, add:
- `#ruraltech`
- the folder tag matching the destination folder

## Source of truth priority

Always use this order:

1. Graphify artifacts under `graphify-out/`
2. explicit scope passed in `$ARGUMENTS`
3. existing relevant notes in `brain/`
4. cheap git signals for narrowing scope
5. raw implementation files only if still required

Never start with raw file scanning.

## ROI-based sync planning

Before reading note bodies or raw implementation files, rank candidate sync targets by value per token.

Prioritize:
1. high-impact, low-cost notes
2. scoped project, architecture, and task notes
3. only then decision or knowledge notes
4. session notes only when a milestone is clear

Do not start with the longest or most generic notes.

## Hotspot-first strategy

If no explicit scope is provided:

1. inspect cheap git signals
2. inspect Graphify component or community summaries
3. select only the top 5 most likely impacted scopes
4. sync only the top 3 unless more are clearly required

## Change-detection gate

Before reading note bodies:

- check whether the relevant implementation scope actually changed
- if no meaningful change is detected, skip sync
- if a candidate note already reflects the current implementation state, skip it
- do not update notes just because they look related

## Path and scope resolution

1. If `$ARGUMENTS` is empty:
   - infer the smallest useful scope from cheap git and Graphify signals
2. If `$ARGUMENTS` is a repository file or folder path and exists:
   - use it as the sync scope
3. If `$ARGUMENTS` is a `brain/...` note path and exists:
   - use that note as the anchor and sync only directly related implementation context
4. If `$ARGUMENTS` is a topic or module name:
   - resolve it using Graphify names, note titles, filenames, tags, and existing links
5. If scope cannot be resolved safely:
   - stop and explain what is ambiguous

## High-level workflow

1. Confirm whether `graphify-out/` exists
2. If Graphify is missing or clearly outdated, run:
   - `graphify .`
3. Inspect which Graphify artifacts actually exist
4. Read the smallest useful Graphify artifact set first
5. Resolve scope
6. Use cheap git signals only to narrow candidates
7. Find candidate notes using cheap signals
8. Read only the top relevant notes
9. Read only the minimum required implementation files
10. determine implementation deltas
11. update only impacted note sections
12. save notes
13. run `brain-links` only for notes that changed
14. print a short sync report

## Graphify-first policy

Always prefer Graphify artifacts over raw repository scanning.

Use this order when available:

1. `graphify-out/GRAPH_REPORT.md`
2. `graphify-out/wiki/index.md`
3. other summary-level Graphify artifacts in `graphify-out/`
4. raw files only if still needed

If those exact files do not exist:
- inspect `graphify-out/`
- use the available summary-level artifacts
- do not fail only because a specific expected filename is missing

## Git-aware narrowing

Use git only as a narrowing mechanism.

Cheap git signals:
- `git status --short`
- `git diff --name-only`
- modified folders
- obvious branch context

Avoid:
- large raw diffs
- full patch inspection unless the scope is already very narrow

## Candidate note selection

Find candidate notes using the cheapest possible signals first.

Cheap signals:
- exact filename match
- exact note title match
- shared tags
- folder relevance
- explicit component or module names
- existing Obsidian links
- Graphify community or component names

Candidate priority:
1. exact scoped note
2. project note
3. architecture note
4. task note
5. decision note
6. knowledge note

Read only the smallest useful set.

## What to sync

Sync only what is clearly supported by current implementation context.

Possible sync outcomes:
- implementation status advanced
- component now exists or is connected
- integration now exists
- task item completed
- task item still pending
- blocker remains or is removed
- architecture flow needs update
- project note needs progress or status update
- decision note needs implementation confirmation
- knowledge note needs a concrete implementation example
- session note should capture a real milestone

Do not invent:
- completion
- blockers
- design intent
- decisions never recorded
- roadmap items without evidence

## Preferred update targets by situation

### If implementation changed
Prefer updating:
- `brain/arquitetura`
- `brain/projetos`
- `brain/tarefas`

### If implementation confirms a prior decision
Prefer updating:
- `brain/decisoes`
- `brain/arquitetura`

### If implementation adds reusable understanding
Prefer updating:
- `brain/conhecimento`

### If the main change is execution status
Prefer updating:
- `brain/tarefas`
- `brain/projetos`

## Section-level update policy

Prefer updating existing sections instead of reshaping the whole note.

### Project notes
Update only relevant sections such as:
- `## Context`
- `## Status`
- `## Scope`
- `## Progress`
- `## Next step`
- `## Related`

### Architecture notes
Update only relevant sections such as:
- `## Overview`
- `## Components`
- `## Data flow`
- `## Integrations`
- `## Technologies`
- `## Risks`
- `## Related`

### Decision notes
Update only relevant sections such as:
- `## Context`
- `## Decision`
- `## Reason`
- `## Impact`
- `## Related`

### Task notes
Update only relevant sections such as:
- `## Status`
- `## Completed`
- `## Pending`
- `## Blockers`
- `## Next step`
- checkbox lists

### Knowledge notes
Update only relevant sections such as:
- `## Description`
- `## Details`
- `## Example`
- `## Related`

Do not rewrite unaffected sections.

## Implementation delta rule

Only record deltas that are now true because of the current implementation state.

Good examples:
- component implemented
- integration wired
- pending item narrowed
- task item completed
- architecture flow updated
- note now matches coded behavior

Bad examples:
- project progressed
- system improved
- things were implemented

Be concrete and short.

## Context logging rule

When a section is updated, add one short factual update-context line in that same section if useful.

Examples:
- `Update context: LoRa routing was implemented in the gateway module.`
- `Update context: MQTT publishing remains pending because credentials are missing.`
- `Update context: Battery telemetry is now persisted through the ingestion path.`

Keep these lines short and factual.

## Note creation policy

Prefer updating existing notes.

Create a new note only if all are true:
- the concept is clearly implemented or clearly relevant now
- no existing note covers it adequately
- it belongs naturally in one allowed brain folder
- the new note will reduce future scanning and duplication

If creating a note:
- use a short clear filename
- add `#ruraltech`
- add the folder tag
- add at least one `[[related note]]`

## Token optimization rules

Minimize token usage aggressively.

### Core principles

- use Graphify first
- use git only to narrow scope
- avoid raw repository scanning
- prefer filenames, titles, tags, headings, and summaries before body reads
- read only candidate notes, not whole folders
- stop as soon as enough high-confidence evidence is found
- update only notes that truly changed
- run `brain-links` only on changed notes

### Two-phase sync

#### Phase 1: cheap signals only
Use only:
- Graphify summaries
- git changed filenames
- note filenames
- note titles
- tags
- folder relevance
- existing links

If Phase 1 is enough to identify the impacted notes and delta, do not run Phase 2.

#### Phase 2: expensive reads only if needed
Use only:
- full candidate note bodies
- minimal implementation file reads

Run Phase 2 only when Phase 1 is insufficient.

### Read budget

Default maximum read budget:
- up to 2 Graphify artifacts
- up to 5 candidate notes
- up to 4 raw implementation files

Do not exceed this unless the user gave an explicit narrow scope that requires more.

### Hard limits

- never read the whole `brain/`
- never scan the whole repository unless the user explicitly requested repo-wide sync
- never read more than the smallest useful candidate set
- avoid large raw diffs
- do not reopen the same note repeatedly unless validation requires it
- do not create a session note unless there is a clear milestone
- do not use `brain-links` on unchanged notes

### Early stop rule

Stop as soon as all are true:
- impacted notes are identified
- implementation delta is clear
- notes are updated accurately
- link refresh has been applied or queued for changed notes
- no additional high-confidence impacted note remains

### Skip-if-no-delta

- if there is no implementation delta, do not rewrite the note
- if the note is already accurate, skip it
- if remaining candidates are low-confidence, stop

### Editing minimization

- do one clean edit pass per note
- preserve note structure
- update only changed sections
- do not reformat the whole note
- do not normalize unrelated text
- keep updates short and factual

### Output minimization

At the end, print only:
- resolved scope
- Graphify artifacts used
- notes updated
- notes created
- notes skipped
- link refresh status
- short factual summary

Do not print long reasoning or large excerpts.

## Safety and ambiguity rules

- never mark work as completed unless implementation evidence clearly supports it
- if evidence is ambiguous, make the smallest safe update
- if two notes are plausible but only one has strong support, update only that one
- if a note is already accurate, do not touch it
- do not create duplicate notes
- do not infer a decision from implementation alone unless the note already frames it that way
- do not delete content unless it is clearly obsolete and replaced by more accurate current content in the same note

## brain-links chaining

After saving each changed note:

1. invoke `brain-links` on that note path
2. use it only to refresh or add relevant inline links
3. do not let link refresh drive content changes
4. if `brain-links` cannot run programmatically in this environment, report the exact manual command for that note

## Final output format

Print only this structure:

# Brain Sync

## Scope
<resolved scope>

## Graphify used
- artifact
- artifact

## Notes updated
- path
- path

## Notes created
- path
- path

## Notes skipped
- path — short reason

## Link refresh
- path — success
- path — manual: /brain-links <path>

## Summary
Short factual summary of the synchronized implementation progress