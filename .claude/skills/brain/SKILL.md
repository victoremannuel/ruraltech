---
name: brain
description: load second brain context
disable-model-invocation: true
---

Initialize second brain.

Goal:

- load graphify knowledge
- load obsidian brain knowledge
- avoid raw repository scanning
- build working project context
- prepare claude for work

Steps:

1. Check if graphify-out exists
2. If graphify is missing or outdated, run:

graphify .

3. Read graphify-out/GRAPH_REPORT.md
4. If exists, read graphify-out/wiki/index.md
5. Scan brain folder structure
6. Load relevant notes only
7. Build working context
8. Print summary

Brain path:

brain/

Folders:

brain/arquitetura  
brain/decisoes  
brain/projetos  
brain/conhecimento  
brain/tarefas  
brain/inbox  

Loading priority:

1. projetos
2. arquitetura
3. decisoes
4. tarefas
5. conhecimento

Rules:

- prefer brain knowledge over raw scanning
- prefer graphify over file search
- avoid reading entire repository
- load only relevant notes
- prefer updating knowledge over recreating
- use obsidian links as context
- do not duplicate information
- connect related concepts

Context building:

After loading:

- detect project type
- detect main components
- detect architecture
- detect active tasks
- detect key decisions
- detect knowledge notes

Output format:

# Brain Loaded

## Project

Short project description

## Main Components

- component
- component

## Architecture

Detected architecture summary

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