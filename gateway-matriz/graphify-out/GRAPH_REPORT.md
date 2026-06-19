# Graph Report - gateway-matriz  (2026-06-18)

## Corpus Check
- Corpus is ~17,492 words - fits in a single context window. You may not need a graph.

## Summary
- 109 nodes · 153 edges · 26 communities detected
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 9 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_allocateDeviceSlot(), appendLogLine()|allocateDeviceSlot(), appendLogLine()]]
- [[_COMMUNITY_QueueStreamSupport.cpp, detectDataPresence()|QueueStreamSupport.cpp, detectDataPresence()]]
- [[_COMMUNITY_LoRaGateway.cpp, armContinuousReceive()|LoRaGateway.cpp, armContinuousReceive()]]
- [[_COMMUNITY_begin(), loop()|begin(), loop()]]
- [[_COMMUNITY_LoRaProtocol.cpp, decodePlain()|LoRaProtocol.cpp, decodePlain()]]
- [[_COMMUNITY_SdLogger.cpp, begin()|SdLogger.cpp, begin()]]
- [[_COMMUNITY_LoRaProtocol.h, LoRaProtocol()|LoRaProtocol.h, LoRaProtocol()]]
- [[_COMMUNITY_calcHmac16(), encryptAndSign()|calcHmac16(), encryptAndSign()]]
- [[_COMMUNITY_items(), rpv2fenceplanner()|items(), rpv2fenceplanner()]]
- [[_COMMUNITY_SdLogger.h, SdLogger()|SdLogger.h, SdLogger()]]
- [[_COMMUNITY_LoRaGateway.h, LoRaGateway()|LoRaGateway.h, LoRaGateway()]]
- [[_COMMUNITY_cfg(), config.h|cfg(), config.h]]
- [[_COMMUNITY_Types.h, MsgType()|Types.h, MsgType()]]
- [[_COMMUNITY_CryptoEngine(), CryptoEngine.h|CryptoEngine(), CryptoEngine.h]]
- [[_COMMUNITY_BleNodeKind(), BlePresence.h|BleNodeKind(), BlePresence.h]]
- [[_COMMUNITY_manual_settings.h, cfg_manual()|manual_settings.h, cfg_manual()]]
- [[_COMMUNITY_MatrixLoRaTxAudit.h, MatrixLoRaTxReason()|MatrixLoRaTxAudit.h, MatrixLoRaTxReason()]]
- [[_COMMUNITY_RtrWakeOrchestrator.h, rtrwake()|RtrWakeOrchestrator.h, rtrwake()]]
- [[_COMMUNITY_ApiServer(), ApiServer.h|ApiServer(), ApiServer.h]]
- [[_COMMUNITY_QueueStreamSupport.h, rtmatrix()|QueueStreamSupport.h, rtmatrix()]]
- [[_COMMUNITY_build_opt.h|build_opt.h]]
- [[_COMMUNITY_manual_settings.local.example.h|manual_settings.local.example.h]]
- [[_COMMUNITY_manual_settings.local.h|manual_settings.local.h]]
- [[_COMMUNITY_matrix_uplink_antireplay_bridge.cpp|matrix_uplink_antireplay_bridge.cpp]]
- [[_COMMUNITY_Logger.h|Logger.h]]
- [[_COMMUNITY_command_contract_bridge.cpp|command_contract_bridge.cpp]]

## God Nodes (most connected - your core abstractions)
1. `receive()` - 9 edges
2. `send()` - 9 edges
3. `begin()` - 9 edges
4. `handleAntiReplayResetRequest()` - 7 edges
5. `updateDeviceFromPacket()` - 7 edges
6. `processLine()` - 7 edges
7. `prepareSpiBusForLoRa()` - 5 edges
8. `armContinuousReceive()` - 5 edges
9. `refreshAdvertising()` - 5 edges
10. `log()` - 4 edges

## Surprising Connections (you probably didn't know these)
- `buildSecureWireMetrics()` --calls--> `encodePlain()`  [INFERRED]
  gateway-matriz/LoRaGateway.cpp → gateway-matriz/LoRaProtocol.cpp
- `receive()` --calls--> `decodePlain()`  [INFERRED]
  gateway-matriz/LoRaGateway.cpp → gateway-matriz/LoRaProtocol.cpp
- `receive()` --calls--> `verifyAndDecrypt()`  [INFERRED]
  gateway-matriz/LoRaGateway.cpp → gateway-matriz/CryptoEngine.cpp
- `handleAntiReplayResetRequest()` --calls--> `resetUplinkAntiReplayForDevice()`  [INFERRED]
  gateway-matriz/ApiServer.cpp → gateway-matriz/LoRaGateway.cpp
- `begin()` --calls--> `send()`  [INFERRED]
  gateway-matriz/ApiServer.cpp → gateway-matriz/LoRaGateway.cpp

## Communities

### Community 0 - "allocateDeviceSlot(), appendLogLine()"
Cohesion: 0.2
Nodes (19): allocateDeviceSlot(), appendLogLine(), begin(), broadcastTelemetry(), compactIdentifier(), copyToBuffer(), findDeviceSlot(), handleAntiReplayResetRequest() (+11 more)

### Community 1 - "QueueStreamSupport.cpp, detectDataPresence()"
Cohesion: 0.23
Nodes (10): detectDataPresence(), finishEvent(), isWhitespace(), mergePresence(), processLine(), push(), QueueStreamParser(), reset() (+2 more)

### Community 2 - "LoRaGateway.cpp, armContinuousReceive()"
Cohesion: 0.35
Nodes (12): armContinuousReceive(), begin(), buildSecureWireMetrics(), bytesToHex(), loadReplayState(), persistReplayState(), prepareSpiBusForLoRa(), receive() (+4 more)

