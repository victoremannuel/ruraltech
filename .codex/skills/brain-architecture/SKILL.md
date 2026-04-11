---
name: brain-architecture
description: Document a system, component, or flow in the architecture folder.
disable-model-invocation: true
allowed-tools: Bash(find *) Bash(ls *) Read Write Edit MultiEdit
---

Document architecture in `brain/arquitetura`.

Subject:
$ARGUMENTS

Rules:
- prefer updating an existing architecture note
- use concrete technical language
- link to related decisions and project notes
- keep it reusable

Template:

# Architecture: $ARGUMENTS

## Overview

## Components

## Data flow

## Integrations

## Technologies

## Risks

## Related

[[related note]]

At the end:
- print the file path
- list the related notes added