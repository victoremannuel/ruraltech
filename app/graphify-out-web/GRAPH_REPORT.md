# Graph Report - app/web-scope  (2026-06-18)

## Corpus Check
- 114 files · ~83,740 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1183 nodes · 1559 edges · 34 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_rt_action_row 2.dart, build|rt_action_row 2.dart, build]]
- [[_COMMUNITY_area_editor_screen.dart, AreaEditorScreen|area_editor_screen.dart, AreaEditorScreen]]
- [[_COMMUNITY_add_collar_screen.dart, add_gateway_screen.dart|add_collar_screen.dart, add_gateway_screen.dart]]
- [[_COMMUNITY_firebase_service 2.dart, _dayKeyFromMs|firebase_service 2.dart, _dayKeyFromMs]]
- [[_COMMUNITY_rt_collar_sheet 2.dart, _actionsRow|rt_collar_sheet 2.dart, _actionsRow]]
- [[_COMMUNITY_device_model.dart, DeviceModel|device_model.dart, DeviceModel]]
- [[_COMMUNITY_device_details_screen.dart, _boolLabel|device_details_screen.dart, _boolLabel]]
- [[_COMMUNITY_firebase_options 2.dart, DefaultFirebaseOptions|firebase_options 2.dart, DefaultFirebaseOptions]]
- [[_COMMUNITY_bluetooth_discovery_service.dart, _bestName|bluetooth_discovery_service.dart, _bestName]]
- [[_COMMUNITY_add_gateway_screen 2.dart, AddGatewayScreen|add_gateway_screen 2.dart, AddGatewayScreen]]
- [[_COMMUNITY_geofence_screen.dart, build|geofence_screen.dart, build]]
- [[_COMMUNITY_main.dart, _AuthenticatedHome|main.dart, _AuthenticatedHome]]
- [[_COMMUNITY_herding_screen.dart, _BottomBar|herding_screen.dart, _BottomBar]]
- [[_COMMUNITY_rt_field 2.dart, _border|rt_field 2.dart, _border]]
- [[_COMMUNITY_collar_log_screen.dart, build|collar_log_screen.dart, build]]
- [[_COMMUNITY_add_collar_screen 2.dart, AddCollarScreen|add_collar_screen 2.dart, AddCollarScreen]]
- [[_COMMUNITY_cloud_service.dart, CloudService|cloud_service.dart, CloudService]]
- [[_COMMUNITY_colors 2.dart, _oklch|colors 2.dart, _oklch]]
- [[_COMMUNITY_top_feedback.dart, AppFeedback|top_feedback.dart, AppFeedback]]
- [[_COMMUNITY_events_screen.dart, build|events_screen.dart, build]]
- [[_COMMUNITY_theme 2.dart, buildRuralTechTheme|theme 2.dart, buildRuralTechTheme]]
- [[_COMMUNITY_home_shell 2.dart, build|home_shell 2.dart, build]]
- [[_COMMUNITY_rt_fab.dart, _ActionPill|rt_fab.dart, _ActionPill]]
- [[_COMMUNITY_tokens 2.dart, RTElevation|tokens 2.dart, RTElevation]]
- [[_COMMUNITY_cloud_compat.dart, CloudAuthException|cloud_compat.dart, CloudAuthException]]
- [[_COMMUNITY_index.js, collectPushTokens()|index.js, collectPushTokens()]]
- [[_COMMUNITY_index 2.js, collectPushTokens()|index 2.js, collectPushTokens()]]
- [[_COMMUNITY_onboarding_gateway_utils.dart, Function|onboarding_gateway_utils.dart, Function]]
- [[_COMMUNITY_manual_settings.dart, ManualSettings|manual_settings.dart, ManualSettings]]
- [[_COMMUNITY_home_session_state.dart, shouldShowBlockingHomeLoader|home_session_state.dart, shouldShowBlockingHomeLoader]]
- [[_COMMUNITY_fence_model.dart, FenceModel|fence_model.dart, FenceModel]]
- [[_COMMUNITY_event_model.dart, EventModel|event_model.dart, EventModel]]
- [[_COMMUNITY_herding_plan_model.dart, HerdingPlanModel|herding_plan_model.dart, HerdingPlanModel]]
- [[_COMMUNITY_pending_notifications.dart|pending_notifications.dart]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 71 edges
2. `../../design/colors.dart` - 50 edges
3. `../../design/tokens.dart` - 48 edges
4. `../../design/typography.dart` - 44 edges
5. `package:latlong2/latlong.dart` - 19 edges
6. `package:provider/provider.dart` - 17 edges
7. `../services/auth_service.dart` - 15 edges
8. `../utils/top_feedback.dart` - 15 edges
9. `../config/manual_settings.dart` - 14 edges
10. `../services/cloud_service.dart` - 14 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities

### Community 0 - "rt_action_row 2.dart, build"
Cohesion: 0.02
Nodes (158): build, Material, RTActionRow, SizedBox, build, Material, RTActionRow, SizedBox (+150 more)

### Community 1 - "area_editor_screen.dart, AreaEditorScreen"
Cohesion: 0.02
Nodes (92): AreaEditorScreen, _AreaEditorScreenState, build, Center, Container, dispose, Exception, _gatewayLabel (+84 more)

### Community 2 - "add_collar_screen.dart, add_gateway_screen.dart"
Cohesion: 0.03
Nodes (75): add_collar_screen.dart, add_gateway_screen.dart, _angularDiffDegrees, _applyFilterViewportIfNeeded, _applyHeading, _bindGatewayTelemetryStream, build, _buildHomeFab (+67 more)

### Community 3 - "firebase_service 2.dart, _dayKeyFromMs"
Cohesion: 0.04
Nodes (55): _dayKeyFromMs, _decodeHerdingPhases, _decodeLatLonPoints, DeviceModel, emit, _eventSortKeyMs, Exception, FirebaseService (+47 more)

### Community 4 - "rt_collar_sheet 2.dart, _actionsRow"
Cohesion: 0.04
Nodes (52): _actionsRow, build, Column, Container, DraggableScrollableSheet, _grabber, _header, Row (+44 more)

### Community 5 - "device_model.dart, DeviceModel"
Cohesion: 0.04
Nodes (52): DeviceModel, _hasHealthFlag, HerdingOperationDeviceStatus, HerdingOperationModel, herdingOperationStatusFromValue, herdingOperationStatusValue, idFrom, action (+44 more)

### Community 6 - "device_details_screen.dart, _boolLabel"
Cohesion: 0.04
Nodes (52): _boolLabel, build, _buildActions, _buildGpsBusGrid, _buildHero, _buildPositionCard, DeviceDetailsScreen, _formatCoord (+44 more)

### Community 7 - "firebase_options 2.dart, DefaultFirebaseOptions"
Cohesion: 0.04
Nodes (44): DefaultFirebaseOptions, UnsupportedError, DefaultFirebaseOptions, UnsupportedError, PolygonMapContext, PolygonMapDeviceOverlay, PolygonMapGatewayOverlay, applySelections (+36 more)

### Community 8 - "bluetooth_discovery_service.dart, _bestName"
Cohesion: 0.04
Nodes (47): _bestName, BluetoothDiscoveryService, _candidateMap, _connectWithRetry, dispose, _ensureAdapterOn, Exception, _initIfNeeded (+39 more)

### Community 9 - "add_gateway_screen 2.dart, AddGatewayScreen"
Cohesion: 0.04
Nodes (47): AddGatewayScreen, _AddGatewayScreenState, _applyDetectedGateway, _border, build, Container, dispose, Divider (+39 more)

### Community 10 - "geofence_screen.dart, build"
Cohesion: 0.05
Nodes (41): build, _buildActionsBar, ClipRRect, GeofenceScreen, _GeofenceScreenState, GestureDetector, _GhostBtn, _HudPill (+33 more)

### Community 11 - "main.dart, _AuthenticatedHome"
Cohesion: 0.05
Nodes (41): _AuthenticatedHome, _AuthenticatedHomeState, build, callbackDispatcher, didChangeDependencies, HomeShell, InitializationSettings, MaterialApp (+33 more)

### Community 12 - "herding_screen.dart, _BottomBar"
Cohesion: 0.05
Nodes (42): _BottomBar, build, _buildEmpty, _buildError, _buildMapContext, Center, Column, Container (+34 more)

### Community 13 - "rt_field 2.dart, _border"
Cohesion: 0.05
Nodes (40): _border, build, Column, RTField, _RTFieldState, SizedBox, AddCollarScreen, _AddCollarScreenState (+32 more)

### Community 14 - "collar_log_screen.dart, build"
Cohesion: 0.06
Nodes (34): build, _buildControlBar, _buildLogEntry, _buildLogList, _buildPolygonResultSection, Center, CollarLogScreen, _CollarLogScreenState (+26 more)

### Community 15 - "add_collar_screen 2.dart, AddCollarScreen"
Cohesion: 0.06
Nodes (34): AddCollarScreen, _AddCollarScreenState, AlertDialog, _applyDetectedCollar, _border, build, Column, Container (+26 more)

### Community 16 - "cloud_service.dart, CloudService"
Cohesion: 0.06
Nodes (30): CloudService, _commandEventMatchesDevice, _computePropertyScopeId, _decodeHerdingPhases, _decodeLatLonPoints, emit, Exception, getLatestTelemetryPositionForDevice (+22 more)

### Community 17 - "colors 2.dart, _oklch"
Cohesion: 0.07
Nodes (23): _oklch, RTColors, toByte, _oklch, RTColors, toByte, _oklch, RTColors (+15 more)

### Community 18 - "top_feedback.dart, AppFeedback"
Cohesion: 0.09
Nodes (22): AppFeedback, _AppFeedbackController, AppFeedbackHost, _AppFeedbackHostState, _AppFeedbackMessage, _backgroundForType, build, clear (+14 more)

### Community 19 - "events_screen.dart, build"
Cohesion: 0.09
Nodes (22): build, _buildEmpty, _buildError, _buildFilters, Center, _CounterCard, EventsScreen, _EventsScreenState (+14 more)

### Community 20 - "theme 2.dart, buildRuralTechTheme"
Cohesion: 0.12
Nodes (16): buildRuralTechTheme, ThemeData, buildRuralTechTheme, ThemeData, buildRuralTechTheme, ThemeData, RTTypography, textTheme (+8 more)

### Community 21 - "home_shell 2.dart, build"
Cohesion: 0.1
Nodes (20): build, HomeShell, _HomeShellState, _KeepAliveTab, _KeepAliveTabState, KeyedSubtree, Scaffold, _TabConfig (+12 more)

### Community 22 - "rt_fab.dart, _ActionPill"
Cohesion: 0.14
Nodes (13): _ActionPill, AnimatedBuilder, build, Column, dispose, _handleAction, _mainFab, Material (+5 more)

### Community 23 - "tokens 2.dart, RTElevation"
Cohesion: 0.21
Nodes (6): RTElevation, RTRadius, RTSpacing, RTElevation, RTRadius, RTSpacing

### Community 24 - "cloud_compat.dart, CloudAuthException"
Cohesion: 0.25
Nodes (7): CloudAuthException, CloudException, DocumentReference, GeoPoint, Timestamp, toDate, toString

### Community 25 - "index.js, collectPushTokens()"
Cohesion: 0.36
Nodes (5): collectPushTokens(), createAreaFromOperation(), normalizeId(), pointList(), sendPush()

### Community 26 - "index 2.js, collectPushTokens()"
Cohesion: 0.36
Nodes (5): collectPushTokens(), createAreaFromOperation(), normalizeId(), pointList(), sendPush()

### Community 27 - "onboarding_gateway_utils.dart, Function"
Cohesion: 0.67
Nodes (2): Function, matchesSelectedGatewayId

### Community 28 - "manual_settings.dart, ManualSettings"
Cohesion: 1.0
Nodes (1): ManualSettings

### Community 29 - "home_session_state.dart, shouldShowBlockingHomeLoader"
Cohesion: 1.0
Nodes (1): shouldShowBlockingHomeLoader

### Community 30 - "fence_model.dart, FenceModel"
Cohesion: 1.0
Nodes (1): FenceModel

### Community 31 - "event_model.dart, EventModel"
Cohesion: 1.0
Nodes (1): EventModel

### Community 32 - "herding_plan_model.dart, HerdingPlanModel"
Cohesion: 1.0
Nodes (1): HerdingPlanModel

### Community 33 - "pending_notifications.dart"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **1012 isolated node(s):** `DefaultFirebaseOptions`, `UnsupportedError`, `RuralTechApp`, `_AuthenticatedHome`, `_AuthenticatedHomeState` (+1007 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `manual_settings.dart, ManualSettings`** (2 nodes): `manual_settings.dart`, `ManualSettings`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `home_session_state.dart, shouldShowBlockingHomeLoader`** (2 nodes): `home_session_state.dart`, `shouldShowBlockingHomeLoader`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `fence_model.dart, FenceModel`** (2 nodes): `fence_model.dart`, `FenceModel`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `event_model.dart, EventModel`** (2 nodes): `event_model.dart`, `EventModel`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `herding_plan_model.dart, HerdingPlanModel`** (2 nodes): `herding_plan_model.dart`, `HerdingPlanModel`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `pending_notifications.dart`** (1 nodes): `pending_notifications.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `rt_action_row 2.dart, build` to `area_editor_screen.dart, AreaEditorScreen`, `add_collar_screen.dart, add_gateway_screen.dart`, `firebase_service 2.dart, _dayKeyFromMs`, `rt_collar_sheet 2.dart, _actionsRow`, `device_model.dart, DeviceModel`, `device_details_screen.dart, _boolLabel`, `bluetooth_discovery_service.dart, _bestName`, `add_gateway_screen 2.dart, AddGatewayScreen`, `geofence_screen.dart, build`, `main.dart, _AuthenticatedHome`, `herding_screen.dart, _BottomBar`, `rt_field 2.dart, _border`, `collar_log_screen.dart, build`, `add_collar_screen 2.dart, AddCollarScreen`, `colors 2.dart, _oklch`, `top_feedback.dart, AppFeedback`, `events_screen.dart, build`, `theme 2.dart, buildRuralTechTheme`, `home_shell 2.dart, build`, `rt_fab.dart, _ActionPill`, `tokens 2.dart, RTElevation`?**
  _High betweenness centrality (0.288) - this node is a cross-community bridge._
- **Why does `package:latlong2/latlong.dart` connect `geofence_screen.dart, build` to `area_editor_screen.dart, AreaEditorScreen`, `add_collar_screen.dart, add_gateway_screen.dart`, `firebase_service 2.dart, _dayKeyFromMs`, `firebase_options 2.dart, DefaultFirebaseOptions`, `add_gateway_screen 2.dart, AddGatewayScreen`, `herding_screen.dart, _BottomBar`, `rt_field 2.dart, _border`, `add_collar_screen 2.dart, AddCollarScreen`, `cloud_service.dart, CloudService`, `colors 2.dart, _oklch`?**
  _High betweenness centrality (0.119) - this node is a cross-community bridge._
- **Why does `../../design/colors.dart` connect `rt_action_row 2.dart, build` to `area_editor_screen.dart, AreaEditorScreen`, `add_collar_screen.dart, add_gateway_screen.dart`, `rt_collar_sheet 2.dart, _actionsRow`, `device_model.dart, DeviceModel`, `device_details_screen.dart, _boolLabel`, `add_gateway_screen 2.dart, AddGatewayScreen`, `geofence_screen.dart, build`, `herding_screen.dart, _BottomBar`, `rt_field 2.dart, _border`, `collar_log_screen.dart, build`, `add_collar_screen 2.dart, AddCollarScreen`, `events_screen.dart, build`, `home_shell 2.dart, build`, `rt_fab.dart, _ActionPill`?**
  _High betweenness centrality (0.103) - this node is a cross-community bridge._
- **What connects `DefaultFirebaseOptions`, `UnsupportedError`, `RuralTechApp` to the rest of the system?**
  _1012 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `rt_action_row 2.dart, build` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `area_editor_screen.dart, AreaEditorScreen` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._
- **Should `add_collar_screen.dart, add_gateway_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.03 - nodes in this community are weakly interconnected._