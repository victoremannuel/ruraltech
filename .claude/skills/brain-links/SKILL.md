---
name: brain-links
description: Add inline Obsidian links to one brain note using existing notes, tags, and high-confidence matches only.
argument-hint: "[note-path]"
disable-model-invocation: false
---
Read a note from the Obsidian brain, detect concepts/entities mentioned in the content, use existing tags as semantic anchors, find matching related notes inside the allowed brain folders, insert inline Obsidian links on the same line where the content is mentioned, and save the note.

Argument:
$ARGUMENTS

The argument can be:

- a relative path inside `brain/`
- an absolute path to a note file
- a path relative to the repository root

## Goal

- enrich an existing note with inline Obsidian links
- use both content and tags as signals
- only create links to notes inside the allowed brain folders
- insert the link immediately after the cited concept on the same line
- avoid duplicate links
- preserve readability

## Allowed folders inside `brain/`

- `/tarefas/*`
- `/sessoes/*`
- `/projetos/*`
- `/ideias/*`
- `/devisoes/*`
- `/decisoes/*`
- `/contexto/*`
- `/conhecimento/*`
- `/arquitetura/*`

## Rules

- only link notes that already exist
- only link using notes from the allowed folders above
- never create new notes in this skill
- never link to notes outside `brain/`
- never add the same link twice on the same line
- do not replace existing valid Obsidian links
- preserve the original text as much as possible
- prefer the most specific matching note
- if multiple candidate notes are ambiguous, choose the strongest semantic match only
- do not force links for weak matches
- ignore notes tagged with `plugin`
- prefer notes tagged with `ruraltech`
- keep markdown simple
- prefer short, deterministic matching passes over broad exploratory reading

## Tag-aware linking

Tags must be used as a primary semantic signal.

### Rules for tags

- detect tags (`#tag`) in the current note
- detect tags in candidate notes
- prioritize linking notes that share tags
- use tags to disambiguate similar concepts

### Tag usage behavior

- if a concept matches a tag, prefer notes with the same tag
- if multiple notes match the concept, prefer the one sharing the same tag
- if the current note has tags, prioritize linking notes that share at least one tag
- if no tag match exists, fallback to content-based matching

### Important

- do not create new tags
- do not modify existing tags
- do not link based only on tags without semantic relevance
- tags are a boost signal, not the only signal

## Token optimization rules

Minimize token usage aggressively.

### Core principles

- prefer structured signals before semantic reading
- prefer filename, title, heading, and tag matches before reading full note bodies
- prefer Graphify artifacts if available over broad raw scanning
- avoid reading unrelated notes
- stop early when confidence is high
- do not load large note bodies unless necessary
- do not scan the whole vault if strong candidates are found early

### Search strategy

Use this order:

1. resolve the target note path
2. read only the target note first
3. extract:
   - tags
   - title
   - headings
   - repeated concepts
   - explicit component names
4. search candidate notes by cheap signals first:
   - filename
   - note title
   - first heading
   - tags
5. only if needed, read candidate note bodies for top matches
6. stop once enough strong matches are found

### Hard limits

- never read every note in `brain/`
- inspect only allowed folders
- cap candidate discovery to the smallest useful set
- read at most the top 8 candidate notes in full
- prefer reading only the beginning of candidate notes first
- only expand to deeper reading for ambiguous cases
- stop linking after the useful links for the note are found
- do not chase weak semantic matches

### Candidate ranking priority

Rank matches in this order:

1. exact filename match
2. exact title match
3. shared tags
4. exact heading match
5. strong semantic match

If rank 1, 2, or 3 produces a strong result, do not continue broad searching.

- when a high-confidence match is found by filename, exact title, or shared tag, prefer it immediately and avoid broader semantic search

### Early stop rule

- if 3 to 5 high-confidence links are already found, stop searching for more unless the note is clearly underlinked
- if a concept already has one strong linked target, do not keep searching alternatives for the same concept
- if the remaining unmatched concepts are generic or low-confidence, stop the process

