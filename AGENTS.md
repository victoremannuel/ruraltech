# Codex Agent Configuration

This project uses:

- Obsidian second brain in /brain
- Graphify knowledge graph
- Shared skills with Claude
- Persistent architecture memory

---

## graphify

Graph location:

graphify-out/GRAPH_REPORT.md

Rules:

- Always prefer graphify over raw file scanning
- Read GRAPH_REPORT.md before answering architecture/code questions
- If graphify-out/wiki/index.md exists, use it instead of scanning files
- Avoid scanning the repository if graphify is available
- If graph is outdated or missing, rebuild automatically

---

## brain

All knowledge is stored in /brain

Folders:

brain/inbox → raw ideas
brain/projetos → active projects
brain/arquitetura → technical architecture
brain/decisoes → decisions
brain/tarefas → tasks
brain/conhecimento → reusable knowledge
brain/sessoes → session checkpoints

Rules:

- never duplicate notes
- always update existing notes
- create one concept per file
- use [[obsidian links]]
- keep markdown simple
- connect related notes
- prefer updating over creating
- Whenever an implementation plan is requested, it must be recorded as a task in the “tasks” folder, and this note should be used for planning and as an implementation checklist. At the end of the implementation, completed items must be checked off, and the history and pending items summarized.
- tudo que vc fizer deve ser relatado no brain

### tagging rules

- every note MUST include:
  - #ruraltech
  - #folder-name (matching folder)

Examples:

- note in arquitetura → #arquitetura
- note in decisoes → #decisoes

### filtering rules

- ignore notes with tag `plugin`
- ONLY consider notes with tag `ruraltech`

---

## brain skills

Available commands:

/brain
Load second brain context

/brain-save "topic"
Create or update knowledge

/brain-decision "title"
Register decision

/brain-architecture "component"
Document architecture

/brain-task "task"
Register task

/brain-daily
Save session checkpoint

Rules:

- always prefer using /brain-* skills
- never create notes manually without skill
- always check existing notes before creating new ones
- always apply required tags
- always link related notes
- always store inside /brain

---

## when to write to brain

Write to brain when:

- architecture is defined
- a decision is made
- new concept is created
- knowledge is discovered
- system components are defined
- project structure is explained
- user asks to document/save/register/log/create note
- session is ending

Prefer:

/brain-save
/brain-decision
/brain-architecture
/brain-task
/brain-daily

---

## note format

# Title

#ruraltech
#folder-name

## Context

## Description

## Details

## Related

[[related note]]

---

## architecture format

# Architecture: Name

#ruraltech
#arquitetura

## Overview

## Components

## Flow

## Technologies

## Related

---

## decision format

# Decision: Name

#ruraltech
#decisoes

Date:

## Context

## Options

## Decision

## Reason

## Impact

## Related

---

## task format

# Task: Name

#ruraltech
#tarefas

## Context

## Action

## Status

## Next step

## Related

---

## session format

# Session YYYY-MM-DD

#ruraltech
#sessoes

## What was done

## Decisions made

## Architecture updates

## Open tasks

## Next step

---

## behavior rules

- always load /brain before starting work
- always prefer brain over raw repo scanning
- always prefer graphify over grep/search
- minimize token usage by using structured knowledge
- avoid redundant reads
- build context before answering

## Imported Claude Cowork project instructions
