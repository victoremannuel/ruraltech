---
type: community
cohesion: 0.25
members: 8
---

# Community 2

**Cohesion:** 0.25 - loosely connected
**Members:** 8 nodes

## Members
- [[handleMatrixBindings()]] - code - functions/matrix-cloud/index.ts
- [[handleMatrixCommandQueues()]] - code - functions/matrix-cloud/index.ts
- [[handleMatrixCommandResults()]] - code - functions/matrix-cloud/index.ts
- [[handleMatrixQueueKeys()]] - code - functions/matrix-cloud/index.ts
- [[handlePropertyEvents()]] - code - functions/matrix-cloud/index.ts
- [[handlePropertyHealthHistory()]] - code - functions/matrix-cloud/index.ts
- [[handlePropertyTelemetryHistory()]] - code - functions/matrix-cloud/index.ts
- [[handleRoute()]] - code - functions/matrix-cloud/index.ts

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Community_2
SORT file.name ASC
```

## Connections to other communities
- 8 edges to [[_COMMUNITY_Community 0]]
- 1 edge to [[_COMMUNITY_Community 9]]
- 1 edge to [[_COMMUNITY_Community 7]]
- 1 edge to [[_COMMUNITY_Community 8]]
- 1 edge to [[_COMMUNITY_Community 6]]

## Top bridge nodes
- [[handleRoute()]] - degree 12, connects to 5 communities
- [[handleMatrixBindings()]] - degree 2, connects to 1 community
- [[handleMatrixCommandQueues()]] - degree 2, connects to 1 community
- [[handleMatrixCommandResults()]] - degree 2, connects to 1 community
- [[handleMatrixQueueKeys()]] - degree 2, connects to 1 community