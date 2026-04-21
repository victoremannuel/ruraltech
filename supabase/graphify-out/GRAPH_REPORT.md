# Graph Report - supabase  (2026-04-11)

## Corpus Check
- Corpus is ~6,331 words - fits in a single context window. You may not need a graph.

## Summary
- 57 nodes · 100 edges · 12 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `handleRoute()` - 12 edges
2. `normalizeId()` - 10 edges
3. `normalizeText()` - 8 edges
4. `normalizeRole()` - 4 edges
5. `resolveEntityScopeId()` - 4 edges
6. `getAuthContext()` - 4 edges
7. `userHasPropertyAccess()` - 4 edges
8. `handlePropertyTelemetryLatest()` - 3 edges
9. `handlePropertyHealthLatest()` - 3 edges
10. `handlePropertyCommands()` - 3 edges

## Surprising Connections (you probably didn't know these)
- `handleRoute()` --calls--> `handlePropertyTelemetryLatest()`  [EXTRACTED]
  functions/matrix-cloud/index.ts → functions/matrix-cloud/index.ts  _Bridges community 9 → community 2_
- `handleRoute()` --calls--> `handlePropertyHealthLatest()`  [EXTRACTED]
  functions/matrix-cloud/index.ts → functions/matrix-cloud/index.ts  _Bridges community 7 → community 2_
- `handleRoute()` --calls--> `handlePropertyCommands()`  [EXTRACTED]
  functions/matrix-cloud/index.ts → functions/matrix-cloud/index.ts  _Bridges community 8 → community 2_
- `handleRoute()` --calls--> `handlePropertyCommandEvents()`  [EXTRACTED]
  functions/matrix-cloud/index.ts → functions/matrix-cloud/index.ts  _Bridges community 6 → community 2_
- `normalizeScopeId()` --calls--> `normalizeText()`  [EXTRACTED]
  functions/_shared/supabase.ts → functions/_shared/supabase.ts  _Bridges community 3 → community 1_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.21
Nodes (7): base64UrlEncode(), eventIdFor(), generateApnsJwt(), pickRuntimeId(), sendApns(), upsertCommandRecords(), validateWriterKey()

### Community 1 - "Community 1"
Cohesion: 0.29
Nodes (6): corsHeaders(), entityMatchesProperty(), isTargetReady(), jsonResponse(), normalizeScopeId(), resolveEntityScopeId()

### Community 2 - "Community 2"
Cohesion: 0.25
Nodes (8): handleMatrixBindings(), handleMatrixCommandQueues(), handleMatrixCommandResults(), handleMatrixQueueKeys(), handlePropertyEvents(), handlePropertyHealthHistory(), handlePropertyTelemetryHistory(), handleRoute()

### Community 3 - "Community 3"
Cohesion: 0.4
Nodes (6): createAdminClient(), extractQueueKey(), getAuthContext(), normalizeBusinessRef(), normalizeRole(), normalizeText()

### Community 4 - "Community 4"
Cohesion: 0.4
Nodes (5): computePropertyScopeId(), getCollarById(), getGatewayById(), getPropertyById(), normalizeId()

### Community 5 - "Community 5"
Cohesion: 0.67
Nodes (3): normalizeDeviceIdList(), normalizeIdList(), userHasPropertyAccess()

### Community 6 - "Community 6"
Cohesion: 1.0
Nodes (2): dayKeyFromMs(), handlePropertyCommandEvents()

### Community 7 - "Community 7"
Cohesion: 1.0
Nodes (2): handlePropertyHealthLatest(), updateCollarHealth()

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (2): handlePropertyCommands(), updateHerdingOperationFromCommand()

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (2): handlePropertyTelemetryLatest(), updateCollarTelemetry()

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (2): buildDispatchPayload(), derivePolygonKind()

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (2): matrixRuntimeIdFromGatewayData(), sanitizeCloudKey()

## Knowledge Gaps
- **Thin community `Community 6`** (2 nodes): `dayKeyFromMs()`, `handlePropertyCommandEvents()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 7`** (2 nodes): `handlePropertyHealthLatest()`, `updateCollarHealth()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (2 nodes): `handlePropertyCommands()`, `updateHerdingOperationFromCommand()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (2 nodes): `handlePropertyTelemetryLatest()`, `updateCollarTelemetry()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (2 nodes): `buildDispatchPayload()`, `derivePolygonKind()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (2 nodes): `matrixRuntimeIdFromGatewayData()`, `sanitizeCloudKey()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `handleRoute()` connect `Community 2` to `Community 0`, `Community 6`, `Community 7`, `Community 8`, `Community 9`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Why does `normalizeId()` connect `Community 4` to `Community 11`, `Community 1`, `Community 3`, `Community 5`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Why does `normalizeText()` connect `Community 3` to `Community 1`, `Community 11`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._