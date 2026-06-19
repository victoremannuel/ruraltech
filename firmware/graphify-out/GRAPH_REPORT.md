# Graph Report - firmware  (2026-04-11)

## Corpus Check
- Corpus is ~1,041 words - fits in a single context window. You may not need a graph.

## Summary
- 21 nodes · 32 edges · 5 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `skipSpaces()` - 6 edges
2. `equalsTokenIgnoreCase()` - 5 edges
3. `isAdminRole()` - 3 edges
4. `hasAdminModePermission()` - 3 edges
5. `targetIncludesGateway()` - 3 edges
6. `targetIncludesCollars()` - 3 edges
7. `feedText()` - 2 edges
8. `main()` - 2 edges
9. `isValidScopeId()` - 2 edges
10. `isTraceableCommandId()` - 2 edges

## Surprising Connections (you probably didn't know these)
- `isAdminRole()` --calls--> `equalsTokenIgnoreCase()`  [EXTRACTED]
  shared/command_contract.cpp → shared/command_contract.cpp  _Bridges community 1 → community 3_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.38
Nodes (2): planPointChunks(), validatePointCount()

### Community 1 - "Community 1"
Cohesion: 0.47
Nodes (6): equalsTokenIgnoreCase(), isTraceableCommandId(), isValidScopeId(), skipSpaces(), targetIncludesCollars(), targetIncludesGateway()

### Community 2 - "Community 2"
Cohesion: 1.0
Nodes (2): feedText(), main()

### Community 3 - "Community 3"
Cohesion: 0.67
Nodes (3): hasAdminModePermission(), isAdminRole(), validateSetParamsPayload()

### Community 4 - "Community 4"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **Thin community `Community 4`** (2 nodes): `command_contract_test.cpp`, `main()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `skipSpaces()` connect `Community 1` to `Community 0`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Why does `equalsTokenIgnoreCase()` connect `Community 1` to `Community 0`, `Community 3`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `isAdminRole()` connect `Community 3` to `Community 0`, `Community 1`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._