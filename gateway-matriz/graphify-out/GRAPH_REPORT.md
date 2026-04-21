# Graph Report - gateway-matriz  (2026-04-11)

## Corpus Check
- Corpus is ~7,359 words - fits in a single context window. You may not need a graph.

## Summary
- 89 nodes · 140 edges · 14 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `updateDeviceFromPacket()` - 7 edges
2. `processLine()` - 7 edges
3. `begin()` - 6 edges
4. `prepareSpiBusForLoRa()` - 5 edges
5. `armContinuousReceive()` - 5 edges
6. `receive()` - 5 edges
7. `refreshAdvertising()` - 5 edges
8. `log()` - 4 edges
9. `begin()` - 4 edges
10. `appendLogLine()` - 4 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "Community 0"
Cohesion: 0.21
Nodes (15): allocateDeviceSlot(), appendLogLine(), begin(), broadcastTelemetry(), compactIdentifier(), copyToBuffer(), findDeviceSlot(), handleDevicesRequest() (+7 more)

### Community 1 - "Community 1"
Cohesion: 0.22
Nodes (10): detectDataPresence(), finishEvent(), isWhitespace(), mergePresence(), processLine(), push(), QueueStreamParser(), reset() (+2 more)

### Community 2 - "Community 2"
Cohesion: 0.24
Nodes (6): decodePlain(), encodePlain(), rd32(), rd64(), wr32(), wr64()

### Community 3 - "Community 3"
Cohesion: 0.29
Nodes (3): calcHmac16(), encryptAndSign(), verifyAndDecrypt()

### Community 4 - "Community 4"
Cohesion: 0.44
Nodes (8): armContinuousReceive(), begin(), idxForDevice(), loadReplayState(), persistReplayState(), prepareSpiBusForLoRa(), receive(), send()

### Community 5 - "Community 5"
Cohesion: 0.36
Nodes (5): begin(), loop(), refreshAdvertising(), setFlags(), writeInt32LE()

### Community 6 - "Community 6"
Cohesion: 0.57
Nodes (5): begin(), hashLine(), log(), prepareSpiBusForSd(), releaseChipSelect()

### Community 7 - "Community 7"
Cohesion: 1.0
Nodes (0): 

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (0): 

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (0): 

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (1): Pinagem

### Community 12 - "Community 12"
Cohesion: 1.0
Nodes (1): Readme

### Community 13 - "Community 13"
Cohesion: 1.0
Nodes (1): Funcionamento

## Knowledge Gaps
- **3 isolated node(s):** `Pinagem`, `Readme`, `Funcionamento`
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 7`** (1 nodes): `build_opt.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (1 nodes): `manual_settings.local.example.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (1 nodes): `manual_settings.local.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (1 nodes): `command_contract_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `Pinagem`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `Readme`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (1 nodes): `Funcionamento`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `Pinagem`, `Readme`, `Funcionamento` to the rest of the system?**
  _3 weakly-connected nodes found - possible documentation gaps or missing edges._