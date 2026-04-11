---
name: brain-daily
description: Save a session checkpoint into the second brain.
disable-model-invocation: true
allowed-tools: Bash(date *) Bash(find *) Bash(ls *) Read Write Edit MultiEdit
---

Create or update a session checkpoint in `brain/sessoes`.

Purpose:
- summarize the current session
- capture decisions
- capture architecture updates
- capture open tasks
- preserve context for the next session

Use today's date from the system.

Template:

# Session YYYY-MM-DD

## What was done

## Decisions made

## Architecture updates

## Open tasks

## Next recommended action

Also:
- add links to any notes created or updated in this session

At the end:
- print the file path
- print a 5-line summary