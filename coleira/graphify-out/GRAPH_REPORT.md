# Graph Report - coleira  (2026-06-18)

## Corpus Check
- Corpus is ~15,609 words - fits in a single context window. You may not need a graph.

## Summary
- 110 nodes · 129 edges · 27 communities detected
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 6 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_begin(), loop()|begin(), loop()]]
- [[_COMMUNITY_SmartGps.cpp, applyFilter()|SmartGps.cpp, applyFilter()]]
- [[_COMMUNITY_CryptoEngine.cpp, LoRaManager.cpp|CryptoEngine.cpp, LoRaManager.cpp]]
- [[_COMMUNITY_SensorsManager.cpp, begin()|SensorsManager.cpp, begin()]]
- [[_COMMUNITY_LoRaProtocol.cpp, decodePlain()|LoRaProtocol.cpp, decodePlain()]]
- [[_COMMUNITY_Geofence.cpp, HerdingController.cpp|Geofence.cpp, HerdingController.cpp]]
- [[_COMMUNITY_StorageQueue.cpp, begin()|StorageQueue.cpp, begin()]]
- [[_COMMUNITY_SafetyController.cpp, beep()|SafetyController.cpp, beep()]]
- [[_COMMUNITY_LoRaProtocol.h, LoRaProtocol()|LoRaProtocol.h, LoRaProtocol()]]
- [[_COMMUNITY_StateMachine.cpp, intervalMs()|StateMachine.cpp, intervalMs()]]
- [[_COMMUNITY_SmartGps.h, flags()|SmartGps.h, flags()]]
- [[_COMMUNITY_Geofence.h, Geofence()|Geofence.h, Geofence()]]
- [[_COMMUNITY_config.h, cfg()|config.h, cfg()]]
- [[_COMMUNITY_CryptoEngine.h, CryptoEngine()|CryptoEngine.h, CryptoEngine()]]
- [[_COMMUNITY_BleNodeKind(), BlePresence.h|BleNodeKind(), BlePresence.h]]
- [[_COMMUNITY_StateMachine.h, StateMachine()|StateMachine.h, StateMachine()]]
- [[_COMMUNITY_LoRaManager.h, LoRaManager()|LoRaManager.h, LoRaManager()]]
- [[_COMMUNITY_StorageQueue.h, StorageQueue()|StorageQueue.h, StorageQueue()]]
- [[_COMMUNITY_manual_settings.h, cfg_manual()|manual_settings.h, cfg_manual()]]
- [[_COMMUNITY_SensorsManager.h, SensorsManager()|SensorsManager.h, SensorsManager()]]
- [[_COMMUNITY_SafetyController.h, SafetyController()|SafetyController.h, SafetyController()]]
- [[_COMMUNITY_HerdingController.h, HerdingController()|HerdingController.h, HerdingController()]]
- [[_COMMUNITY_build_opt.h|build_opt.h]]
- [[_COMMUNITY_Types.h|Types.h]]
- [[_COMMUNITY_manual_settings.local.h|manual_settings.local.h]]
- [[_COMMUNITY_Logger.h|Logger.h]]
- [[_COMMUNITY_command_contract_bridge.cpp|command_contract_bridge.cpp]]

