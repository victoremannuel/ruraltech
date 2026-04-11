---
name: brain-task
description: Register an actionable task in the second brain.
disable-model-invocation: true
allowed-tools: Bash(find *) Bash(ls *) Read Write Edit MultiEdit
---

Register a task in `brain/tarefas`.

Task:
$ARGUMENTS

Rules:
- prefer updating an existing task note if it is the same task
- write actionable items
- include status when possible
- link to project and architecture notes if relevant

Template:

# Task: $ARGUMENTS

## Context

## Action

## Status

## Next step

## Related

[[related note]]

At the end:
- print the file path
- show the task status