---
name: brain-save
description: Save or update brain knowledge with minimal scanning, strict candidate budgets, and incremental edits.
argument-hint: "[topic or note path]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Write
  - Edit
  - MultiEdit
  - Bash(find:*)
  - Bash(ls:*)
---

Save or update knowledge in `/brain` with aggressive token optimization.

Argument:
$ARGUMENTS

## Goal

- save or update knowledge in the correct brain folder
- reuse existing notes whenever possible
- avoid duplicates
- update incrementally instead of rewriting
- minimize token usage
- refresh links after saving using `brain-links`

## Destination folders

Decide destination by content type:

- architecture or system design → `brain/arquitetura`
- decision or tradeoff → `brain/decisoes`
- project context or scope → `brain/projetos`
- reusable concept or reference → `brain/conhecimento`
- actionable work item → `brain/tarefas`
- raw capture or unclear content → `brain/inbox`
- session checkpoint → `brain/sessoes`

## Rules

- never duplicate notes
- prefer updating an existing note
- use simple markdown
- use `[[obsidian links]]`
- use short and clear filenames
- create one concept per file
- preserve useful context from the current session
- ignore notes tagged with `plugin`
- prefer notes tagged with `ruraltech`

## Token optimization rules

### Core principles

- decide the likely destination folder before broad search
- use cheap signals first
- search only within the most likely folders
- read only a small candidate set
- stop when a strong existing note match is found
- do not rewrite a note if there is no real delta

### Cheap signals first

Use this order:
1. exact filename match
2. exact title match
3. shared tags
4. folder relevance
5. existing links
6. only then note body similarity

### Read budget

Default maximum:
- search in up to 2 likely folders
- read up to 3 candidate notes in full
- stop early if one strong match is found

### Early stop rule

Stop searching when:
- one exact or strong match exists
- destination folder is clear
- no competing note has similar confidence

### Editing minimization

- update only impacted sections
- do not reformat the whole note
- do not rewrite unrelated sections
- keep additions factual and short

## Workflow

1. Infer the most likely destination folder from content
2. Search only the most likely destination folder and one fallback folder if needed
3. Check for strong existing note matches
4. Update the existing note if a strong match exists
5. Create a new note only if needed
6. Add minimal related links
7. Run `brain-links` on the saved note if available

## Template for new notes

# Title

#ruraltech
#folder-name

## Context

## Description

## Details

## Related

[[related note]]

## brain-links chaining

After saving:
1. invoke `brain-links` on the saved note path
2. if not available programmatically, report the manual command

## Final output

Print only:
- saved path
- created or updated
- destination folder
- whether `brain-links` ran successfully
- manual command if needed