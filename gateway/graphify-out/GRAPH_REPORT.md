# Graph Report - gateway  (2026-04-11)

## Corpus Check
- Corpus is ~4,934 words - fits in a single context window. You may not need a graph.

## Summary
- 67 nodes · 95 edges · 13 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `updateDeviceFromPacket()` - 7 edges
2. `begin()` - 6 edges
3. `refreshAdvertising()` - 5 edges
4. `appendLogLine()` - 4 edges
5. `encodePlain()` - 3 edges
6. `decodePlain()` - 3 edges
7. `receive()` - 3 edges
8. `onWsEvent()` - 3 edges
9. `broadcastTelemetry()` - 3 edges
10. `calcHmac16()` - 3 edges

## Surprising Connections (you probably didn't know these)
- `broadcastTelemetry()` --calls--> `updateDeviceFromPacket()`  [EXTRACTED]
  ApiServer.cpp → ApiServer.cpp  _Bridges community 4 → community 3_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.22
Nodes (5): begin(), idxForDevice(), loadReplayState(), persistReplayState(), receive()

### Community 1 - "Community 1"
Cohesion: 0.24
Nodes (6): decodePlain(), encodePlain(), rd32(), rd64(), wr32(), wr64()

### Community 2 - "Community 2"
Cohesion: 0.36
Nodes (5): begin(), loop(), refreshAdvertising(), setFlags(), writeInt32LE()

### Community 3 - "Community 3"
Cohesion: 0.33
Nodes (7): appendLogLine(), begin(), broadcastTelemetry(), compactIdentifier(), handleDevicesRequest(), handleLogsRequest(), onWsEvent()

### Community 4 - "Community 4"
Cohesion: 0.33
Nodes (6): allocateDeviceSlot(), copyToBuffer(), findDeviceSlot(), parseCoordinate(), parseDeviceId(), updateDeviceFromPacket()

### Community 5 - "Community 5"
Cohesion: 0.6
Nodes (2): hashLine(), log()

### Community 6 - "Community 6"
Cohesion: 0.7
Nodes (3): calcHmac16(), encryptAndSign(), verifyAndDecrypt()

### Community 7 - "Community 7"
Cohesion: 0.6
Nodes (2): hasPendingCommand(), popCommand()

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (0): 

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (1): Pinagem

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (1): Readme

### Community 12 - "Community 12"
Cohesion: 1.0
Nodes (1): Funcionamento

## Knowledge Gaps
- **3 isolated node(s):** `Pinagem`, `Readme`, `Funcionamento`
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 8`** (1 nodes): `build_opt.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (1 nodes): `command_contract_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (1 nodes): `Pinagem`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `Readme`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `Funcionamento`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `updateDeviceFromPacket()` connect `Community 4` to `Community 3`, `Community 7`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **Why does `begin()` connect `Community 3` to `Community 7`?**
  _High betweenness centrality (0.002) - this node is a cross-community bridge._
- **What connects `Pinagem`, `Readme`, `Funcionamento` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._