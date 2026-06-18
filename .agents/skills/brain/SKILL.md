---
name: brain
description: Load second-brain context with Graphify first, hotspot-first narrowing, and strict read budgets.
argument-hint: "[optional-scope]"
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(find:*)
  - Bash(ls:*)
  - Bash(cat:*)
  - Bash(test:*)
  - Bash(pwd)
  - Bash(git status:*)
  - Bash(git diff:*)
  - Bash(graphify:*)
---

Initialize second brain context with minimal token usage.

Argument:
$ARGUMENTS

Scope is optional:
- empty → load only the most relevant current project context
- file path
- folder path
- module name
- note path
- topic name

## Goal

- load Graphify knowledge first
- load only the most relevant Obsidian brain knowledge
- avoid raw repository scanning
- build a compact working context
- prepare Codex for the current work with minimal token cost

## Brain path

brain/

Relevant folders:
- brain/projetos
- brain/arquitetura
- brain/decisoes
- brain/conhecimento
- brain/tarefas
- brain/inbox

Ignore:
- notes tagged with `plugin`
- notes not related to `ruraltech` when tags are present

## Source priority

Always use this order:
1. Graphify artifacts
2. explicit scope argument
3. cheap git signals
4. existing relevant notes
5. raw file reading only if absolutely needed

## Token optimization rules

Minimize token usage aggressively.

### Core principles

- use Graphify before reading notes
- prefer hotspot-first loading
- prefer cheap signals before semantic reading
- avoid reading entire folders
- stop once enough context is loaded
- do not load broad historical context unless required

### Two-phase loading

#### Phase 1: cheap signals only
Use only:
- Graphify summaries
- note filenames
- note titles
- tags
- folder relevance
- git changed filenames if needed

If Phase 1 is sufficient, do not run Phase 2.

#### Phase 2: expensive reads only if needed
Use only:
- full note bodies for the top relevant notes
- minimal raw implementation file reads

Run Phase 2 only when Phase 1 is insufficient.

### Read budget

Default maximum:
- up to 2 Graphify artifacts
- up to 4 full note reads
- up to 2 raw implementation file reads

Do not exceed this unless scope is explicit and narrow.

### Hotspot-first strategy

If no explicit scope is provided:
1. inspect Graphify summaries
2. inspect cheap git signals if available
3. identify the top 5 likely impacted areas
4. load only the top 3 unless more are clearly needed

### Early stop rule

Stop as soon as all are true:
- project type is clear
- main components are clear
- relevant architecture is clear
- active tasks or decisions are clear
- no additional high-confidence note is needed

## Scope resolution

1. If `$ARGUMENTS` is empty:
   - infer scope from Graphify and cheap git signals
2. If `$ARGUMENTS` resolves to a file/folder path:
   - use it as the scope anchor
3. If `$ARGUMENTS` resolves to a brain note path:
   - use that note as the scope anchor
4. If `$ARGUMENTS` is a topic/module name:
   - resolve using Graphify names, note filenames, titles, tags, and existing links
5. If scope is ambiguous:
   - stop and explain the ambiguity

## Graphify-first policy

1. Check whether `graphify-out/` exists
2. If Graphify is missing or clearly outdated, run:
   - `graphify .`
3. Inspect available artifacts in `graphify-out/`
4. Prefer this order:
   - `graphify-out/GRAPH_REPORT.md`
   - `graphify-out/wiki/index.md`
   - other summary-level artifacts

If expected filenames do not exist:
- inspect the available artifacts
- use the smallest useful summary artifacts
- do not fail only because a specific filename is missing

## Candidate note selection

Rank candidate notes using cheap signals:
1. exact filename match
2. exact title match
3. shared tags
4. folder relevance
5. Graphify component/community name match
6. existing links

Loading priority:
1. projetos
2. arquitetura
3. decisoes
4. tarefas
5. conhecimento

Read only the smallest useful set.

## Context building

After loading, determine:
- project type
- main components
- architecture
- active tasks
- key decisions
- reusable knowledge currently relevant

## Output format

Print only this structure:

# Brain Loaded

## Scope
<resolved scope>

## Graphify used
- artifact
- artifact

## Project
Short project description

## Main Components
- component
- component

## Architecture
Short detected architecture summary

## Decisions
- decision
- decision

## Active Tasks
- task
- task

## Knowledge Loaded
- note
- note

## Ready
Second brain initialized
Working context loaded
Ready to assist