## God Nodes (most connected - your core abstractions)
1. `update()` - 8 edges
2. `receiveFrame()` - 5 edges
3. `begin()` - 5 edges
4. `loadLastGoodFixFromEeprom()` - 5 edges
5. `sendFrame()` - 4 edges
6. `encodePlain()` - 4 edges
7. `decodePlain()` - 4 edges
8. `ensureEepromReady()` - 4 edges
9. `persistLastGoodFix()` - 4 edges
10. `refreshAdvertising()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `tick()` --calls--> `update()`  [INFERRED]
  coleira/SensorsManager.cpp → coleira/SmartGps.cpp
- `sendFrame()` --calls--> `encodePlain()`  [INFERRED]
  coleira/LoRaManager.cpp → coleira/LoRaProtocol.cpp
- `receiveFrame()` --calls--> `decodePlain()`  [INFERRED]
  coleira/LoRaManager.cpp → coleira/LoRaProtocol.cpp
- `sendFrame()` --calls--> `encryptAndSign()`  [INFERRED]
  coleira/LoRaManager.cpp → coleira/CryptoEngine.cpp
- `receiveFrame()` --calls--> `verifyAndDecrypt()`  [INFERRED]
  coleira/LoRaManager.cpp → coleira/CryptoEngine.cpp

## Communities

### Community 0 - "begin(), loop()"
Cohesion: 0.21
Nodes (9): begin(), loop(), maybeNotifyConnectedClient(), PositionReadCallbacks, PresenceServerCallbacks, refreshAdvertising(), setPosition(), updatePositionCharacteristic() (+1 more)

### Community 1 - "SmartGps.cpp, applyFilter()"
Cohesion: 0.35
Nodes (12): applyFilter(), begin(), crc16(), ensureEepromReady(), haversineMeters(), isOutlier(), loadLastGoodFixFromEeprom(), medianValue() (+4 more)

### Community 2 - "CryptoEngine.cpp, LoRaManager.cpp"
Cohesion: 0.29
Nodes (7): calcHmac16(), encryptAndSign(), verifyAndDecrypt(), bytesToHex(), persistReplayCheckpoint(), receiveFrame(), sendFrame()

### Community 3 - "SensorsManager.cpp, begin()"
Cohesion: 0.39
Nodes (7): begin(), captureGpsBootSampleChar(), probeI2cAddress(), readGpsSnapshot(), readTelemetry(), runI2cScan(), tick()

### Community 4 - "LoRaProtocol.cpp, decodePlain()"
Cohesion: 0.48
Nodes (6): decodePlain(), encodePlain(), rd32(), rd64(), wr32(), wr64()

### Community 5 - "Geofence.cpp, HerdingController.cpp"
Cohesion: 0.38
Nodes (5): distanceToSegmentMeters(), haversineMeters(), isInside(), isNearBoundary(), updateWithGps()

### Community 6 - "StorageQueue.cpp, begin()"
Cohesion: 0.48
Nodes (6): begin(), popEvent(), pushEvent(), resetPersistentQueue(), resetRamQueue(), slotAddr()

### Community 7 - "SafetyController.cpp, beep()"
Cohesion: 0.4
Nodes (0): 

### Community 8 - "LoRaProtocol.h, LoRaProtocol()"
Cohesion: 0.5
Nodes (0): 

### Community 9 - "StateMachine.cpp, intervalMs()"
Cohesion: 0.67
Nodes (0): 

### Community 10 - "SmartGps.h, flags()"
Cohesion: 0.67
Nodes (0): 

### Community 11 - "Geofence.h, Geofence()"
Cohesion: 1.0
Nodes (0): 

### Community 12 - "config.h, cfg()"
Cohesion: 1.0
Nodes (0): 

### Community 13 - "CryptoEngine.h, CryptoEngine()"
Cohesion: 1.0
Nodes (0): 

### Community 14 - "BleNodeKind(), BlePresence.h"
Cohesion: 1.0
Nodes (0): 

### Community 15 - "StateMachine.h, StateMachine()"
Cohesion: 1.0
Nodes (0): 

### Community 16 - "LoRaManager.h, LoRaManager()"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "StorageQueue.h, StorageQueue()"
Cohesion: 1.0
Nodes (0): 

### Community 18 - "manual_settings.h, cfg_manual()"
Cohesion: 1.0
Nodes (0): 

### Community 19 - "SensorsManager.h, SensorsManager()"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "SafetyController.h, SafetyController()"
Cohesion: 1.0
Nodes (0): 

### Community 21 - "HerdingController.h, HerdingController()"
Cohesion: 1.0
Nodes (0): 

### Community 22 - "build_opt.h"
Cohesion: 1.0
Nodes (0): 

### Community 23 - "Types.h"
Cohesion: 1.0
Nodes (0): 

### Community 24 - "manual_settings.local.h"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Logger.h"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "command_contract_bridge.cpp"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **1 isolated node(s):** `PositionReadCallbacks`
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Geofence.h, Geofence()`** (2 nodes): `Geofence.h`, `Geofence()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `config.h, cfg()`** (2 nodes): `config.h`, `cfg()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `CryptoEngine.h, CryptoEngine()`** (2 nodes): `CryptoEngine.h`, `CryptoEngine()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BleNodeKind(), BlePresence.h`** (2 nodes): `BleNodeKind()`, `BlePresence.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `StateMachine.h, StateMachine()`** (2 nodes): `StateMachine.h`, `StateMachine()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `LoRaManager.h, LoRaManager()`** (2 nodes): `LoRaManager.h`, `LoRaManager()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `StorageQueue.h, StorageQueue()`** (2 nodes): `StorageQueue.h`, `StorageQueue()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `manual_settings.h, cfg_manual()`** (2 nodes): `manual_settings.h`, `cfg_manual()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SensorsManager.h, SensorsManager()`** (2 nodes): `SensorsManager.h`, `SensorsManager()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `SafetyController.h, SafetyController()`** (2 nodes): `SafetyController.h`, `SafetyController()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `HerdingController.h, HerdingController()`** (2 nodes): `HerdingController.h`, `HerdingController()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `build_opt.h`** (1 nodes): `build_opt.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Types.h`** (1 nodes): `Types.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `manual_settings.local.h`** (1 nodes): `manual_settings.local.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Logger.h`** (1 nodes): `Logger.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `command_contract_bridge.cpp`** (1 nodes): `command_contract_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `update()` connect `SmartGps.cpp, applyFilter()` to `SensorsManager.cpp, begin()`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Why does `tick()` connect `SensorsManager.cpp, begin()` to `SmartGps.cpp, applyFilter()`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Why does `receiveFrame()` connect `CryptoEngine.cpp, LoRaManager.cpp` to `LoRaProtocol.cpp, decodePlain()`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `receiveFrame()` (e.g. with `verifyAndDecrypt()` and `decodePlain()`) actually correct?**
  _`receiveFrame()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `sendFrame()` (e.g. with `encodePlain()` and `encryptAndSign()`) actually correct?**
  _`sendFrame()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PositionReadCallbacks` to the rest of the system?**
  _1 weakly-connected nodes found - possible documentation gaps or missing edges._