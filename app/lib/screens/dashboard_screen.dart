import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_collar_sheet.dart';
import '../components/domain/rt_telemetry_grid.dart';
import '../components/map/rt_filter_chips.dart';
import '../components/primitives/rt_button.dart';
import '../components/primitives/rt_fab.dart';
import '../config/manual_settings.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/gateway_service.dart';
import '../services/map_filter_service.dart';
import '../utils/cloud_compat.dart';
import '../utils/device_map_telemetry.dart';
import '../utils/home_session_state.dart';
import '../utils/map_coordinates.dart';
import '../utils/polygon_metrics.dart';
import '../utils/top_feedback.dart';
import 'area_editor_screen.dart';
import 'herding_screen.dart';
import 'map_point_picker_screen.dart';
import 'rural_property_editor_screen.dart';
import 'add_collar_screen.dart';
import 'add_gateway_screen.dart';
import 'device_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  int _refreshTick = 0;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<GatewayTelemetrySample>? _gatewayTelemetrySub;
  StreamSubscription<Map<String, dynamic>>? _gatewayMessageSub;
  GatewayService? _boundGatewayService;
  LatLng? _userPosition;
  double _userHeading = 0;
  int _lastAppliedFilterRevision = -1;
  int _lastAppliedFilterSignature = 0;
  String? _lastReadyAuthKey;
  String? _lastTelemetryRetentionCleanupDayKey;
  String? _selectedAreaId;
  String? _selectedAreaPropertyId;
  List<String> _selectedAreaLinkedDeviceIds = const <String>[];
  String? _selectedPropertyId;
  LatLng? _selectedPolygonAnchor;
  List<LatLng> _selectedPolygonPoints = const [];
  final Map<String, DeviceMapTelemetrySample> _latestTelemetryByDeviceId = {};
  List<DeviceModel> _latestKnownDevices = const <DeviceModel>[];

  // Stream cache: evita que build() recrie streams a cada rebuild,
  // o que causava StreamBuilder re-subscriptions e reset do mapa.
  String? _cachedStreamKey;
  Stream<List<Map<String, dynamic>>>? _propertiesStream;
  Stream<List<Map<String, dynamic>>>? _areasStream;
  Stream<List<DeviceModel>>? _devicesStream;
  Stream<List<Map<String, dynamic>>>? _gatewaysStream;

  void _updateStreamsIfNeeded({
    required String uid,
    required bool isAdmin,
  }) {
    final key = '$uid-$isAdmin-$_refreshTick';
    if (_cachedStreamKey == key) return;
    _cachedStreamKey = key;
    final fb = context.read<CloudService>();
    _propertiesStream = fb.streamRuralProperties(uid: uid, isAdmin: isAdmin);
    _areasStream = fb.streamAreas(uid: uid, isAdmin: isAdmin);
    _devicesStream = fb.streamDevices(uid: uid, isAdmin: isAdmin);
    _gatewaysStream = fb.streamGateways(uid: uid, isAdmin: isAdmin);
  }

  @override
  void initState() {
    super.initState();
    _initUserLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindGatewayTelemetryStream();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _compassSub?.cancel();
    _gatewayTelemetrySub?.cancel();
    _gatewayMessageSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _bindGatewayTelemetryStream() {
    final gateway = context.read<GatewayService>();
    if (identical(_boundGatewayService, gateway)) return;
    _boundGatewayService = gateway;
    _gatewayTelemetrySub?.cancel();
    _gatewayMessageSub?.cancel();
    _gatewayTelemetrySub = gateway.telemetryStream.listen((sample) {
      final telemetrySample = _telemetrySampleFromGateway(sample);
      if (telemetrySample == null) return;

      final matchedDevice = _matchedDeviceForTelemetrySample(telemetrySample);
      final before = matchedDevice == null
          ? null
          : _resolvedMarkerTelemetryForDevice(
              matchedDevice,
              devices: _latestKnownDevices,
            );
      final updated = _cacheTelemetrySample(telemetrySample);
      if (!updated) return;

      if (matchedDevice == null || !mounted) return;
      final after = _resolvedMarkerTelemetryForDevice(
        matchedDevice,
        devices: _latestKnownDevices,
      );
      if (didDeviceMapPointChange(before, after)) {
        setState(() {});
      }
    });
    _gatewayMessageSub = gateway.messageStream.listen(_persistCriticalEvent);
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Map<String, dynamic>? _decodePayloadMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  void _persistCriticalEvent(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = (message['type'] ?? '').toString().trim().toLowerCase();
    if (type != 'event') return;

    final deviceId = _asInt(
      message['device_id'] ??
          message['deviceId'] ??
          message['device_id_str'] ??
          message['id'],
    );
    if (deviceId == null || deviceId <= 0) return;

    final payload = _decodePayloadMap(message['payload']);
    final gatewayId =
        (message['gateway_id'] ?? message['gatewayId'])?.toString().trim();
    final gatewayRole =
        (message['gateway_role'] ?? message['gatewayRole'])?.toString().trim();
    final eventType = (payload == null
            ? null
            : (payload['type'] ?? payload['event_type'] ?? payload['reason']))
        ?.toString()
        .trim();
    if (payload == null && (gatewayId ?? gatewayRole ?? eventType) == null) {
      return;
    }
  }

  double _normalizeHeading(double heading) {
    if (!heading.isFinite) return _userHeading;
    var normalized = heading % 360.0;
    if (normalized < 0) normalized += 360.0;
    return normalized;
  }

  double _angularDiffDegrees(double a, double b) {
    final diff = (a - b).abs() % 360.0;
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  void _applyHeading(double heading) {
    final next = _normalizeHeading(heading);
    if (_angularDiffDegrees(next, _userHeading) < 0.5) return;
    if (!mounted) return;
    setState(() => _userHeading = next);
  }

  void _startCompassTracking() {
    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      _applyHeading(heading);
    });
  }

  Future<void> _initUserLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final current = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userPosition = LatLng(current.latitude, current.longitude);
        if (current.heading.isFinite && current.heading >= 0) {
          _userHeading = _normalizeHeading(current.heading);
        }
      });
    } catch (_) {}

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _userPosition = LatLng(pos.latitude, pos.longitude);
      });
      if (pos.heading.isFinite && pos.heading >= 0) {
        // Fallback when compass stream is unavailable on device.
        _applyHeading(pos.heading);
      }
    });
    _startCompassTracking();
  }

  double _countryOverviewZoom(double latitude) {
    final absLat = latitude.abs();
    if (absLat >= 55) return 2.4;
    if (absLat >= 35) return 2.7;
    return 2.9;
  }

  LatLng? _toLatLng(dynamic value) {
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    if (value is List && value.length >= 2 && value[0] is GeoPoint) {
      final point = value[0] as GeoPoint;
      return tryMapLatLngFromPair(point.latitude, point.longitude);
    }
    return tryMapLatLng(value);
  }

  LatLng? _gatewayMarkerPoint(Map<String, dynamic> gateway) {
    return tryMapLatLngFromPair(gateway['lat'], gateway['lon']) ??
        tryMapLatLng(gateway['position']);
  }

  List<LatLng> _polygonFromProperty(Map<String, dynamic>? p) {
    if (p == null) return const [];
    final points = (p['points'] as List?) ?? const [];
    return points.map(_toLatLng).whereType<LatLng>().toList();
  }

  List<LatLng> _collectViewPoints(
    List<Map<String, dynamic>> properties,
    List<Map<String, dynamic>> areas,
    List<Marker> markers,
  ) {
    final points = <LatLng>[];
    for (final p in properties) {
      final raw = (p['points'] as List?) ?? const [];
      points.addAll(raw.map(_toLatLng).whereType<LatLng>());
    }
    for (final a in areas) {
      final raw = (a['perimeter'] as List?) ?? const [];
      points.addAll(raw.map(_toLatLng).whereType<LatLng>());
    }
    points.addAll(markers.map((m) => m.point));
    return points;
  }

  String _normalizeRefId(dynamic value) {
    if (value is DocumentReference) return value.id;
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return '';
      if (!raw.contains('/')) return raw;
      final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? raw : parts.last;
    }
    if (value == null) return '';
    return value.toString().trim();
  }

  String _gatewayConnectionFailureMessage(String wsHost) {
    final host = Uri.tryParse(wsHost)?.host.trim() ?? wsHost.trim();
    if (host == '192.168.4.1') {
      return 'Nao foi possivel conectar ao gateway selecionado ($wsHost). '
          'Conecte o celular na rede Wi-Fi/AP do gateway ou atualize o IP dele na rede local.';
    }
    return 'Nao foi possivel conectar ao gateway selecionado ($wsHost) '
        'para receber telemetria ao vivo.';
  }

  String _repairCloudStateErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('admin_required')) {
      return 'Falha ao reparar o estado cloud: somente administradores podem executar esse reparo.';
    }
    if (raw.contains('missing_supabase_access_token')) {
      return 'Falha ao reparar o estado cloud: sessao do backend invalida. Entre novamente no app.';
    }
    if (raw.contains(':429') || raw.contains('RESOURCE_EXHAUSTED')) {
      return 'Falha ao reparar o estado cloud: o backend recusou a varredura por limite de taxa/quota. Tente novamente em instantes.';
    }
    return 'Falha ao reparar o estado cloud: $error';
  }

  String _normalizeNumericDeviceId(String? raw) {
    return normalizeMapNumericDeviceId(raw);
  }

  DeviceMapTelemetrySample? _telemetrySampleFromGateway(
    GatewayTelemetrySample sample,
  ) {
    final normalizedTelemetryDeviceId =
        _normalizeNumericDeviceId(sample.deviceId);
    if (normalizedTelemetryDeviceId.isEmpty) return null;
    if (!isValidMapCoordinatePair(sample.lat, sample.lon)) return null;
    return DeviceMapTelemetrySample(
      deviceId: normalizedTelemetryDeviceId,
      lat: sample.lat,
      lon: sample.lon,
      receivedAtMs: sample.receivedAtMs,
      gatewayId: _normalizeRefId(sample.gatewayId),
      source: sample.sourceType ?? 'gateway',
    );
  }

  bool _cacheTelemetrySample(DeviceMapTelemetrySample sample) {
    final current = _latestTelemetryByDeviceId[sample.deviceId];
    if (!shouldReplaceDeviceMapTelemetrySample(current, sample)) {
      return false;
    }
    _latestTelemetryByDeviceId[sample.deviceId] = sample;
    return true;
  }

  DeviceModel? _matchedDeviceForTelemetrySample(
    DeviceMapTelemetrySample sample,
  ) {
    final candidates = _latestKnownDevices.where((device) {
      final deviceId = _normalizeNumericDeviceId(
        device.loraDeviceId ?? device.deviceId ?? device.id,
      );
      return deviceId == sample.deviceId;
    }).toList(growable: false);
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;

    final gatewayId = _normalizeRefId(sample.gatewayId);
    if (gatewayId.isEmpty) return null;
    final gatewayMatches = candidates.where((device) {
      return _normalizeRefId(device.gatewayId) == gatewayId;
    }).toList(growable: false);
    if (gatewayMatches.length != 1) return null;
    return gatewayMatches.single;
  }

  LatLng? _telemetryPositionForDeviceId(String? rawDeviceId) {
    final normalized = _normalizeNumericDeviceId(rawDeviceId);
    if (normalized.isEmpty) return null;
    return _latestTelemetryByDeviceId[normalized]?.point;
  }

  void _mergeTelemetryCacheFromDevices(List<DeviceModel> devices) {
    for (final device in devices) {
      final sample = deviceMapTelemetrySampleFromDevice(device);
      if (sample == null) continue;
      _cacheTelemetrySample(sample);
    }
  }

  DeviceMapTelemetrySample? _resolvedMarkerTelemetryForDevice(
    DeviceModel device, {
    required List<DeviceModel> devices,
  }) {
    return resolvePreferredMapTelemetryForDevice(
      device: device,
      devices: devices,
      localSamplesByDeviceId: _latestTelemetryByDeviceId,
    );
  }

  int _viewPointsSignature(List<LatLng> points) {
    var hash = points.length;
    for (final p in points) {
      hash = hash * 31 + (p.latitude * 10000).round();
      hash = hash * 31 + (p.longitude * 10000).round();
    }
    return hash;
  }

  void _applyFilterViewportIfNeeded({
    required MapFilterService filters,
    required List<LatLng> viewPoints,
  }) {
    if (!filters.hasAnyFilter || viewPoints.isEmpty) {
      _lastAppliedFilterRevision = -1;
      _lastAppliedFilterSignature = 0;
      return;
    }

    final signature = _viewPointsSignature(viewPoints);
    if (_lastAppliedFilterRevision == filters.revision &&
        _lastAppliedFilterSignature == signature) {
      return;
    }
    _lastAppliedFilterRevision = filters.revision;
    _lastAppliedFilterSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (viewPoints.length >= 2) {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(viewPoints),
              padding: const EdgeInsets.all(40),
            ),
          );
        } else {
          final zoom = _mapController.camera.zoom < 15
              ? 15.0
              : _mapController.camera.zoom;
          _mapController.move(viewPoints.first, zoom);
        }
      } catch (_) {
        // Falha transitória de controller em rebuild; próxima revisão refaz.
      }
    });
  }

  bool _isInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  LatLng _centroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(-23, -46);
    var lat = 0.0;
    var lon = 0.0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  void _refreshFromDatabase() {
    setState(() => _refreshTick++);
    AppFeedback.warning('Atualizando dados da Home...');
  }

  void _syncAuthenticatedSession({
    required String authKey,
  }) {
    if (_lastReadyAuthKey != authKey) {
      _lastReadyAuthKey = authKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MapFilterService>().clearAll();
      });
    }
  }

  String _utcDayKeyNow() {
    final now = DateTime.now().toUtc();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  void _scheduleTelemetryRetentionCleanup(List<DeviceModel> devices) {
    final today = _utcDayKeyNow();
    if (_lastTelemetryRetentionCleanupDayKey == today) return;
    _lastTelemetryRetentionCleanupDayKey = today;

    final ids = devices
        .map((d) {
          final candidate = (d.deviceId ?? '').trim();
          if (candidate.isNotEmpty) return candidate;
          return d.id.trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    unawaited(
      context.read<CloudService>().cleanupTelemetryRetentionForDevices(ids),
    );
  }

  void _resetNorthUp() {
    _mapController.rotate(0);
  }

  void _centerOnUser() {
    final user = _userPosition;
    if (user == null) {
      AppFeedback.warning('Localizacao do dispositivo indisponivel.');
      return;
    }
    final zoom =
        _mapController.camera.zoom < 16 ? 16.0 : _mapController.camera.zoom;
    _mapController.move(user, zoom);
  }

  Future<bool> _confirmDelete(
    BuildContext context, {
    required String targetLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar exclusao'),
        content: Text('Deseja realmente apagar $targetLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showActionError(Object error) {
    AppFeedback.error('Falha na operacao: $error');
  }

  bool _isLikelyMatrixGateway(Map<String, dynamic> gateway) {
    final explicit = gateway['is_matrix'] ?? gateway['isMatrix'];
    if (explicit is bool) return explicit;

    final kind = (gateway['kind'] ?? '').toString().toLowerCase();
    if (kind == 'gateway_matrix' || kind == 'matrix') return true;

    final gatewayId =
        (gateway['gatewayId'] ?? gateway['id'] ?? '').toString().toUpperCase();
    if (gatewayId.startsWith('RT-M-')) return true;

    final name = (gateway['name'] ?? '').toString().toLowerCase();
    return name.contains('matriz');
  }

  Future<void> _openSelectedPolygonEditor(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final areaId = _selectedAreaId;
    final propertyId = _selectedPropertyId;
    if (areaId == null && propertyId == null) return;

    if (areaId != null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AreaEditorScreen(
            initialArea: <String, dynamic>{
              'id': areaId,
              'propertyId': _selectedAreaPropertyId,
              'perimeter': _selectedPolygonPoints,
              'linkedDeviceIds': _selectedAreaLinkedDeviceIds,
            },
          ),
        ),
      );
      if (ok == true && mounted) {
        setState(() {
          _selectedAreaId = null;
          _selectedAreaPropertyId = null;
          _selectedAreaLinkedDeviceIds = const <String>[];
          _selectedPolygonAnchor = null;
          _selectedPolygonPoints = const [];
        });
      }
      return;
    }

    if (propertyId != null) {
      final properties =
          await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
      if (!context.mounted) return;
      final property = properties.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p?['id']?.toString() == propertyId,
            orElse: () => null,
          );
      if (property == null) {
        if (context.mounted) {
          AppFeedback.error('Propriedade nao encontrada para edicao.');
        }
        return;
      }

      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RuralPropertyEditorScreen(initialProperty: property),
        ),
      );
      if (ok == true && context.mounted) {
        setState(() {
          _selectedPropertyId = null;
          _selectedAreaPropertyId = null;
          _selectedPolygonAnchor = null;
          _selectedPolygonPoints = const [];
        });
      }
    }
  }

  Future<void> _showEditDeviceDialog(
      BuildContext context, DeviceModel device) async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    final gateways =
        await fb.streamGateways(uid: uid, isAdmin: auth.isAdmin).first;
    final users = auth.isAdmin
        ? await fb.getUserOptions()
        : const <Map<String, String>>[];
    if (!context.mounted) return;
    String? propertyId = device.propertyId;
    String? selectedGatewayId = device.gatewayId;
    String? ownerUid = device.ownerUid;
    LatLng? selectedPosition = (device.lat != null && device.lon != null)
        ? LatLng(device.lat!, device.lon!)
        : null;
    final ownerOptions = users
        .where((u) => (u['uid'] ?? '').isNotEmpty)
        .map((u) => Map<String, String>.from(u))
        .toList();
    if (ownerUid == null || ownerUid.isEmpty) {
      ownerUid = ownerOptions.isNotEmpty ? ownerOptions.first['uid'] : uid;
    }
    if (ownerUid != null && ownerOptions.every((u) => u['uid'] != ownerUid)) {
      ownerOptions.insert(0, {
        'uid': ownerUid,
        'email': ownerUid,
      });
    }

    final nameCtrl = TextEditingController(text: device.name);
    final statusCtrl = TextEditingController(text: device.status);
    final loraIdCtrl = TextEditingController(
      text: (() {
        final raw = (device.deviceId ?? '').trim();
        if (raw.isNotEmpty) return raw;
        return device.loraDeviceId ?? '';
      })(),
    );
    bool wifiOtaEnabled = device.wifiOtaEnabled;
    final formKey = GlobalKey<FormState>();

    String? normalizeLoraDeviceId(String? raw) {
      if (raw == null) return null;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final parsed = int.tryParse(trimmed);
      if (parsed == null || parsed <= 0) return null;
      return parsed.toString();
    }

    List<Map<String, dynamic>> gatewaysForProperty(String? selectedPropertyId) {
      final normalizedProperty = _normalizeRefId(selectedPropertyId);
      if (normalizedProperty.isEmpty) {
        return gateways;
      }
      return gateways.where((g) {
        final gatewayProperty = _normalizeRefId(g['propertyId']);
        return gatewayProperty == normalizedProperty;
      }).toList();
    }

    String gatewayLabel(Map<String, dynamic> gateway) {
      final id = _normalizeRefId(gateway['id']);
      final name = (gateway['name'] ?? '').toString().trim();
      if (name.isEmpty) return id;
      return '$name ($id)';
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Editar coleira'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (_) {
                      final availableGateways = gatewaysForProperty(propertyId);
                      final hasSelectedGateway =
                          (selectedGatewayId ?? '').trim().isNotEmpty;
                      final selectedGatewayInList = hasSelectedGateway &&
                          availableGateways.any(
                            (g) =>
                                _normalizeRefId(g['id']) ==
                                _normalizeRefId(selectedGatewayId),
                          );

                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            key: const Key('edit_device_property_dropdown'),
                            initialValue: propertyId,
                            items: properties
                                .map(
                                  (p) => DropdownMenuItem<String>(
                                    value: p['id'].toString(),
                                    child:
                                        Text((p['name'] ?? p['id']).toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              propertyId = v;
                              final stillAvailable = gatewaysForProperty(v).any(
                                (g) =>
                                    _normalizeRefId(g['id']) ==
                                    _normalizeRefId(selectedGatewayId),
                              );
                              if (!stillAvailable) {
                                selectedGatewayId = null;
                              }
                            }),
                            decoration: const InputDecoration(
                              labelText: 'Propriedade rural',
                            ),
                          ),
                          DropdownButtonFormField<String>(
                            key: const Key('edit_device_gateway_dropdown'),
                            initialValue:
                                hasSelectedGateway ? selectedGatewayId : null,
                            items: <DropdownMenuItem<String>>[
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Sem gateway vinculado'),
                              ),
                              if (hasSelectedGateway && !selectedGatewayInList)
                                DropdownMenuItem<String>(
                                  value: selectedGatewayId,
                                  child: Text(
                                    'Gateway atual (${selectedGatewayId!})',
                                  ),
                                ),
                              ...availableGateways.map(
                                (g) => DropdownMenuItem<String>(
                                  value: _normalizeRefId(g['id']),
                                  child: Text(gatewayLabel(g)),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(
                              () => selectedGatewayId =
                                  (v == null || v.trim().isEmpty) ? null : v,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Gateway vinculado',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (ownerOptions.isEmpty)
                    TextFormField(
                      initialValue: ownerUid ?? uid,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Usuario dono (email)',
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('edit_device_owner_dropdown'),
                      initialValue: ownerUid,
                      items: ownerOptions
                          .map(
                            (u) => DropdownMenuItem<String>(
                              value: u['uid'],
                              child: Text(u['email'] ?? u['uid'] ?? ''),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => ownerUid = v),
                      decoration: const InputDecoration(
                        labelText: 'Usuario dono (email)',
                      ),
                    ),
                  TextFormField(
                    key: const Key('edit_device_lora_id_input'),
                    controller: loraIdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ID LoRa da coleira',
                    ),
                    validator: (v) {
                      if (normalizeLoraDeviceId(v) == null) {
                        return 'Informe um ID LoRa numerico maior que zero';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    key: const Key('edit_device_name_input'),
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome da coleira'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o nome'
                        : null,
                  ),
                  TextFormField(
                    key: const Key('edit_device_status_input'),
                    controller: statusCtrl,
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  const SizedBox(height: 8),
                  if (auth.isAdmin)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: wifiOtaEnabled,
                      onChanged: (v) => setState(() => wifiOtaEnabled = v),
                      title: const Text('Modo LoRa-only'),
                      subtitle: Text(
                        wifiOtaEnabled
                            ? 'Desativado (Wi-Fi/BLE habilitados).'
                            : 'Ativado (Wi-Fi/BLE desligados).',
                      ),
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Modo LoRa-only'),
                      subtitle: Text(
                        wifiOtaEnabled ? 'Desativado' : 'Ativado',
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on),
                    title: const Text('Posicao da coleira'),
                    subtitle: Text(
                      selectedPosition == null
                          ? 'Nenhuma posicao selecionada'
                          : '${selectedPosition!.latitude.toStringAsFixed(6)}, ${selectedPosition!.longitude.toStringAsFixed(6)}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final selectedProperty =
                            properties.cast<Map<String, dynamic>?>().firstWhere(
                                  (p) => p?['id'].toString() == propertyId,
                                  orElse: () => null,
                                );
                        final picked = await Navigator.push<LatLng>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapPointPickerScreen(
                              initial: selectedPosition,
                              propertyPolygon:
                                  _polygonFromProperty(selectedProperty),
                            ),
                          ),
                        );
                        if (picked != null) {
                          setState(() => selectedPosition = picked);
                        }
                      },
                      child: const Text('Selecionar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (auth.isAdmin)
              TextButton(
                onPressed: () async {
                  final confirm =
                      await _confirmDelete(context, targetLabel: 'a coleira');
                  if (!confirm) return;
                  try {
                    await fb.deleteDevice(id: device.id);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    if (!context.mounted) return;
                    _showActionError(e);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Apagar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('edit_device_save_button'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPosition == null) return;
                final normalizedLoraId = normalizeLoraDeviceId(loraIdCtrl.text);
                if (normalizedLoraId == null) {
                  if (context.mounted) {
                    AppFeedback.error(
                      'Informe um ID LoRa numerico maior que zero para a coleira.',
                    );
                  }
                  return;
                }
                final modeChanged = wifiOtaEnabled != device.wifiOtaEnabled;
                await fb.updateDevice(
                  id: device.id,
                  deviceId: normalizedLoraId,
                  name: nameCtrl.text.trim(),
                  status: statusCtrl.text.trim(),
                  lat: selectedPosition!.latitude,
                  lon: selectedPosition!.longitude,
                  ownerUid: ownerUid ?? uid,
                  propertyId: propertyId,
                  gatewayId: selectedGatewayId,
                  wifiOtaEnabled: wifiOtaEnabled,
                );
                if (auth.isAdmin && modeChanged) {
                  var queuedToMatrix = false;
                  final targetPropertyId =
                      (propertyId ?? device.propertyId)?.trim();
                  if (targetPropertyId == null || targetPropertyId.isEmpty) {
                    if (context.mounted) {
                      AppFeedback.warning(
                        'A coleira precisa estar vinculada a uma propriedade para receber SET_PARAMS via matriz.',
                      );
                    }
                  } else {
                    try {
                      await fb.enqueueScopedCommand(
                        command: 'SET_PARAMS',
                        propertyId: targetPropertyId,
                        requestedByUid: uid,
                        requestedByRole: auth.role,
                        targetDeviceIds: <String>[normalizedLoraId],
                        payload: {
                          'target': 'collars',
                          'wifi_ota_enabled': wifiOtaEnabled,
                          'requested_by_role': 'adm',
                          'requested_by_admin': true,
                        },
                        ttl: const Duration(minutes: 10),
                      );
                      queuedToMatrix = true;
                    } catch (e) {
                      if (context.mounted) {
                        AppFeedback.warning(
                          'Nao foi possivel enfileirar SET_PARAMS para a coleira: $e',
                        );
                      }
                    }
                  }
                  if (queuedToMatrix && context.mounted && mounted) {
                    AppFeedback.success(
                      'Modo salvo e comando enfileirado para envio via matriz.',
                    );
                  }
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditGatewayDialog(
      BuildContext context, Map<String, dynamic> gateway) async {
    final auth = context.read<AuthService>();
    final fb = context.read<CloudService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    if (!context.mounted) return;
    String? propertyId = gateway['propertyId']?.toString();
    LatLng? selectedPosition = (gateway['lat'] is num && gateway['lon'] is num)
        ? LatLng(
            (gateway['lat'] as num).toDouble(),
            (gateway['lon'] as num).toDouble(),
          )
        : null;

    final nameCtrl =
        TextEditingController(text: (gateway['name'] ?? '').toString());
    final statusCtrl =
        TextEditingController(text: (gateway['status'] ?? 'active').toString());
    final hostCtrl =
        TextEditingController(text: (gateway['host'] ?? '').toString());
    bool wifiOtaEnabled = gateway['wifi_ota_enabled'] is bool
        ? gateway['wifi_ota_enabled'] as bool
        : true;
    bool isMatrix = _isLikelyMatrixGateway(gateway);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Editar gateway'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('edit_gateway_property_dropdown'),
                    initialValue: propertyId,
                    items: properties
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p['id'].toString(),
                            child: Text((p['name'] ?? p['id']).toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => propertyId = v),
                    decoration:
                        const InputDecoration(labelText: 'Propriedade rural'),
                  ),
                  TextFormField(
                    key: const Key('edit_gateway_name_input'),
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome do gateway'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o nome'
                        : null,
                  ),
                  TextFormField(
                    key: const Key('edit_gateway_status_input'),
                    controller: statusCtrl,
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  TextFormField(
                    key: const Key('edit_gateway_host_input'),
                    controller: hostCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Host (opcional)'),
                  ),
                  if (auth.isAdmin)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isMatrix,
                      onChanged: (v) => setState(() => isMatrix = v),
                      title: const Text('Gateway matriz'),
                      subtitle: const Text(
                        'Ative para identificar este gateway como matriz.',
                      ),
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tipo de gateway'),
                      subtitle: Text(isMatrix ? 'Matriz' : 'Comum'),
                    ),
                  const SizedBox(height: 8),
                  if (auth.isAdmin)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: wifiOtaEnabled,
                      onChanged: (v) => setState(() => wifiOtaEnabled = v),
                      title: const Text('Modo LoRa-only'),
                      subtitle: Text(
                        wifiOtaEnabled
                            ? 'Desativado (Wi-Fi/BLE habilitados).'
                            : 'Ativado (Wi-Fi/BLE desligados).',
                      ),
                    )
                  else
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Modo LoRa-only'),
                      subtitle: Text(
                        wifiOtaEnabled ? 'Desativado' : 'Ativado',
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on),
                    title: const Text('Posicao do gateway'),
                    subtitle: Text(
                      selectedPosition == null
                          ? 'Nenhuma posicao selecionada'
                          : '${selectedPosition!.latitude.toStringAsFixed(6)}, ${selectedPosition!.longitude.toStringAsFixed(6)}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final selectedProperty =
                            properties.cast<Map<String, dynamic>?>().firstWhere(
                                  (p) => p?['id'].toString() == propertyId,
                                  orElse: () => null,
                                );
                        final picked = await Navigator.push<LatLng>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapPointPickerScreen(
                              initial: selectedPosition,
                              propertyPolygon:
                                  _polygonFromProperty(selectedProperty),
                            ),
                          ),
                        );
                        if (picked != null) {
                          setState(() => selectedPosition = picked);
                        }
                      },
                      child: const Text('Selecionar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (auth.isAdmin)
              TextButton(
                onPressed: () async {
                  final confirm =
                      await _confirmDelete(context, targetLabel: 'o gateway');
                  if (!confirm) return;
                  try {
                    await fb.deleteGateway(id: gateway['id'].toString());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    if (!context.mounted) return;
                    _showActionError(e);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Apagar'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('edit_gateway_save_button'),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPosition == null) return;
                final modeChanged = wifiOtaEnabled !=
                    ((gateway['wifi_ota_enabled'] is bool)
                        ? gateway['wifi_ota_enabled'] as bool
                        : true);
                await fb.updateGateway(
                  id: gateway['id'].toString(),
                  name: nameCtrl.text.trim(),
                  status: statusCtrl.text.trim(),
                  host: hostCtrl.text.trim().isEmpty
                      ? null
                      : hostCtrl.text.trim(),
                  propertyId: propertyId,
                  lat: selectedPosition!.latitude,
                  lon: selectedPosition!.longitude,
                  wifiOtaEnabled: wifiOtaEnabled,
                  isMatrix: isMatrix,
                );
                if (auth.isAdmin && modeChanged) {
                  final targetPropertyId = propertyId?.trim();
                  if (targetPropertyId == null || targetPropertyId.isEmpty) {
                    if (context.mounted) {
                      AppFeedback.warning(
                        'O gateway precisa estar vinculado a uma propriedade para receber SET_PARAMS via matriz.',
                      );
                    }
                  } else {
                    try {
                      await fb.enqueueScopedCommand(
                        command: 'SET_PARAMS',
                        propertyId: targetPropertyId,
                        requestedByUid: uid,
                        requestedByRole: auth.role,
                        targetGatewayIds: <String>[gateway['id'].toString()],
                        payload: {
                          'target': 'gateway',
                          'wifi_ota_enabled': wifiOtaEnabled,
                          'requested_by_role': 'adm',
                          'requested_by_admin': true,
                        },
                        ttl: const Duration(minutes: 10),
                      );
                      if (context.mounted) {
                        AppFeedback.success(
                          'Modo salvo e comando enfileirado para o gateway via matriz.',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppFeedback.warning(
                          'Nao foi possivel enfileirar SET_PARAMS para o gateway: $e',
                        );
                      }
                    }
                  }
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDeviceMarkerActions(
      BuildContext context, DeviceModel device) async {
    final networkId = device.networkId;
    final liveTelemetry = _latestTelemetryByDeviceId[device.id];
    final lat = liveTelemetry?.lat ?? device.lat;
    final lon = liveTelemetry?.lon ?? device.lon;
    final lastSeenMs = liveTelemetry?.receivedAtMs ??
        device.telemetryReceivedAtMs ??
        device.positionReceivedAtMs;
    final online = lastSeenMs != null &&
        DateTime.now().millisecondsSinceEpoch - lastSeenMs < 5 * 60 * 1000;

    final entries = <RTTelemetryEntry>[
      RTTelemetryEntry(
        label: 'Coordenadas',
        value: _formatCoordPair(lat, lon),
        emphasis: true,
      ),
      RTTelemetryEntry(
        label: 'Última telemetria',
        value: _formatRelativeFromMs(lastSeenMs),
      ),
      if (device.hasDailyHealth)
        RTTelemetryEntry(
          label: 'Sat / HDOP',
          value:
              '${device.healthSatellites ?? '-'} · ${device.healthHdop?.toStringAsFixed(2) ?? '-'}',
        ),
      if (device.hasDailyHealth && device.healthTemperatureC != null)
        RTTelemetryEntry(
          label: 'Temperatura',
          value: '${device.healthTemperatureC!.toStringAsFixed(1)} °C',
        ),
    ];

    await showRTCollarSheet(
      context,
      sheet: RTCollarSheet(
        title: device.name,
        subtitle: 'ID $networkId',
        online: online,
        lastSeenLabel: lastSeenMs == null
            ? 'Sem registros'
            : 'Visto ${_formatRelativeFromMs(lastSeenMs)}',
        entries: entries,
        actions: [
          RTCollarSheetAction(
            icon: Icons.tune,
            label: 'Comandos',
            variant: RTButtonVariant.primary,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeviceDetailsScreen(device: device),
                ),
              );
            },
          ),
          RTCollarSheetAction(
            icon: Icons.edit_outlined,
            label: 'Editar',
            onTap: () async {
              Navigator.of(context).pop();
              await _showEditDeviceDialog(context, device);
            },
          ),
        ],
      ),
    );
  }

  String _formatCoordPair(double? lat, double? lon) {
    if (lat == null || lon == null) return 'Sem posição';
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  String _formatRelativeFromMs(int? ms) {
    if (ms == null || ms <= 0) return 'sem dados';
    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inSeconds < 60) return 'há poucos segundos';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    return 'há ${diff.inDays} d';
  }

  Future<void> _openGatewayMarkerActions(
      BuildContext context, Map<String, dynamic> gateway) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('Editar gateway'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _showEditGatewayDialog(context, gateway);
          },
        ),
      ),
    );
  }

  Future<void> _showAddDeviceDialog(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCollarScreen()),
    );
  }

  Future<void> _showAddGatewayDialog(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddGatewayScreen()),
    );
  }

  Future<void> _showUpdateRoleDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final emailCtrl = TextEditingController();
    String role = 'adm';

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Vincular adm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('role_update_email_input'),
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email do usuario'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('role_update_role_dropdown'),
                initialValue: role,
                items: const [
                  DropdownMenuItem(value: 'adm', child: Text('adm')),
                  DropdownMenuItem(value: 'user', child: Text('user')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => role = v);
                },
                decoration: const InputDecoration(labelText: 'Perfil'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              key: const Key('role_update_save_button'),
              onPressed: () async {
                final targetEmail = emailCtrl.text.trim();
                if (targetEmail.isEmpty) return;
                try {
                  await auth.updateRoleByEmail(targetEmail, role);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  AppFeedback.error(e.toString());
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    context.watch<GatewayService>();
    final filters = context.watch<MapFilterService>();
    final uid = auth.user?.uid;
    final authKey = resolveHomeAuthKey(uid: uid, role: auth.role);

    if (shouldShowBlockingHomeLoader(
      uid: uid,
      isProfileLoading: auth.isProfileLoading,
      lastReadyAuthKey: _lastReadyAuthKey,
    )) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (authKey == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final currentUid = uid!;

    _syncAuthenticatedSession(authKey: authKey);
    _updateStreamsIfNeeded(uid: currentUid, isAdmin: auth.isAdmin);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        key: ValueKey('props-$currentUid-$_refreshTick'),
        stream: _propertiesStream,
        builder: (context, propsSnap) {
          final propertiesError = propsSnap.error;
          return StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('areas-$currentUid-$_refreshTick'),
            stream: _areasStream,
            builder: (context, areasSnap) {
              final areasError = areasSnap.error;
              return StreamBuilder<List<DeviceModel>>(
                key: ValueKey('devices-$currentUid-$_refreshTick'),
                stream: _devicesStream,
                builder: (context, devicesSnap) {
                  final devicesError = devicesSnap.error;
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _gatewaysStream,
                    builder: (context, gatewaySnap) {
                      final gatewaysError = gatewaySnap.error;
                      final derivedHomeIssues = <String>[];
                      final homeIssues = collectHomeLoadIssues(
                        propertiesError: propertiesError,
                        areasError: areasError,
                        devicesError: devicesError,
                        gatewaysError: gatewaysError,
                      ).toList(growable: true);
                      final allProperties = propsSnap.data ?? const [];
                      final allAreas = areasSnap.data ?? const [];
                      final allDevices =
                          devicesSnap.data ?? const <DeviceModel>[];
                      final allGateways = gatewaySnap.data ?? const [];
                      _latestKnownDevices = allDevices;
                      _mergeTelemetryCacheFromDevices(allDevices);
                      _scheduleTelemetryRetentionCleanup(allDevices);

                      final selectedPropertyIds = Set<String>.from(
                        filters.propertyIds.map(_normalizeRefId),
                      );
                      final selectedAreaIds = Set<String>.from(
                        filters.areaIds.map(_normalizeRefId),
                      );
                      final selectedCollarIds = Set<String>.from(
                        filters.collarIds.map(_normalizeRefId),
                      );
                      final selectedGatewayIds = Set<String>.from(
                        filters.gatewayIds.map(_normalizeRefId),
                      );

                      final resolvedPropertyIds = <String>{};
                      if (filters.hasAnyFilter) {
                        resolvedPropertyIds.addAll(selectedPropertyIds);

                        for (final a in allAreas) {
                          final areaId = _normalizeRefId(a['id']);
                          if (!selectedAreaIds.contains(areaId)) continue;
                          final propertyId = _normalizeRefId(a['propertyId']);
                          if (propertyId.isNotEmpty) {
                            resolvedPropertyIds.add(propertyId);
                          }
                        }

                        for (final d in allDevices) {
                          if (!selectedCollarIds.contains(d.id)) continue;
                          final propertyId = _normalizeRefId(d.propertyId);
                          if (propertyId.isNotEmpty) {
                            resolvedPropertyIds.add(propertyId);
                          }
                        }

                        for (final g in allGateways) {
                          final gatewayId = _normalizeRefId(g['id']);
                          if (!selectedGatewayIds.contains(gatewayId)) continue;
                          final propertyId = _normalizeRefId(g['propertyId']);
                          if (propertyId.isNotEmpty) {
                            resolvedPropertyIds.add(propertyId);
                          }
                        }
                      }

                      final hasResolvedProperties =
                          resolvedPropertyIds.isNotEmpty;

                      final properties = !filters.hasAnyFilter
                          ? allProperties
                          : allProperties.where((p) {
                              final id = _normalizeRefId(p['id']);
                              if (hasResolvedProperties) {
                                return id.isNotEmpty &&
                                    resolvedPropertyIds.contains(id);
                              }
                              return selectedPropertyIds.contains(id);
                            }).toList();

                      final filteredAreas = !filters.hasAnyFilter
                          ? allAreas
                          : allAreas.where((a) {
                              final areaId = _normalizeRefId(a['id']);
                              final propertyId =
                                  _normalizeRefId(a['propertyId']);
                              if (hasResolvedProperties &&
                                  propertyId.isNotEmpty &&
                                  resolvedPropertyIds.contains(propertyId)) {
                                return true;
                              }
                              return selectedAreaIds.contains(areaId);
                            }).toList();

                      final devices = !filters.hasAnyFilter
                          ? allDevices
                          : allDevices.where((d) {
                              final propertyId = _normalizeRefId(d.propertyId);
                              if (hasResolvedProperties &&
                                  propertyId.isNotEmpty &&
                                  resolvedPropertyIds.contains(propertyId)) {
                                return true;
                              }
                              return selectedCollarIds.contains(d.id);
                            }).toList();

                      final gateways = !filters.hasAnyFilter
                          ? allGateways
                          : allGateways.where((g) {
                              final gatewayId = _normalizeRefId(g['id']);
                              final propertyId =
                                  _normalizeRefId(g['propertyId']);
                              if (hasResolvedProperties &&
                                  propertyId.isNotEmpty &&
                                  resolvedPropertyIds.contains(propertyId)) {
                                return true;
                              }
                              return selectedGatewayIds.contains(gatewayId);
                            }).toList();

                      final markers = <Marker>[];
                      final polygons = <Polygon>[];
                      final areaLabelMarkers = <Marker>[];
                      try {
                        markers.addAll(
                          devices.map((d) {
                            final position = _resolvedMarkerTelemetryForDevice(
                              d,
                              devices: allDevices,
                            );
                            if (position == null) {
                              return null;
                            }
                            final freshness = resolveTelemetryFreshness(d);
                            final iconColor = switch (freshness) {
                              TelemetryFreshness.fresh => Colors.green,
                              TelemetryFreshness.stale => Colors.red,
                              TelemetryFreshness.unknown => Colors.grey,
                            };
                            return Marker(
                              point: position.point,
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () => _openDeviceMarkerActions(context, d),
                                child: Icon(
                                  Icons.pets,
                                  color: iconColor,
                                  size: 30,
                                ),
                              ),
                            );
                          }).whereType<Marker>(),
                        );

                        for (final g in gateways) {
                          final point = _gatewayMarkerPoint(g);
                          if (point == null) continue;
                          markers.add(
                            Marker(
                              point: point,
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () =>
                                    _openGatewayMarkerActions(context, g),
                                child: const Icon(
                                  Icons.wifi,
                                  color: Colors.blue,
                                  size: 30,
                                ),
                              ),
                            ),
                          );
                        }

                        for (final a in filteredAreas) {
                          final raw = (a['perimeter'] as List?) ?? const [];
                          final latLngs =
                              raw.map(_toLatLng).whereType<LatLng>().toList();
                          if (latLngs.length < 3) continue;
                          polygons.add(
                            Polygon(
                              points: latLngs,
                              color: Colors.teal.withValues(alpha: 0.22),
                              borderColor: Colors.teal,
                              borderStrokeWidth: 3,
                            ),
                          );
                          final placement =
                              PolygonMetrics.labelPlacement(latLngs);
                          areaLabelMarkers.add(
                            Marker(
                              point: placement.anchor,
                              width: 126,
                              height: 48,
                              child: IgnorePointer(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.58),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.black12,
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    PolygonMetrics.areaTextMultiline(latLngs),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        for (final p in properties) {
                          final points = (p['points'] as List?) ?? const [];
                          final latLngs =
                              points.map(_toLatLng).whereType<LatLng>().toList();
                          if (latLngs.length < 3) continue;
                          polygons.add(
                            Polygon(
                              points: latLngs,
                              color: Colors.orange.withValues(alpha: 0.25),
                              borderColor: Colors.orange.shade700,
                              borderStrokeWidth: 3,
                            ),
                          );
                          final placement =
                              PolygonMetrics.labelPlacement(latLngs);
                          areaLabelMarkers.add(
                            Marker(
                              point: placement.anchor,
                              width: 126,
                              height: 48,
                              child: IgnorePointer(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.58),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.black12,
                                      width: 0.6,
                                    ),
                                  ),
                                  child: Text(
                                    PolygonMetrics.areaTextMultiline(latLngs),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        derivedHomeIssues.add(
                          'Falha ao processar os dados do mapa. Registros inválidos foram ignorados.',
                        );
                      }
                      homeIssues.addAll(derivedHomeIssues);

                      void selectPolygonAt(LatLng tapPoint) {
                        for (final a in filteredAreas) {
                          final raw = (a['perimeter'] as List?) ?? const [];
                          final pts =
                              raw.map(_toLatLng).whereType<LatLng>().toList();
                          if (pts.length < 3) continue;
                          if (_isInsidePolygon(tapPoint, pts)) {
                            final propertyId =
                                (a['propertyId'] ?? '').toString();
                            setState(() {
                              _selectedAreaId = a['id'].toString();
                              _selectedAreaPropertyId = propertyId;
                              _selectedAreaLinkedDeviceIds =
                                  ((a['linkedDeviceIds'] as List?) ??
                                          const <dynamic>[])
                                      .map((entry) => entry.toString().trim())
                                      .where((entry) => entry.isNotEmpty)
                                      .toList();
                              _selectedPropertyId = null;
                              _selectedPolygonPoints = pts;
                              _selectedPolygonAnchor = _centroid(pts);
                            });
                            return;
                          }
                        }
                        for (final p in properties) {
                          final raw = (p['points'] as List?) ?? const [];
                          final pts =
                              raw.map(_toLatLng).whereType<LatLng>().toList();
                          if (pts.length < 3) continue;
                          if (_isInsidePolygon(tapPoint, pts)) {
                            setState(() {
                              _selectedPropertyId = p['id'].toString();
                              _selectedAreaId = null;
                              _selectedAreaPropertyId = null;
                              _selectedAreaLinkedDeviceIds = const <String>[];
                              _selectedPolygonPoints = pts;
                              _selectedPolygonAnchor = _centroid(pts);
                            });
                            return;
                          }
                        }
                        setState(() {
                          _selectedPropertyId = null;
                          _selectedAreaId = null;
                          _selectedAreaPropertyId = null;
                          _selectedAreaLinkedDeviceIds = const <String>[];
                          _selectedPolygonPoints = const [];
                          _selectedPolygonAnchor = null;
                        });
                      }

                      final viewPoints = _collectViewPoints(
                          properties, filteredAreas, markers);
                      final hasFilteredFocusTargets =
                          filters.hasAnyFilter && viewPoints.isNotEmpty;
                      _applyFilterViewportIfNeeded(
                        filters: filters,
                        viewPoints: viewPoints,
                      );
                      final countryCenter =
                          _userPosition ?? const LatLng(-14.2350, -51.9253);
                      final center = hasFilteredFocusTargets
                          ? viewPoints.first
                          : countryCenter;
                      final fitBounds =
                          hasFilteredFocusTargets && viewPoints.length >= 2
                              ? LatLngBounds.fromPoints(viewPoints)
                              : null;
                      final initialZoom = hasFilteredFocusTargets
                          ? 14.0
                          : _countryOverviewZoom(center.latitude);

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: center,
                                initialZoom: initialZoom,
                                initialCameraFit: fitBounds == null
                                    ? null
                                    : CameraFit.bounds(
                                        bounds: fitBounds,
                                        padding: const EdgeInsets.all(40),
                                      ),
                                onTap: (_, p) => selectPolygonAt(p),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c'],
                                  userAgentPackageName: ManualSettings
                                      .mapUserAgentPackageName,
                                ),
                                PolygonLayer(polygons: polygons),
                                MarkerLayer(markers: areaLabelMarkers),
                                MarkerLayer(markers: markers),
                                if (_userPosition != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _userPosition!,
                                        width: 42,
                                        height: 42,
                                        child: Transform.rotate(
                                          angle: _userHeading *
                                              (math.pi / 180.0),
                                          child: const Icon(
                                            Icons.navigation,
                                            color: Colors.blue,
                                            size: 34,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_selectedPolygonAnchor != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(
                                          _selectedPolygonAnchor!.latitude,
                                          _selectedPolygonAnchor!.longitude +
                                              0.00025,
                                        ),
                                        width: 40,
                                        height: 40,
                                        child: FloatingActionButton.small(
                                          heroTag: 'edit-polygon',
                                          onPressed: () =>
                                              _openSelectedPolygonEditor(
                                                  context),
                                          child: const Icon(Icons.edit),
                                        ),
                                      ),
                                    ],
                                  ),
                                const Scalebar(
                                  alignment: Alignment.bottomRight,
                                  padding: EdgeInsets.only(
                                    right: 12,
                                    bottom: 12,
                                  ),
                                  lineColor: Colors.white54,
                                  textStyle: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              bottom: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 12, 16, 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _MapSearchBar(
                                            count: devices.length +
                                                gateways.length,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const _NotifBell(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  RTFilterChips(
                                    chips: [
                                      RTFilterChipData(
                                        id: 'all',
                                        label: 'Todos',
                                        icon: Icons.layers_outlined,
                                        count: devices.length +
                                            gateways.length,
                                      ),
                                      RTFilterChipData(
                                        id: 'collars',
                                        label: 'Coleiras',
                                        count: devices.length,
                                      ),
                                      RTFilterChipData(
                                        id: 'gateways',
                                        label: 'Gateways',
                                        icon: Icons.router_outlined,
                                        count: gateways.length,
                                      ),
                                    ],
                                    selectedIds: const {'all'},
                                    onToggle: (_) {},
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: 12,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _MapControlsStack(
                                onNorth: _resetNorthUp,
                                onLocate: _centerOnUser,
                              ),
                            ),
                          ),
                          if (homeIssues.isNotEmpty)
                            Positioned(
                              top: 140,
                              left: 12,
                              right: 64,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: RTColors.dangerSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: RTColors.danger
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.warning_amber_rounded,
                                        color: RTColors.danger,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        homeIssues.join('\n'),
                                        style: RTTypography.bodySmall
                                            .copyWith(
                                          color: RTColors.danger,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            right: 16,
                            bottom: 96,
                            child: _buildHomeFab(context, auth),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHomeFab(BuildContext context, AuthService auth) {
    final actions = <RTFabAction>[
      RTFabAction(
        icon: Icons.crop_free,
        label: 'Novo polígono',
        actionKey: const Key('home_action_new_area'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AreaEditorScreen()),
        ),
      ),
      RTFabAction(
        icon: Icons.route_outlined,
        label: 'Solicitar arrebanhamento',
        actionKey: const Key('home_action_start_herding'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HerdingScreen()),
        ),
      ),
      if (auth.isAdmin)
        RTFabAction(
          icon: Icons.pets_outlined,
          label: 'Incluir coleira',
          actionKey: const Key('home_action_add_collar'),
          onTap: () => _showAddDeviceDialog(context),
        ),
      if (auth.isAdmin)
        RTFabAction(
          icon: Icons.wifi,
          label: 'Incluir gateway',
          actionKey: const Key('home_action_add_gateway'),
          onTap: () => _showAddGatewayDialog(context),
        ),
      if (auth.isAdmin)
        RTFabAction(
          icon: Icons.sync_problem_outlined,
          label: 'Reparar estado cloud',
          actionKey: const Key('home_action_repair_cloud_state'),
          tone: RTColors.warn,
          onTap: () async {
            try {
              final result = await context
                  .read<CloudService>()
                  .repairCloudState(apply: true);
              if (!context.mounted) return;
              AppFeedback.success(
                'Estado cloud reparado: propriedades=${result['propertyCount'] ?? 0}, gateways=${result['gatewayCount'] ?? 0}.',
              );
            } catch (e) {
              if (!context.mounted) return;
              AppFeedback.error(_repairCloudStateErrorMessage(e));
            }
          },
        ),
      if (auth.isAdmin)
        RTFabAction(
          icon: Icons.landscape_outlined,
          label: 'Incluir propriedade rural',
          actionKey: const Key('home_action_add_property'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RuralPropertyEditorScreen(),
            ),
          ),
        ),
      if (auth.isAdmin)
        RTFabAction(
          icon: Icons.admin_panel_settings_outlined,
          label: 'Vincular adm',
          actionKey: const Key('home_action_update_role'),
          onTap: () => _showUpdateRoleDialog(context),
        ),
    ];

    return RTFab(
      fabKey: const Key('home_open_actions_button'),
      label: 'Novo',
      icon: Icons.add,
      actions: actions,
    );
  }
}

class _MapSearchBar extends StatelessWidget {
  const _MapSearchBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: RTColors.bg.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.hair),
        boxShadow: RTElevation.sh1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: RTColors.inkMute),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Buscar propriedade…',
                style: RTTypography.body.copyWith(color: RTColors.inkMute),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: RTColors.bgAlt,
                borderRadius: BorderRadius.circular(RTRadius.rFull),
              ),
              child: Text(
                '$count',
                style: RTTypography.mono.copyWith(fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 18, color: RTColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _NotifBell extends StatelessWidget {
  const _NotifBell();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: RTColors.bg.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.hair),
        boxShadow: RTElevation.sh1,
      ),
      child: Icon(
        Icons.notifications_outlined,
        size: 22,
        color: RTColors.inkSoft,
      ),
    );
  }
}

class _MapControlsStack extends StatelessWidget {
  const _MapControlsStack({
    required this.onNorth,
    required this.onLocate,
  });

  final VoidCallback onNorth;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlBtn(Icons.layers_outlined, 'Camadas', () {}),
        _controlBtn(Icons.my_location, 'Centralizar', onLocate),
        _controlBtn(Icons.explore_outlined, 'Norte', onNorth),
      ],
    );
  }

  Widget _controlBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: RTColors.bg,
            borderRadius: BorderRadius.circular(RTRadius.r3),
            border: Border.all(color: RTColors.hair),
            boxShadow: RTElevation.sh1,
          ),
          child: Icon(icon, size: 22, color: RTColors.inkSoft),
        ),
      ),
    );
  }
}
