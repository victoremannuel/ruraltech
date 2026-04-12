---
name: brain-architecture
description: Document architecture using Graphify first, narrow scope, and update only the affected sections.
argument-hint: "[component, module, path, or architecture note]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - MultiEdit
  - Bash(find:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(test:*)
  - Bash(graphify:*)
---

Document or update architecture in `brain/arquitetura` with minimal token usage.

Argument:
$ARGUMENTS

## Goal

- document a system, component, or flow
- use Graphify before raw file inspection
- update existing architecture notes whenever possible
- keep architecture notes concrete and reusable
- refresh links after saving using `brain-links`

## Rules

- prefer updating an existing architecture note
- use concrete technical language
- link to related decisions and project notes only when clearly relevant
- keep it reusable
- ignore notes tagged with `plugin`
- prefer notes tagged with `ruraltech`

## Token optimization rules

### Core principles

- use Graphify first
- resolve scope before reading raw files
- prefer note filename/title/tag matches before note body reading
- read only the smallest useful candidate set
- update sections incrementally
- avoid broad repository scanning

### Two-phase approach

#### Phase 1: cheap signals only
Use:
- Graphify summaries
- note filenames
- note titles
- tags
- folder relevance

If Phase 1 is sufficient, do not run Phase 2.

#### Phase 2: expensive reads only if needed
Use:
- up to 3 candidate architecture note bodies
- up to 3 raw implementation files

### Read budget

Default maximum:
- up to 2 Graphify artifacts
- up to 3 architecture notes
- up to 3 implementation files

### Early stop rule

Stop when:
- component or flow scope is clear
- the impacted architecture note is identified
- the architecture delta is clear
- no additional note has high-confidence relevance

### Editing minimization

Update only relevant sections:
- `## Overview`
- `## Components`
- `## Data flow`
- `## Integrations`
- `## Technologies`
- `## Risks`
- `## Related`

Do not rewrite unaffected sections.

## Workflow

1. Check `graphify-out/`
2. Run `graphify .` only if needed
3. Read the smallest useful Graphify summary artifacts
4. Resolve architecture scope
5. Search for candidate notes in `brain/arquitetura`
6. Update the existing architecture note if possible
7. Create a new architecture note only if no adequate note exists
8. Run `brain-links` on the saved note

## Template for new architecture notes

# Architecture: $ARGUMENTS

#ruraltech
#arquitetura

## Overview

## Components

## Data flow

## Integrations

## Technologies

## Risks

## Related

[[related note]]

## Final output

Print only:
- file path
- created or updated
- Graphify artifacts used
- related notes added
- whether `brain-links` ran successfully
- manual command if needed