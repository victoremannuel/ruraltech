---
name: bootstrap
description: Initialize the working context by loading the second brain through /brain with minimal overhead.
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

Initialize the project context with minimal token usage.

Argument:
$ARGUMENTS

Goal:
- load the second brain through `/brain`
- avoid duplicate loading of Graphify and brain notes
- keep bootstrap lightweight
- return only a short ready status

Rules:
- do not manually reload Graphify artifacts if `/brain` already handled them
- do not manually rescan `brain/` after `/brain`
- prefer relative project paths over absolute machine-specific paths
- keep output short
- stop as soon as `/brain` provides enough context

Workflow:
1. Invoke `/brain $ARGUMENTS`
2. If `/brain` succeeds, do not perform extra loading
3. If `/brain` reports missing or outdated Graphify artifacts, allow `/brain` to resolve that
4. Return a short ready status only

Output:
# Bootstrap Ready

- scope loaded
- brain initialized
- graphify status
- ready to work