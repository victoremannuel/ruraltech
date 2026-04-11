---
name: brain-save
description: Save or update knowledge in the Obsidian second brain
allowed-tools: Read,Write,Edit,MultiEdit,Bash(find:*),Bash(ls:*)
---

Save or update knowledge in `/brain`.

Topic:
$ARGUMENTS

Decide the destination folder by content type:

- architecture or system design → `brain/arquitetura`
- decision or tradeoff → `brain/decisoes`
- project context or scope → `brain/projetos`
- reusable concept or reference → `brain/conhecimento`
- actionable work item → `brain/tarefas`
- raw capture or unclear content → `brain/inbox`
- session checkpoint → `brain/sessoes`

Rules:
- never duplicate notes
- prefer updating an existing note
- use simple markdown
- use `[[obsidian links]]`
- use short and clear filenames
- create one concept per file
- connect the note to existing knowledge when possible

Workflow:
1. Search `/brain` for related notes.
2. Reuse and update existing notes when possible.
3. Create a new note only when necessary.
4. Add related links.
5. Preserve useful context from the current session.

Template:

# Title

## Context

## Description

## Details

## Related

[[related note]]

At the end, print:
- saved path
- created or updated
- destination folder chosen