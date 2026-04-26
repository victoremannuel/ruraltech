# Instructions

## skill /design

**Quando usar esta skill:** sempre que for solicitado criar, alterar, refatorar ou revisar QUALQUER tela, componente, widget ou elemento visual do app RuralTech (`app/lib/`). Esta skill é a fonte de verdade para o redesign v2.

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:

- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md
- Prefer graphify-out/wiki/ over raw file scanning
- Use graphify knowledge before reading multiple files
- After modifying code, rebuild graph if needed

If graphify exists:

- Use graphify knowledge first
- If graph is outdated, rebuild automatically
- Prefer graphify over raw scanning

---

## brain

This repository uses Obsidian as a second brain.

All knowledge must be written inside /brain

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
- whenever a note is created, it must have a tag (#folder-name) corresponding to the folder the note is in.
- ignore notes that have the tag `plugin`
- consider ONLY notes that have the `ruraltech` tag.
- every note created about the ruraltech solution MUST have the `ruraltech` tag.
- Whenever an implementation plan is requested, it must be recorded as a task in the “tasks” folder, and this note should be used for planning and as an implementation checklist. At the end of the implementation, completed items must be checked off, and the history and pending items summarized.
- tudo que vc fizer deve ser relatado no brain

---

## brain skills

The following commands are available:

/brain
Load second brain context using graphify + obsidian notes

/brain-save "topic"
Create or update knowledge in the second brain

/brain-decision "title"
Register a technical or product decision

/brain-architecture "component"
Document system architecture

/brain-task "task"
Register actionable task

/brain-daily
Save session checkpoint

Rules:

- Prefer using /brain-* skills instead of manual note creation
- Always check existing notes before creating new ones
- Always apply required tags
- Always link related notes
- Always store notes inside /brain

---

## when to write to brain

Write to brain when:

- architecture is defined
- a decision is made
- new concept is created
- knowledge is discovered
- project structure is explained
- system components are defined
- user asks to "document"
- user asks to "save"
- user asks to "remember"
- user asks to "register"
- user asks to "create note"
- user asks to "log"
- session is ending

Prefer using:

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
