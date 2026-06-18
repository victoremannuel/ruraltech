---
name: brain-task
description: Register or update a task note with minimal reading, exact-match reuse, and section-level edits.
argument-hint: "[task title or task note path]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - MultiEdit
  - Bash(find:*)
  - Bash(ls:*)
---

Register or update a task in `brain/tarefas` with minimal token usage.

Argument:
$ARGUMENTS

## Goal

- create or update a task note
- avoid duplicate task notes
- prefer updating existing tasks
- keep task notes actionable
- refresh links after saving using `brain-links`

## Rules

- prefer updating an existing task note if it is the same task
- write actionable items
- include status when possible
- link to project and architecture notes only when clearly relevant
- ignore notes tagged with `plugin`
- prefer notes tagged with `ruraltech`

## Token optimization rules

### Core principles

- search only inside `brain/tarefas` first
- use filename, title, and tags before body similarity
- read only a very small candidate set
- stop as soon as a strong existing task match is found
- use section-level edits instead of full rewrites

### Cheap signals first

Rank candidates by:
1. exact filename match
2. exact task title match
3. shared tags
4. similar next-step wording
5. only then body similarity

### Read budget

Default maximum:
- read up to 3 candidate task notes in full
- read no other folders unless task context clearly requires it

### Early stop rule

Stop when:
- a strong matching task note is found
- task status can be updated safely
- no additional task note is likely to be the same task

### Editing minimization

- update only:
  - `## Context`
  - `## Action`
  - `## Status`
  - `## Next step`
  - `## Related`
- do not rewrite the entire note
- keep updates short and factual

## Template for new tasks

# Task: $ARGUMENTS

#ruraltech
#tarefas

## Context

## Action

## Status

## Next step

## Related

[[related note]]

## brain-links chaining

After saving:
1. invoke `brain-links` on the saved task note
2. if unavailable programmatically, report the manual command

## Final output

Print only:
- file path
- created or updated
- task status
- whether `brain-links` ran successfully
- manual command if needed