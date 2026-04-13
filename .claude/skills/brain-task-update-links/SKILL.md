---
name: brain-task-update-links
description: Update one task note with completed, pending, blocked, and next-step changes, then run brain-links on the updated note.
argument-hint: "[task-note-path] | [optional-update-context]"
disable-model-invocation: true
---
Update a task note using the current conversation context plus any explicit update context passed in the arguments.

Arguments:
$ARGUMENTS

Accepted input formats:

- `brain/tarefas/my-task.md`
- `/absolute/path/to/brain/tarefas/my-task.md`
- `tarefas/my-task.md`
- `brain/tarefas/my-task.md | finished X, pending Y, blocked by Z`
- `/absolute/path/to/file.md | what changed in this task`

## Goal

- update an existing task note accurately
- reflect what was completed
- reflect what is still pending
- reflect blockers if any
- preserve the note structure when possible
- update only the relevant sections
- record the context of the update in the section that was changed
- avoid unnecessary rewrites
- after saving, run `brain-links` for the same note so links are refreshed

## Scope

This skill is for task notes.

Preferred target location:

- `brain/tarefas/*`

If the target file is outside `brain/tarefas/`, continue only if the note is clearly a task-oriented note.
Otherwise stop and explain that the file does not look like a task note.

## Source of truth priority

Use this order:

1. the target task note
2. the explicit update context passed after `|`
3. the current conversation/session context
4. do not scan the whole brain unless absolutely necessary

## Path resolution

1. If `$ARGUMENTS` contains `|`, split into:
   - left side = target path
   - right side = explicit update context
2. If the left side is an absolute path and exists, use it.
3. If it starts with `brain/` and exists, use it.
4. If it exists relative to the repository root, use it.
5. If it exists relative to `brain/`, use it.
6. If the path cannot be resolved, stop and explain which path could not be found.

## Update behavior

Read the target note and determine how it is structured.

Prefer updating existing sections instead of reshaping the whole file.

Typical task-related sections may include:

- `## Context`
- `## Status`
- `## Action`
- `## Done`
- `## Completed`
- `## Pending`
- `## Open items`
- `## Blockers`
- `## Next step`
- `## Related`
- checkbox lists like `- [ ]` and `- [x]`

### What to update

Update only what is justified by the note content and the current context.

Possible updates:

- mark matching unchecked items as completed when clearly done
- keep incomplete items as pending
- move finished items from pending/open lists to done/completed lists when that structure exists
- create or update a blockers section when a blocker is clearly mentioned
- create or update a next-step section when the next action is clear
- update a short status summary if the note has one
- add a brief contextual update note in the relevant modified section

### Context logging rule

Whenever you change a section, include a short update line in that same section explaining what changed.

Examples:

- in a completed section:
  - `Update context: gateway validation finished during firmware review.`
- in a pending section:
  - `Update context: battery test still pending because field data is missing.`
- in a blockers section:
  - `Update context: deployment blocked by missing MQTT credentials.`

Keep these update-context lines short and useful.

### If the note has checkbox items

- check items that are clearly completed
- leave unclear items unchanged
- do not guess completion
- do not duplicate checkbox items into multiple sections unless the note structure already expects that

### If the note has no useful task structure

Create only the minimum needed sections:

- `## Status`
- `## Completed`
- `## Pending`
- `## Blockers`
- `## Next step`

Do not create extra sections unless needed.

## Editing policy

- preserve the existing note structure when possible
- modify only the relevant lines and sections
- do not rewrite unrelated sections
- do not normalize style unless necessary for clarity
- prefer one clean edit pass
- keep markdown simple
- preserve existing tags and links
- do not remove valid existing Obsidian links

## Token optimization rules

Minimize token usage aggressively.

### Core principles

- read only the target task note first
- use explicit update context if provided
- use current session context only as needed
- avoid broad vault scanning
- prefer section-level edits over full note rewrites
- stop once the task note is correctly updated
- run `brain-links` only once after the note is saved

### Hard limits

- do not read the whole `brain/`
- do not inspect unrelated folders
- do not re-open the same note repeatedly unless required for validation
- do not search for every possible related note here; leave that work to `brain-links`
- do not generate long reasoning in the output

### Early stop rule

- if the note has been updated correctly and clearly reflects completed, pending, blockers, and next step status, stop
- if the context is ambiguous, make the smallest safe update and stop
- do not over-edit the note

## Safety and ambiguity rules

- never mark an item as completed unless the context clearly supports it
- if the context is ambiguous, keep the item pending
- if the user-provided update context conflicts with the note, prefer the explicit current user context
- do not invent blockers, completions, or next steps
- do not create duplicate items
- do not delete information unless it is clearly obsolete and replaced by a more current equivalent in the same note

## brain-links chaining

After saving the updated note:

1. invoke `brain-links` on the same resolved note path
2. use `brain-links` only to refresh or add inline links related to the updated content
3. do not let `brain-links` rewrite the task logic
4. if `brain-links` is unavailable for programmatic invocation in this environment, report that the task note was updated and that `/brain-links <resolved-path>` should be run manually

## Final output

After execution, print only:

- resolved path
- sections updated
- completed items changed
- pending items changed
- blockers changed
- next-step changed
- whether `brain-links` ran successfully
- if not, print the exact manual command to run