### Community 3 - "begin(), loop()"
Cohesion: 0.39
Nodes (5): begin(), loop(), refreshAdvertising(), setFlags(), writeInt32LE()

### Community 4 - "LoRaProtocol.cpp, decodePlain()"
Cohesion: 0.48
Nodes (6): decodePlain(), encodePlain(), rd32(), rd64(), wr32(), wr64()

### Community 5 - "SdLogger.cpp, begin()"
Cohesion: 0.67
Nodes (5): begin(), hashLine(), log(), prepareSpiBusForSd(), releaseChipSelect()

### Community 6 - "LoRaProtocol.h, LoRaProtocol()"
Cohesion: 0.5
Nodes (0): 

### Community 7 - "calcHmac16(), encryptAndSign()"
Cohesion: 0.83
Nodes (3): calcHmac16(), encryptAndSign(), verifyAndDecrypt()

### Community 8 - "items(), rpv2fenceplanner()"
Cohesion: 0.67
Nodes (0): 

### Community 9 - "SdLogger.h, SdLogger()"
Cohesion: 1.0
Nodes (0): 

### Community 10 - "LoRaGateway.h, LoRaGateway()"
Cohesion: 1.0
Nodes (0): 

### Community 11 - "cfg(), config.h"
Cohesion: 1.0
Nodes (0): 

### Community 12 - "Types.h, MsgType()"
Cohesion: 1.0
Nodes (0): 

### Community 13 - "CryptoEngine(), CryptoEngine.h"
Cohesion: 1.0
Nodes (0): 

### Community 14 - "BleNodeKind(), BlePresence.h"
Cohesion: 1.0
Nodes (0): 

### Community 15 - "manual_settings.h, cfg_manual()"
Cohesion: 1.0
Nodes (0): 

### Community 16 - "MatrixLoRaTxAudit.h, MatrixLoRaTxReason()"
Cohesion: 1.0
Nodes (0): 

### Community 17 - "RtrWakeOrchestrator.h, rtrwake()"
Cohesion: 1.0
Nodes (0): 

### Community 18 - "ApiServer(), ApiServer.h"
Cohesion: 1.0
Nodes (0): 

### Community 19 - "QueueStreamSupport.h, rtmatrix()"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "build_opt.h"
Cohesion: 1.0
Nodes (0): 

### Community 21 - "manual_settings.local.example.h"
Cohesion: 1.0
Nodes (0): 

### Community 22 - "manual_settings.local.h"
Cohesion: 1.0
Nodes (0): 

### Community 23 - "matrix_uplink_antireplay_bridge.cpp"
Cohesion: 1.0
Nodes (0): 

### Community 24 - "Logger.h"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "command_contract_bridge.cpp"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **Thin community `SdLogger.h, SdLogger()`** (2 nodes): `SdLogger.h`, `SdLogger()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `LoRaGateway.h, LoRaGateway()`** (2 nodes): `LoRaGateway.h`, `LoRaGateway()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `cfg(), config.h`** (2 nodes): `cfg()`, `config.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Types.h, MsgType()`** (2 nodes): `Types.h`, `MsgType()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `CryptoEngine(), CryptoEngine.h`** (2 nodes): `CryptoEngine()`, `CryptoEngine.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `BleNodeKind(), BlePresence.h`** (2 nodes): `BleNodeKind()`, `BlePresence.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `manual_settings.h, cfg_manual()`** (2 nodes): `manual_settings.h`, `cfg_manual()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `MatrixLoRaTxAudit.h, MatrixLoRaTxReason()`** (2 nodes): `MatrixLoRaTxAudit.h`, `MatrixLoRaTxReason()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `RtrWakeOrchestrator.h, rtrwake()`** (2 nodes): `RtrWakeOrchestrator.h`, `rtrwake()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `ApiServer(), ApiServer.h`** (2 nodes): `ApiServer()`, `ApiServer.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `QueueStreamSupport.h, rtmatrix()`** (2 nodes): `QueueStreamSupport.h`, `rtmatrix()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `build_opt.h`** (1 nodes): `build_opt.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `manual_settings.local.example.h`** (1 nodes): `manual_settings.local.example.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `manual_settings.local.h`** (1 nodes): `manual_settings.local.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `matrix_uplink_antireplay_bridge.cpp`** (1 nodes): `matrix_uplink_antireplay_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Logger.h`** (1 nodes): `Logger.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `command_contract_bridge.cpp`** (1 nodes): `command_contract_bridge.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `send()` connect `LoRaGateway.cpp, armContinuousReceive()` to `allocateDeviceSlot(), appendLogLine()`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Why does `buildSecureWireMetrics()` connect `LoRaGateway.cpp, armContinuousReceive()` to `LoRaProtocol.cpp, decodePlain()`, `calcHmac16(), encryptAndSign()`?**
  _High betweenness centrality (0.038) - this node is a cross-community bridge._
- **Why does `handleAntiReplayResetRequest()` connect `allocateDeviceSlot(), appendLogLine()` to `LoRaGateway.cpp, armContinuousReceive()`?**
  _High betweenness centrality (0.030) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `receive()` (e.g. with `verifyAndDecrypt()` and `decodePlain()`) actually correct?**
  _`receive()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `send()` (e.g. with `begin()` and `handleAntiReplayResetRequest()`) actually correct?**
  _`send()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `handleAntiReplayResetRequest()` (e.g. with `send()` and `resetUplinkAntiReplayForDevice()`) actually correct?**
  _`handleAntiReplayResetRequest()` has 2 INFERRED edges - model-reasoned connections that need verification._