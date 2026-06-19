---
type: community
cohesion: 0.33
members: 7
---

# Community 3

**Cohesion:** 0.33 - loosely connected
**Members:** 7 nodes

## Members
- [[appendLogLine()]] - code - ApiServer.cpp
- [[begin()_3]] - code - ApiServer.cpp
- [[broadcastTelemetry()]] - code - ApiServer.cpp
- [[compactIdentifier()]] - code - ApiServer.cpp
- [[handleDevicesRequest()]] - code - ApiServer.cpp
- [[handleLogsRequest()]] - code - ApiServer.cpp
- [[onWsEvent()]] - code - ApiServer.cpp

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Community_3
SORT file.name ASC
```

## Connections to other communities
- 7 edges to [[_COMMUNITY_Community 7]]
- 1 edge to [[_COMMUNITY_Community 4]]

## Top bridge nodes
- [[broadcastTelemetry()]] - degree 3, connects to 2 communities
- [[begin()_3]] - degree 6, connects to 1 community
- [[appendLogLine()]] - degree 4, connects to 1 community
- [[onWsEvent()]] - degree 3, connects to 1 community
- [[compactIdentifier()]] - degree 2, connects to 1 community