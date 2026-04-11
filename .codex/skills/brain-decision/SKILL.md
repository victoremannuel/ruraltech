---
name: brain-decision
description: Register a technical or product decision in the second brain.
disable-model-invocation: true
allowed-tools: Bash(find *) Bash(ls *) Read Write Edit MultiEdit
---

Register a decision in `brain/decisoes`.

Decision title:
$ARGUMENTS

Rules:
- do not duplicate an existing decision
- update the existing decision if it already exists
- use a concise and auditable format
- add links to architecture and project notes when relevant

Template:

# Decision: $ARGUMENTS

Date: YYYY-MM-DD

## Context

## Options considered

## Decision

## Reason

## Impact

## Related

[[related note]]

At the end:
- print the file path
- summarize the decision in 3 lines