### Tag-first optimization

- use tags as a low-cost filter before semantic matching
- prioritize notes sharing the same tags as the target note
- if no relevant shared tags exist, fallback to content matching
- never read notes with unrelated tags when stronger tagged candidates already exist

### Reading minimization

- read the full body of a candidate note only when cheap signals are insufficient
- prefer summary-level inspection:
  - filename
  - title
  - top heading
  - tags
  - first relevant section
- avoid reading long historical/session notes unless the target note explicitly references them

### Editing minimization

- batch edits in one pass
- only modify lines where a high-confidence link is being inserted
- do not rewrite unaffected sections
- do not normalize formatting unless necessary for the link insertion

### Re-run avoidance

- if the target line already contains a valid link for the concept, skip it
- if the note already has enough useful links, avoid adding marginal links
- do not re-evaluate the same concept repeatedly after a strong match is already used

### Output minimization

At the end, output only:

- resolved path
- number of links added
- linked notes
- skipped ambiguous concepts

Do not print long reasoning or large excerpts from notes.

## Path resolution

1. If `$ARGUMENTS` is an absolute path and exists, use it.
2. If `$ARGUMENTS` starts with `brain/` and exists, use it.
3. If `$ARGUMENTS` exists relative to the repository root, use it.
4. If `$ARGUMENTS` exists relative to `brain/`, use it.
5. If the path cannot be resolved, stop and explain which path could not be found.

## Scope for candidate notes

- inspect only notes under allowed folders
- candidate notes must be markdown files
- exclude the current note itself from linking candidates

## How to find related notes

1. Read the target note.
2. Extract relevant concepts from:
   - headings
   - repeated nouns / noun phrases
   - component names
   - project names
   - architecture terms
   - task names
   - decision names
   - domain concepts
3. Extract tags from the note (`#tag`).
4. Search candidate notes whose:
   - filename matches the concept, or
   - title matches the concept, or
   - first heading matches the concept, or
   - content clearly defines the concept, or
   - tags match the concept or overlap strongly with the target note tags
5. Rank candidates by:
   1. exact filename match
   2. exact note title match
   3. shared tags
   4. exact heading match
   5. strong semantic match from content
6. Only select strong matches.
7. If a strong match is already found through filename, title, or shared tag, stop searching broadly for that concept.

## Link insertion policy

- Insert the Obsidian link inline on the same line where the concept appears.
- The link must come immediately after the cited concept.
- Preferred format:

`conceito [[nome-da-nota]]`

- If the concept already appears as part of an existing link, do nothing.
- If the line already contains a link to the same target note, do nothing.
- Do not add more than one new link per concept occurrence on the same line.
- Avoid turning every repeated occurrence into a link; prioritize the first strong occurrence in a relevant section.

## Examples

- `O gateway matriz concentra a sincronização com a nuvem.`
  becomes
  `O gateway matriz [[gateway-matriz]] concentra a sincronização com a nuvem.`
- `A comunicação LoRa é crítica para o projeto.`
  becomes
  `A comunicação LoRa [[comunicacao-lora]] é crítica para o projeto.`

## Quality filter

Only add a link when the relation is clearly useful for navigation.

Do not link:

- generic words
- weakly related concepts
- folder labels
- markdown boilerplate words
- stopwords
- dates unless there is a specific session note match
- very broad words like `sistema`, `projeto`, `solução` unless there is a very specific corresponding note and the context makes it unambiguous

## Preferred matching priority

1. exact filename match
2. exact note title match
3. shared tags
4. exact heading match
5. strong semantic match
6. do not link if confidence is low

## Before saving

- review the edited lines
- remove redundant or noisy links
- make sure no duplicate links were introduced
- keep the note natural to read

## Output

After execution, print only:

- resolved path
- number of links added
- list of target notes linked
- any ambiguous concepts intentionally skipped
