# Graph Report - coleira  (2026-04-11)

## Corpus Check
- Corpus is ~8,678 words - fits in a single context window. You may not need a graph.

## Summary
- 98 nodes · 153 edges · 15 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `update()` - 7 edges
2. `begin()` - 5 edges
3. `loadLastGoodFixFromEeprom()` - 5 edges
4. `ensureEepromReady()` - 4 edges
5. `persistLastGoodFix()` - 4 edges
6. `refreshAdvertising()` - 4 edges
7. `encodePlain()` - 3 edges
8. `decodePlain()` - 3 edges
9. `probeI2cAddress()` - 3 edges
10. `runI2cScan()` - 3 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Community 0"
Cohesion: 0.29
Nodes (12): applyFilter(), begin(), crc16(), ensureEepromReady(), haversineMeters(), isOutlier(), loadLastGoodFixFromEeprom(), medianValue() (+4 more)

### Community 1 - "Community 1"
Cohesion: 0.2
Nodes (3): calcHmac16(), encryptAndSign(), verifyAndDecrypt()

### Community 2 - "Community 2"
Cohesion: 0.2
Nodes (9): begin(), loop(), maybeNotifyConnectedClient(), PositionReadCallbacks, PresenceServerCallbacks, refreshAdvertising(), setPosition(), updatePositionCharacteristic() (+1 more)

### Community 3 - "Community 3"
Cohesion: 0.31
Nodes (6): decodePlain(), encodePlain(), rd32(), rd64(), wr32(), wr64()

### Community 4 - "Community 4"
Cohesion: 0.36
Nodes (6): begin(), captureGpsBootSampleChar(), probeI2cAddress(), readGpsSnapshot(), readTelemetry(), runI2cScan()

### Community 5 - "Community 5"
Cohesion: 0.31
Nodes (3): distanceToSegmentMeters(), haversineMeters(), isNearBoundary()

### Community 6 - "Community 6"
Cohesion: 0.48
Nodes (5): begin(), popEvent(), pushEvent(), resetQueue(), slotAddr()

### Community 7 - "Community 7"
Cohesion: 0.4
Nodes (0): 

### Community 8 - "Community 8"
Cohesion: 0.67
Nodes (0): 

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (0): 

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (0): 

### Community 12 - "Community 12"
Cohesion: 1.0
Nodes (1): pinagem

### Community 13 - "Community 13"
Cohesion: 1.0
Nodes (1): README

### Community 14 - "Community 14"
Cohesion: 1.0
Nodes (1): funcionamento

## Knowledge Gaps
- **4 isolated node(s):** `PositionReadCallbacks`, `pinagem`, `README`, `funcionamento`
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 9`** (1 nodes): `build_opt.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (1 nodes): `manual_settings.local.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `command_contract_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `pinagem`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (1 nodes): `README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 14`** (1 nodes): `funcionamento`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `PositionReadCallbacks`, `pinagem`, `README` to the rest of the system?**
  _4 weakly-connected nodes found - possible documentation gaps or missing edges._