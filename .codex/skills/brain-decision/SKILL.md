---
name: brain-decision
description: Register or update a decision note using exact-match reuse, minimal reading, and incremental edits.
argument-hint: "[decision title or decision note path]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - MultiEdit
  - Bash(find:*)
  - Bash(ls:*)
---

Register or update a decision in `brain/decisoes` with minimal token usage.

Argument:
$ARGUMENTS

## Goal

- register a technical or product decision
- avoid duplicate decision notes
- update existing decision notes when they already cover the same decision
- keep decisions concise and auditable
- refresh links after saving using `brain-links`

## Rules

- do not duplicate an existing decision
- update the existing decision if it already exists
- use a concise and auditable format
- add links to architecture and project notes only when clearly relevant
- ignore notes tagged with `plugin`
- prefer notes tagged with `ruraltech`

## Token optimization rules

### Core principles

- search only inside `brain/decisoes` first
- use exact title, filename, and tags before semantic reading
- read only a small candidate set
- stop early when a strong decision match is found
- edit only impacted sections

### Cheap signals first

Rank candidates by:
1. exact filename match
2. exact decision title match
3. shared tags
4. related architecture/project note references
5. only then body similarity

### Read budget

Default maximum:
- read up to 3 candidate decision notes in full
- read no other note folders unless clearly necessary

### Early stop rule

Stop when:
- a strong existing decision note match is found
- the decision delta is clear
- no competing candidate has similar confidence

### Editing minimization

Update only relevant sections:
- `## Context`
- `## Options considered`
- `## Decision`
- `## Reason`
- `## Impact`
- `## Related`

Do not rewrite the entire note.

## Template for new decision notes

# Decision: $ARGUMENTS

#ruraltech
#decisoes

Date: YYYY-MM-DD

## Context

## Options considered

## Decision

## Reason

## Impact

## Related

[[related note]]

## brain-links chaining

After saving:
1. invoke `brain-links` on the saved decision note
2. if unavailable programmatically, report the manual command

## Final output

Print only:
- file path
- created or updated
- short decision summary
- whether `brain-links` ran successfully
- manual command if needed