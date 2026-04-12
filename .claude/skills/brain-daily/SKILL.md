---
name: brain-daily
description: Save a compact session checkpoint using only current-session deltas and changed notes.
disable-model-invocation: true
allowed-tools:
  - Bash(date:*)
  - Bash(find:*)
  - Bash(ls:*)
  - Bash(git status:*)
  - Bash(git diff:*)
  - Read
  - Write
  - Edit
  - MultiEdit
---

Create or update a compact session checkpoint in `brain/sessoes` with minimal token usage.

## Goal

- summarize the current session
- capture only the session deltas that matter
- avoid broad re-reading of the brain
- preserve enough context for the next session
- refresh links after saving using `brain-links`

## Purpose

Capture only:
- what was done in this session
- decisions made in this session
- architecture updates from this session
- open tasks still relevant after this session
- next recommended action

## Token optimization rules

### Core principles

- use the current session as the primary source
- use changed notes and cheap git signals only as support
- do not rescan broad brain history
- do not summarize unrelated prior work
- keep the checkpoint compact and factual

### Cheap signals first

Use:
- current conversation/session context
- changed filenames from git if helpful
- notes created or updated in this session
- explicit outputs already produced in this session

### Read budget

Default maximum:
- read up to 4 changed notes from this session
- avoid opening old session notes unless updating today’s checkpoint

### Early stop rule

Stop when:
- today’s main deltas are clear
- decisions and open tasks are captured
- next recommended action is clear

### Editing minimization

- update only today’s session note if it already exists
- do not rewrite older session notes
- keep the checkpoint concise

## Template

# Session YYYY-MM-DD

#ruraltech
#sessoes

## What was done

## Decisions made

## Architecture updates

## Open tasks

## Next recommended action

## brain-links chaining

After saving:
1. invoke `brain-links` on today’s session note
2. if unavailable programmatically, report the manual command

## Final output

Print only:
- file path
- created or updated
- notes used from this session
- whether `brain-links` ran successfully
- manual command if needed