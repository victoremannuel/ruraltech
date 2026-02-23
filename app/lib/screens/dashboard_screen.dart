import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/bluetooth_discovery_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';
import '../services/map_filter_service.dart';
import '../utils/polygon_metrics.dart';
import 'area_editor_screen.dart';
import 'events_screen.dart';
import 'map_point_picker_screen.dart';
import 'polygon_editor_screen.dart';
import 'profile_screen.dart';
import 'rural_property_editor_screen.dart';

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
  GatewayService? _boundGatewayService;
  LatLng? _userPosition;
  double _userHeading = 0;
  bool _initialCountryViewApplied = false;
  int _lastAppliedFilterRevision = -1;
  int _lastAppliedFilterSignature = 0;
  String? _lastAuthKey;
  bool _ranLegacyBackfill = false;
  String? _lastTelemetryRetentionCleanupDayKey;
  String? _selectedAreaId;
  String? _selectedPropertyId;
  LatLng? _selectedPolygonAnchor;
  List<LatLng> _selectedPolygonPoints = const [];
  List<LatLng> _selectedPolygonBoundary = const [];

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
    _mapController.dispose();
    super.dispose();
  }

  void _bindGatewayTelemetryStream() {
    final gateway = context.read<GatewayService>();
    if (identical(_boundGatewayService, gateway)) return;
    _boundGatewayService = gateway;
    _gatewayTelemetrySub?.cancel();
    _gatewayTelemetrySub = gateway.telemetryStream.listen((sample) {
      if (!mounted) return;
      if (sample.gatewayWifiOtaEnabled == false) {
        // Em LoRa-only o escritor principal deve ser o gateway matriz.
        return;
      }
      unawaited(
        context.read<FirebaseService>().registerLiveTelemetry(
              deviceId: sample.deviceId,
              lat: sample.lat,
              lon: sample.lon,
              sourceTimestampSec: sample.sourceTimestampSec,
              seq: sample.seq,
              gatewayId: sample.gatewayId,
              gatewayRole: sample.gatewayRole,
              gatewayWifiOtaEnabled: sample.gatewayWifiOtaEnabled,
              sourceType: sample.sourceType ?? 'telemetry',
              writer: 'app',
              receivedAtMs: sample.receivedAtMs,
            ),
      );
    });
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
      _applyInitialCountryViewportIfPossible();
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
      _applyInitialCountryViewportIfPossible();
    });
    _startCompassTracking();
  }

  double _countryOverviewZoom(double latitude) {
    final absLat = latitude.abs();
    if (absLat >= 55) return 2.4;
    if (absLat >= 35) return 2.7;
    return 2.9;
  }

  void _applyInitialCountryViewportIfPossible() {
    if (_initialCountryViewApplied) return;
    final user = _userPosition;
    if (user == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialCountryViewApplied) return;
      final hasFilters = context.read<MapFilterService>().hasAnyFilter;
      if (hasFilters) return;
      try {
        _mapController.move(user, _countryOverviewZoom(user.latitude));
        _initialCountryViewApplied = true;
      } catch (_) {}
    });
  }

  LatLng? _toLatLng(dynamic value) {
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    if (value is List && value.length >= 2) {
      final a = value[0];
      final b = value[1];
      if (a is num && b is num) return LatLng(a.toDouble(), b.toDouble());
      if (a is GeoPoint) return LatLng(a.latitude, a.longitude);
    }
    if (value is Map) {
      final lat = value['lat'] ?? value['latitude'];
      final lng = value['lng'] ?? value['lon'] ?? value['longitude'];
      if (lat is num && lng is num) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Atualizando dados da Home...')),
    );
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
      context.read<FirebaseService>().cleanupTelemetryRetentionForDevices(ids),
    );
  }

  void _resetNorthUp() {
    _mapController.rotate(0);
  }

  void _centerOnUser() {
    final user = _userPosition;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Localizacao do dispositivo indisponivel.')),
      );
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

  void _showActionError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Falha na operacao: $error')),
    );
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

  String? _normalizeWsHost(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('ws://') || value.startsWith('wss://')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return null;
      return 'ws://${uri.host}:81';
    }
    if (value.contains('://')) return null;
    if (value.contains(':')) return 'ws://$value';
    return 'ws://$value:81';
  }

  Future<void> _openSelectedPolygonEditor(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final areaId = _selectedAreaId;
    final propertyId = _selectedPropertyId;
    if (areaId == null && propertyId == null) return;

    if (areaId != null) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PolygonEditorScreen(
            title: 'Editar area',
            initialPoints: _selectedPolygonPoints,
            boundary: _selectedPolygonBoundary,
            maxPoints: GatewayService.maxPolygonPoints,
            onDelete: () => fb.deleteArea(id: areaId),
            deleteLabel: 'Apagar area',
            onSave: (points) =>
                fb.updateAreaPerimeter(id: areaId, perimeter: points),
          ),
        ),
      );
      if (ok == true && mounted) {
        setState(() {
          _selectedAreaId = null;
          _selectedPolygonAnchor = null;
          _selectedPolygonPoints = const [];
          _selectedPolygonBoundary = const [];
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Propriedade nao encontrada para edicao.'),
            ),
          );
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
          _selectedPolygonAnchor = null;
          _selectedPolygonPoints = const [];
        });
      }
    }
  }

  Future<void> _showEditDeviceDialog(
      BuildContext context, DeviceModel device) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final gatewayService = context.read<GatewayService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    final users = auth.isAdmin
        ? await fb.getUserOptions()
        : const <Map<String, String>>[];
    if (!context.mounted) return;
    String? propertyId = device.propertyId;
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
    bool wifiOtaEnabled = device.wifiOtaEnabled;
    final formKey = GlobalKey<FormState>();

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
                  DropdownButtonFormField<String>(
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
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome da coleira'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o nome'
                        : null,
                  ),
                  TextFormField(
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
                    _showActionError(context, e);
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
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPosition == null) return;
                final modeChanged = wifiOtaEnabled != device.wifiOtaEnabled;
                await fb.updateDevice(
                  id: device.id,
                  name: nameCtrl.text.trim(),
                  status: statusCtrl.text.trim(),
                  lat: selectedPosition!.latitude,
                  lon: selectedPosition!.longitude,
                  ownerUid: ownerUid ?? uid,
                  propertyId: propertyId,
                  wifiOtaEnabled: wifiOtaEnabled,
                );
                if (auth.isAdmin && modeChanged) {
                  final loraTarget = (() {
                    final d = (device.deviceId ?? '').trim();
                    if (d.isNotEmpty) return d;
                    return device.id.trim();
                  })();
                  if (int.tryParse(loraTarget) == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Modo salvo no cadastro, mas o ID LoRa da coleira nao e numerico para enviar SET_PARAMS.',
                          ),
                        ),
                      );
                    }
                  } else {
                    final ok =
                        await gatewayService.sendCommandEnsuringConnection(
                      deviceId: loraTarget,
                      command: 'SET_PARAMS',
                      payload: {
                        'target': 'collars',
                        'wifi_ota_enabled': wifiOtaEnabled,
                        'requested_by_role': 'adm',
                        'requested_by_admin': true,
                      },
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Nao foi possivel enviar comando de modo para a coleira via gateway: ${gatewayService.lastError ?? 'erro desconhecido'}',
                          ),
                        ),
                      );
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

  Future<void> _showEditGatewayDialog(
      BuildContext context, Map<String, dynamic> gateway) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final gatewayService = context.read<GatewayService>();
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
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Nome do gateway'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Informe o nome'
                        : null,
                  ),
                  TextFormField(
                    controller: statusCtrl,
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                  TextFormField(
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
                    _showActionError(context, e);
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
                  final persistedHost = (gateway['host'] ?? '').toString();
                  final wsHost = _normalizeWsHost(
                    hostCtrl.text.trim().isEmpty
                        ? persistedHost
                        : hostCtrl.text,
                  );
                  final ok = await gatewayService.sendCommandEnsuringConnection(
                    deviceId: '0',
                    command: 'SET_PARAMS',
                    hostOverride: wsHost,
                    payload: {
                      'target': 'gateway',
                      'wifi_ota_enabled': wifiOtaEnabled,
                      'requested_by_role': 'adm',
                      'requested_by_admin': true,
                    },
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Nao foi possivel enviar comando de modo para o gateway: ${gatewayService.lastError ?? 'erro desconhecido'}',
                        ),
                      ),
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

  Future<void> _showAddDeviceDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final gatewayService = context.read<GatewayService>();
    final bleService = context.read<BluetoothDiscoveryService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    if (!bleService.isScanning) {
      unawaited(bleService.startScan());
    }

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    final users = auth.isAdmin
        ? await fb.getUserOptions()
        : const <Map<String, String>>[];
    if (!context.mounted) return;
    String? propertyId =
        properties.isNotEmpty ? properties.first['id'].toString() : null;
    LatLng? selectedPosition;
    String? selectedDetectedDeviceId;
    bool manualPositionChosen = false;
    final ownerOptions = users
        .where((u) => (u['uid'] ?? '').isNotEmpty)
        .map((u) => Map<String, String>.from(u))
        .toList();

    final Map<String, String> selectedOwner = auth.isAdmin
        ? ownerOptions.firstWhere(
            (u) => (u['uid'] ?? '') == uid,
            orElse: () => ownerOptions.isNotEmpty ? ownerOptions.first : {},
          )
        : {
            'uid': uid,
            'email': ((auth.user?.email ?? '').trim().isNotEmpty)
                ? auth.user!.email!.trim().toLowerCase()
                : uid,
          };
    String? selectedOwnerUid = (selectedOwner['uid'] ?? '').trim().isEmpty
        ? uid
        : selectedOwner['uid'];
    final ownerCtrl = TextEditingController(
      text: (selectedOwner['email'] ?? selectedOwnerUid ?? uid),
    );
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final formKey = GlobalKey<FormState>();

    void selectOwner(Map<String, String> owner) {
      selectedOwnerUid = owner['uid'];
      ownerCtrl.text = (owner['email'] ?? owner['uid'] ?? '').trim();
      ownerCtrl.selection =
          TextSelection.collapsed(offset: ownerCtrl.text.length);
    }

    Future<void> showOwnerPicker(
      BuildContext dialogContext,
      void Function(VoidCallback fn) dialogSetState,
    ) async {
      var query = '';
      final selected = await showDialog<Map<String, String>>(
        context: dialogContext,
        builder: (pickerContext) => StatefulBuilder(
          builder: (pickerContext, pickerSetState) {
            final matches = ownerOptions.where((u) {
              final email = (u['email'] ?? '').trim().toLowerCase();
              return query.isEmpty || email.contains(query);
            }).toList();
            return AlertDialog(
              title: const Text('Selecionar dono da coleira'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por email',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) =>
                          pickerSetState(() => query = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: matches.isEmpty
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Nenhum email encontrado.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: matches.length,
                              itemBuilder: (_, i) {
                                final owner = matches[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                      owner['email'] ?? owner['uid'] ?? ''),
                                  onTap: () =>
                                      Navigator.pop(pickerContext, owner),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(pickerContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        ),
      );
      if (selected == null) return;
      dialogSetState(() => selectOwner(selected));
    }

    String mergeSource(String? current, String next) {
      final out = <String>{};
      if (current != null && current.isNotEmpty) {
        out.addAll(
          current.split('+').map((s) => s.trim()).where((s) => s.isNotEmpty),
        );
      }
      out.add(next);
      final ordered = <String>[];
      for (final preferred in const ['wifi', 'ble']) {
        if (out.remove(preferred)) ordered.add(preferred);
      }
      ordered.addAll(out);
      return ordered.join('+');
    }

    double? toFiniteCoord(dynamic value) {
      if (value is num) {
        final out = value.toDouble();
        return out.isFinite ? out : null;
      }
      if (value is String) {
        final out = double.tryParse(value.trim());
        if (out == null || !out.isFinite) return null;
        return out;
      }
      return null;
    }

    LatLng? positionFromDetectedCollar(
      String? detectedId,
      List<Map<String, dynamic>> discovered,
    ) {
      if (detectedId == null || detectedId.trim().isEmpty) return null;
      Map<String, dynamic>? found;
      for (final item in discovered) {
        if (item['device_id_str']?.toString() == detectedId) {
          found = item;
          break;
        }
      }
      if (found == null) return null;
      final lat = toFiniteCoord(found['lat']);
      final lon = toFiniteCoord(found['lon']);
      if (lat == null || lon == null) return null;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
      return LatLng(lat, lon);
    }

    List<Map<String, dynamic>> mergedDiscoveredCollars() {
      final byId = <String, Map<String, dynamic>>{};

      for (final lora in gatewayService.discoveredCollars) {
        final id = lora['device_id_str']?.toString();
        if (id == null || id.isEmpty) continue;
        byId[id] = {
          ...lora,
          'device_id_str': id,
          'source_type': 'wifi',
        };
      }

      for (final ble in bleService.discoveredCollars) {
        final id = ble['device_id_str']?.toString();
        if (id == null || id.isEmpty) continue;
        final current = byId[id];
        if (current == null) {
          byId[id] = {
            ...ble,
            'device_id_str': id,
            'source_type': 'ble',
          };
          continue;
        }

        current['source_type'] =
            mergeSource(current['source_type']?.toString(), 'ble');
        final bleLat = toFiniteCoord(ble['lat']);
        final bleLon = toFiniteCoord(ble['lon']);
        if (current['lat'] == null && bleLat != null) {
          current['lat'] = bleLat;
        }
        if (current['lon'] == null && bleLon != null) {
          current['lon'] = bleLon;
        }
        if ((current['name']?.toString().trim() ?? '').isEmpty &&
            (ble['name']?.toString().trim() ?? '').isNotEmpty) {
          current['name'] = ble['name'];
        }
        byId[id] = current;
      }

      final out = byId.values.toList();
      out.sort((a, b) => (a['device_id_str'] as String)
          .compareTo(b['device_id_str'] as String));
      return out;
    }

    String collarSourceLabel(Map<String, dynamic> d) {
      final source = (d['source_type'] ?? '').toString();
      if (source == 'wifi+ble' || source == 'ble+wifi') return 'Wi-Fi+BLE';
      if (source == 'wifi') return 'Wi-Fi';
      if (source == 'ble') return 'BLE';
      return source;
    }

    void applyDetectedCollar(Map<String, dynamic> detected) {
      final detectedId = detected['device_id_str']?.toString();
      if (detectedId == null || detectedId.isEmpty) return;
      selectedDetectedDeviceId = detectedId;
      if (nameCtrl.text.trim().isEmpty ||
          nameCtrl.text.startsWith('Coleira ')) {
        final suggested = detected['name']?.toString().trim();
        nameCtrl.text = (suggested == null || suggested.isEmpty)
            ? 'Coleira $detectedId'
            : suggested;
      }
      final lat = toFiniteCoord(detected['lat']);
      final lon = toFiniteCoord(detected['lon']);
      if (lat != null &&
          lon != null &&
          lat >= -90 &&
          lat <= 90 &&
          lon >= -180 &&
          lon <= 180) {
        selectedPosition = LatLng(lat, lon);
        manualPositionChosen = false;
      } else if (!manualPositionChosen) {
        // Evita reaproveitar coordenada antiga de outra coleira detectada.
        selectedPosition = null;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AnimatedBuilder(
          animation: Listenable.merge([gatewayService, bleService]),
          builder: (context, _) {
            final discoveredCollars = mergedDiscoveredCollars();

            return AlertDialog(
              title: const Text('Incluir coleira'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (auth.isAdmin)
                        TextFormField(
                          controller: ownerCtrl,
                          readOnly: true,
                          onTap: () => showOwnerPicker(context, setState),
                          decoration: const InputDecoration(
                            labelText: 'Dono da coleira (email)',
                            helperText:
                                'Toque para abrir a lista e pesquisar por email',
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          validator: (_) {
                            if (selectedOwnerUid == null ||
                                selectedOwnerUid!.trim().isEmpty) {
                              return 'Selecione o dono da coleira';
                            }
                            return null;
                          },
                        )
                      else
                        TextFormField(
                          controller: ownerCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Dono da coleira (email)',
                          ),
                        ),
                      DropdownButtonFormField<String>(
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
                        decoration: const InputDecoration(
                            labelText: 'Propriedade rural'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Selecione a propriedade rural'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Vinculacao da coleira (Bluetooth/Wi-Fi)',
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Opcional: vincule a coleira detectada por Bluetooth ou via Wi-Fi na rede local. '
                              'Se preferir, apenas selecione o ponto no mapa manualmente.',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: bleService.isScanning
                                  ? null
                                  : () => bleService.startScan(),
                              icon: Icon(
                                bleService.isScanning
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_searching,
                              ),
                              label: Text(
                                bleService.isScanning
                                    ? 'Buscando coleira...'
                                    : 'Buscar coleira por Bluetooth',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Wi-Fi (rede local)',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  gatewayService.isDiscoveringCollars
                                      ? 'Buscando coleiras na rede local...'
                                      : (gatewayService.isConnected
                                          ? 'Gateway conectado para descoberta Wi-Fi'
                                          : 'Descoberta Wi-Fi direta (sem gateway)'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                OutlinedButton.icon(
                                  onPressed: gatewayService.isDiscoveringCollars
                                      ? null
                                      : () async {
                                          await gatewayService
                                              .requestCollarDiscovery();
                                        },
                                  icon: Icon(
                                    gatewayService.isDiscoveringCollars
                                        ? Icons.wifi_tethering
                                        : (gatewayService.isConnected
                                            ? Icons.wifi
                                            : Icons.wifi_off),
                                  ),
                                  label: Text(
                                    gatewayService.isDiscoveringCollars
                                        ? 'Buscando...'
                                        : 'Buscar coleira por Wi-Fi',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if ((bleService.lastError ?? '').isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'BLE: ${bleService.lastError}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      if ((gatewayService.lastError ?? '').isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Wi-Fi: ${gatewayService.lastError}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDetectedDeviceId ?? '',
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(
                            value: '',
                            child:
                                Text('Nao vincular agora (usar mapa manual)'),
                          ),
                          ...discoveredCollars.map(
                            (d) => DropdownMenuItem<String>(
                              value: d['device_id_str']?.toString() ?? '',
                              child: Text(
                                () {
                                  final extras = <String>[];
                                  final src = collarSourceLabel(d);
                                  if (src.isNotEmpty) extras.add(src);
                                  final lat = toFiniteCoord(d['lat']);
                                  final lon = toFiniteCoord(d['lon']);
                                  if (lat != null && lon != null) {
                                    extras.add('GPS');
                                  }
                                  if (extras.isEmpty) {
                                    return 'Coleira ${d['device_id_str']}';
                                  }
                                  return 'Coleira ${d['device_id_str']} (${extras.join(', ')})';
                                }(),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == null || v.isEmpty) {
                            selectedDetectedDeviceId = null;
                            if (!manualPositionChosen) {
                              selectedPosition = null;
                            }
                            return;
                          }
                          final detected = discoveredCollars
                              .cast<Map<String, dynamic>?>()
                              .firstWhere(
                                (d) => d?['device_id_str']?.toString() == v,
                                orElse: () => null,
                              );
                          if (detected == null) return;
                          applyDetectedCollar(detected);
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Coleira detectada (Bluetooth/Wi-Fi)',
                        ),
                      ),
                      if (discoveredCollars.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            'Nenhuma coleira detectada ainda. Continue no modo manual ou tente Bluetooth/Wi-Fi.',
                          ),
                        ),
                      TextFormField(
                        controller: nameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Nome da coleira'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o nome'
                            : null,
                      ),
                      TextFormField(
                        controller: statusCtrl,
                        decoration: const InputDecoration(labelText: 'Status'),
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
                            final selectedProperty = properties
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
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
                              setState(() {
                                selectedPosition = picked;
                                manualPositionChosen = true;
                              });
                            }
                          },
                          child: const Text('Selecionar'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Obrigatorio escolher uma opcao: ponto manual no mapa ou vinculacao por Bluetooth/Wi-Fi.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedOwnerUid == null ||
                        selectedOwnerUid!.trim().isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Selecione um dono valido para a coleira.',
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    final hasBinding = selectedDetectedDeviceId != null &&
                        selectedDetectedDeviceId!.trim().isNotEmpty;
                    final liveDetectedPosition = hasBinding
                        ? positionFromDetectedCollar(
                            selectedDetectedDeviceId,
                            discoveredCollars,
                          )
                        : null;
                    final effectivePosition = manualPositionChosen
                        ? selectedPosition
                        : (liveDetectedPosition ?? selectedPosition);
                    if (!hasBinding && effectivePosition == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Selecione ponto no mapa ou vincule uma coleira detectada (Bluetooth/Wi-Fi).',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    if (hasBinding && effectivePosition == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Coleira vinculada sem coordenadas GPS. Aguarde a telemetria da coleira ou selecione o ponto manualmente.',
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    await fb.addDevice(
                      ownerUid: selectedOwnerUid ?? uid,
                      name: nameCtrl.text.trim(),
                      status: statusCtrl.text.trim(),
                      deviceId:
                          hasBinding ? selectedDetectedDeviceId!.trim() : null,
                      lat: effectivePosition?.latitude,
                      lon: effectivePosition?.longitude,
                      propertyId: propertyId,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAddGatewayDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final gatewayService = context.read<GatewayService>();
    final bleService = context.read<BluetoothDiscoveryService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    if (!gatewayService.isConnected) {
      gatewayService.connect();
    }
    unawaited(bleService.startScan());

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    if (!context.mounted) return;
    String? propertyId =
        properties.isNotEmpty ? properties.first['id'].toString() : null;
    String propertyLabel(Map<String, dynamic> property) =>
        (property['name'] ?? property['id']).toString();
    Map<String, dynamic>? findPropertyById(String? id) {
      if (id == null || id.trim().isEmpty) return null;
      return properties.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p?['id'].toString() == id,
            orElse: () => null,
          );
    }

    LatLng? selectedPosition;
    List<Map<String, dynamic>> networkDiscoveredGateways = [];
    final connectedGateway = gatewayService.connectedGatewayCandidate;
    if (connectedGateway != null) {
      networkDiscoveredGateways = [connectedGateway];
    }
    String? selectedDetectedGatewayId = networkDiscoveredGateways.isNotEmpty
        ? networkDiscoveredGateways.first['gateway_id']?.toString()
        : null;
    bool scanningNearbyGateways = false;
    final gatewayIdCtrl =
        TextEditingController(text: selectedDetectedGatewayId ?? '');
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final hostCtrl =
        TextEditingController(text: ManualSettings.defaultGatewayWsHost);
    final propertyCtrl = TextEditingController(
      text: findPropertyById(propertyId) == null
          ? ''
          : propertyLabel(findPropertyById(propertyId)!),
    );
    bool isMatrix = false;
    final formKey = GlobalKey<FormState>();

    void syncPropertyController(String? id) {
      final selectedProperty = findPropertyById(id);
      propertyCtrl.text =
          selectedProperty == null ? '' : propertyLabel(selectedProperty);
      propertyCtrl.selection =
          TextSelection.collapsed(offset: propertyCtrl.text.length);
    }

    String mergeSource(String? current, String next) {
      if (current == null || current.isEmpty) return next;
      if (current == next) return current;
      final parts = current.split('+');
      if (parts.contains(next)) return current;
      if ((current == 'network' && next == 'ble') ||
          (current == 'ble' && next == 'network')) {
        return 'network+ble';
      }
      return '$current+$next';
    }

    List<Map<String, dynamic>> mergedDiscoveredGateways() {
      final byId = <String, Map<String, dynamic>>{};

      for (final net in networkDiscoveredGateways) {
        final id = net['gateway_id']?.toString();
        if (id == null || id.isEmpty) continue;
        byId[id] = {
          ...net,
          'gateway_id': id,
          'source_type': 'network',
        };
      }

      for (final ble in bleService.discoveredGateways) {
        final id = ble['gateway_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final current = byId[id];
        if (current == null) {
          byId[id] = {
            ...ble,
            'gateway_id': id,
            'source_type': 'ble',
          };
          continue;
        }

        current['source_type'] =
            mergeSource(current['source_type']?.toString(), 'ble');
        final ws = ble['host_ws']?.toString();
        if ((current['host_ws']?.toString().trim() ?? '').isEmpty &&
            ws != null &&
            ws.isNotEmpty) {
          current['host_ws'] = ws;
        }
        if ((current['name']?.toString().trim() ?? '').isEmpty &&
            (ble['name']?.toString().trim() ?? '').isNotEmpty) {
          current['name'] = ble['name'];
        }
        byId[id] = current;
      }

      final out = byId.values.toList();
      out.sort(
        (a, b) =>
            (a['gateway_id'] as String).compareTo(b['gateway_id'] as String),
      );
      return out;
    }

    String gatewaySourceLabel(Map<String, dynamic> g) {
      final source = (g['source_type'] ?? '').toString();
      if (source == 'network+ble' || source == 'ble+network') {
        return 'Rede+BLE';
      }
      if (source == 'network') return 'Rede';
      if (source == 'ble') return 'BLE';
      return source;
    }

    void applyDetectedGateway(Map<String, dynamic> detected) {
      final gatewayId = detected['gateway_id']?.toString();
      if (gatewayId == null || gatewayId.isEmpty) return;
      selectedDetectedGatewayId = gatewayId;
      if (gatewayIdCtrl.text.trim().isEmpty ||
          gatewayIdCtrl.text.trim() == selectedDetectedGatewayId) {
        gatewayIdCtrl.text = gatewayId;
      }
      if (gatewayIdCtrl.text.trim().isEmpty) {
        gatewayIdCtrl.text = gatewayId;
      }
      final ws = detected['host_ws']?.toString();
      if (ws != null && ws.isNotEmpty) {
        hostCtrl.text = ws;
      }
      if (nameCtrl.text.trim().isEmpty || nameCtrl.text.startsWith('Gateway')) {
        nameCtrl.text = detected['name']?.toString() ?? 'Gateway $gatewayId';
      }
      final explicit = detected['is_matrix'] ?? detected['isMatrix'];
      if (explicit is bool) {
        isMatrix = explicit;
      } else {
        final kind = (detected['kind'] ?? '').toString().toLowerCase();
        if (kind == 'gateway_matrix' ||
            kind == 'matrix' ||
            gatewayId.toUpperCase().startsWith('RT-M-')) {
          isMatrix = true;
        }
      }
    }

    final initiallyDiscovered = mergedDiscoveredGateways();
    if (initiallyDiscovered.isNotEmpty) {
      applyDetectedGateway(initiallyDiscovered.first);
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AnimatedBuilder(
          animation: Listenable.merge([gatewayService, bleService]),
          builder: (context, _) {
            final discoveredGateways = mergedDiscoveredGateways();

            return AlertDialog(
              title: const Text('Incluir gateway'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownMenu<String>(
                        controller: propertyCtrl,
                        width: MediaQuery.of(context).size.width * 0.72,
                        requestFocusOnTap: true,
                        enableFilter: true,
                        enableSearch: true,
                        label: const Text('Propriedade rural'),
                        hintText: 'Digite para filtrar',
                        initialSelection: propertyId,
                        dropdownMenuEntries: properties
                            .map(
                              (p) => DropdownMenuEntry<String>(
                                value: p['id'].toString(),
                                label: propertyLabel(p),
                              ),
                            )
                            .toList(),
                        onSelected: (v) => setState(() {
                          propertyId = v;
                          syncPropertyController(v);
                        }),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            Text(
                              gatewayService.isConnected
                                  ? 'Gateway conectado'
                                  : 'Gateway desconectado',
                            ),
                            OutlinedButton.icon(
                              onPressed: gatewayService.connect,
                              icon: Icon(
                                gatewayService.isConnected
                                    ? Icons.wifi
                                    : Icons.wifi_off,
                              ),
                              label: Text(
                                gatewayService.isConnected
                                    ? 'Reconectar'
                                    : 'Conectar gateway',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: bleService.isScanning
                                  ? null
                                  : () => bleService.startScan(),
                              icon: Icon(
                                bleService.isScanning
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_searching,
                              ),
                              label: Text(
                                bleService.isScanning
                                    ? 'Buscando BLE...'
                                    : 'Buscar Bluetooth',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((bleService.lastError ?? '').isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'BLE: ${bleService.lastError}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: scanningNearbyGateways
                                  ? null
                                  : () async {
                                      setState(
                                          () => scanningNearbyGateways = true);
                                      final found = await gatewayService
                                          .discoverGatewaysOnLocalNetwork();
                                      if (!context.mounted) return;
                                      setState(() {
                                        scanningNearbyGateways = false;
                                        networkDiscoveredGateways = found;
                                        final connected = gatewayService
                                            .connectedGatewayCandidate;
                                        if (connected != null &&
                                            connected['gateway_id'] != null &&
                                            networkDiscoveredGateways.every(
                                              (g) =>
                                                  g['gateway_id']?.toString() !=
                                                  connected['gateway_id']
                                                      ?.toString(),
                                            )) {
                                          networkDiscoveredGateways = [
                                            connected,
                                            ...networkDiscoveredGateways,
                                          ];
                                        }
                                        final discoveredGateways =
                                            mergedDiscoveredGateways();
                                        if (discoveredGateways.isEmpty) return;
                                        final selected = discoveredGateways
                                            .cast<Map<String, dynamic>?>()
                                            .firstWhere(
                                              (g) =>
                                                  g?['gateway_id']
                                                      ?.toString() ==
                                                  selectedDetectedGatewayId,
                                              orElse: () => null,
                                            );
                                        applyDetectedGateway(
                                          selected ?? discoveredGateways.first,
                                        );
                                      });
                                    },
                              icon: const Icon(Icons.search),
                              label: const Text('Buscar gateways na rede'),
                            ),
                            if (scanningNearbyGateways)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDetectedGatewayId ?? '',
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem<String>(
                            value: '',
                            child:
                                Text('Nao vincular agora (usar mapa manual)'),
                          ),
                          ...discoveredGateways.map(
                            (g) => DropdownMenuItem<String>(
                              value: g['gateway_id']?.toString() ?? '',
                              child: Text(
                                () {
                                  final extras = <String>[];
                                  final src = gatewaySourceLabel(g);
                                  if (src.isNotEmpty) extras.add(src);
                                  final ip = g['ip']?.toString();
                                  if (ip != null && ip.isNotEmpty) {
                                    extras.add(ip);
                                  }
                                  if (extras.isEmpty) {
                                    return '${g['name'] ?? 'Gateway'}';
                                  }
                                  return '${g['name'] ?? 'Gateway'} (${extras.join(', ')})';
                                }(),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == null || v.isEmpty) {
                            selectedDetectedGatewayId = null;
                            return;
                          }
                          final detected = discoveredGateways
                              .cast<Map<String, dynamic>?>()
                              .firstWhere(
                                (g) => g?['gateway_id']?.toString() == v,
                                orElse: () => null,
                              );
                          if (detected == null) return;
                          applyDetectedGateway(detected);
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Gateway detectado (Wi-Fi/Bluetooth)',
                        ),
                      ),
                      if (discoveredGateways.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            'Nenhum gateway detectado ainda. Continue no modo manual ou tente Wi-Fi/Bluetooth.',
                          ),
                        ),
                      TextFormField(
                        controller: gatewayIdCtrl,
                        decoration:
                            const InputDecoration(labelText: 'ID do gateway'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o ID do gateway'
                            : null,
                      ),
                      TextFormField(
                        controller: nameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Nome do gateway'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o nome'
                            : null,
                      ),
                      TextFormField(
                        controller: statusCtrl,
                        decoration: const InputDecoration(labelText: 'Status'),
                      ),
                      TextFormField(
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
                            'Ative para cadastrar este gateway como matriz.',
                          ),
                        )
                      else
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Tipo de gateway'),
                          subtitle: Text(isMatrix ? 'Matriz' : 'Comum'),
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
                            final selectedProperty = properties
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
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
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Obrigatorio escolher uma opcao: ponto manual no mapa ou vinculacao por Wi-Fi/Bluetooth.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (propertyId == null || propertyId!.trim().isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Selecione a propriedade rural.'),
                          ),
                        );
                      }
                      return;
                    }
                    final hasBinding = selectedDetectedGatewayId != null &&
                        selectedDetectedGatewayId!.trim().isNotEmpty;
                    final hasManualPosition = selectedPosition != null;
                    if (!hasBinding && !hasManualPosition) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Selecione ponto no mapa ou vincule um gateway detectado (Wi-Fi/Bluetooth).',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    await fb.addGateway(
                      name: nameCtrl.text.trim(),
                      status: statusCtrl.text.trim(),
                      isMatrix: isMatrix,
                      gatewayId: hasBinding
                          ? selectedDetectedGatewayId!.trim()
                          : gatewayIdCtrl.text.trim(),
                      host: hostCtrl.text.trim().isEmpty
                          ? null
                          : hostCtrl.text.trim(),
                      propertyId: propertyId,
                      lat:
                          hasManualPosition ? selectedPosition!.latitude : null,
                      lon: hasManualPosition
                          ? selectedPosition!.longitude
                          : null,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        ),
      ),
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
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email do usuario'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
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
              onPressed: () async {
                final targetEmail = emailCtrl.text.trim();
                if (targetEmail.isEmpty) return;
                try {
                  await auth.updateRoleByEmail(targetEmail, role);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlusActions(BuildContext context) {
    final auth = context.read<AuthService>();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Novo poligono'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AreaEditorScreen()),
                );
              },
            ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.pets),
                title: const Text('Incluir coleira'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAddDeviceDialog(context);
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Incluir gateway'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAddGatewayDialog(context);
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.landscape),
                title: const Text('Incluir propriedade rural'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RuralPropertyEditorScreen(),
                    ),
                  );
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Vincular adm'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showUpdateRoleDialog(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final gateway = context.watch<GatewayService>();
    final filters = context.watch<MapFilterService>();
    final fb = context.read<FirebaseService>();
    final uid = auth.user?.uid;

    if (uid == null || auth.isProfileLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final authKey = '$uid-${auth.role}';
    if (_lastAuthKey != authKey) {
      _lastAuthKey = authKey;
      _ranLegacyBackfill = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MapFilterService>().clearAll();
      });
    }

    if (auth.isAdmin && !_ranLegacyBackfill) {
      _ranLegacyBackfill = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await fb.backfillLegacyAccessForAreasAndGateways();
        } catch (_) {
          // Best effort migration for legacy documents.
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Home (${auth.isAdmin ? 'adm' : 'user'})'),
        actions: [
          IconButton(icon: const Icon(Icons.wifi), onPressed: gateway.connect),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshFromDatabase,
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        key: ValueKey('props-$uid-${auth.role}-$_refreshTick'),
        stream: fb.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, propsSnap) {
          if (propsSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    Text('Erro ao carregar propriedades: ${propsSnap.error}'),
              ),
            );
          }
          return StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('areas-$uid-${auth.role}-$_refreshTick'),
            stream: fb.streamAreas(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, areasSnap) {
              if (areasSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Erro ao carregar areas: ${areasSnap.error}'),
                  ),
                );
              }
              return StreamBuilder<List<DeviceModel>>(
                key: ValueKey('devices-$uid-${auth.role}-$_refreshTick'),
                stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, devicesSnap) {
                  if (devicesSnap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                            'Erro ao carregar coleiras: ${devicesSnap.error}'),
                      ),
                    );
                  }
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('gws-$uid-${auth.role}-$_refreshTick'),
                    stream: fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                    builder: (context, gatewaySnap) {
                      if (gatewaySnap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                                'Erro ao carregar gateways: ${gatewaySnap.error}'),
                          ),
                        );
                      }
                      final allProperties = propsSnap.data ?? const [];
                      final allAreas = areasSnap.data ?? const [];
                      final allDevices =
                          devicesSnap.data ?? const <DeviceModel>[];
                      final allGateways = gatewaySnap.data ?? const [];
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

                      final markers = <Marker>[
                        ...devices
                            .where((d) => d.lat != null && d.lon != null)
                            .map(
                              (d) => Marker(
                                point: LatLng(d.lat!, d.lon!),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showEditDeviceDialog(context, d),
                                  child: const Icon(
                                    Icons.pets,
                                    color: Colors.red,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                        ...gateways
                            .where((g) => g['lat'] != null && g['lon'] != null)
                            .map(
                              (g) => Marker(
                                point: LatLng(
                                  (g['lat'] as num).toDouble(),
                                  (g['lon'] as num).toDouble(),
                                ),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () =>
                                      _showEditGatewayDialog(context, g),
                                  child: const Icon(
                                    Icons.wifi,
                                    color: Colors.blue,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                      ];

                      final polygons = <Polygon>[];
                      final areaLabelMarkers = <Marker>[];
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

                      void selectPolygonAt(LatLng tapPoint) {
                        for (final a in filteredAreas) {
                          final raw = (a['perimeter'] as List?) ?? const [];
                          final pts =
                              raw.map(_toLatLng).whereType<LatLng>().toList();
                          if (pts.length < 3) continue;
                          if (_isInsidePolygon(tapPoint, pts)) {
                            final propertyId =
                                (a['propertyId'] ?? '').toString();
                            final property = allProperties
                                .cast<Map<String, dynamic>?>()
                                .firstWhere(
                                  (p) => p?['id'].toString() == propertyId,
                                  orElse: () => null,
                                );
                            setState(() {
                              _selectedAreaId = a['id'].toString();
                              _selectedPropertyId = null;
                              _selectedPolygonPoints = pts;
                              _selectedPolygonBoundary =
                                  _polygonFromProperty(property);
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
                              _selectedPolygonPoints = pts;
                              _selectedPolygonBoundary = const [];
                              _selectedPolygonAnchor = _centroid(pts);
                            });
                            return;
                          }
                        }
                        setState(() {
                          _selectedPropertyId = null;
                          _selectedAreaId = null;
                          _selectedPolygonPoints = const [];
                          _selectedPolygonBoundary = const [];
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
                      final mapKey = ValueKey<String>(
                        'home-${filters.revision}-${properties.length}-${filteredAreas.length}-${markers.length}-${_userPosition == null ? 'n' : 'u'}-$_refreshTick',
                      );

                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            color: Colors.green.withValues(alpha: 0.08),
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              'Propriedades: ${properties.length} | Areas: ${filteredAreas.length} | Coleiras: ${devices.length} | Gateways: ${gateways.length}'
                              '${filters.hasAnyFilter ? ' (filtrado)' : ''}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Stack(
                              children: [
                                FlutterMap(
                                  key: mapKey,
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
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.example.ruraltechApp',
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
                                              _selectedPolygonAnchor!
                                                      .longitude +
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
                                  ],
                                ),
                                Positioned(
                                  left: 12,
                                  bottom: 12,
                                  child: Column(
                                    children: [
                                      FloatingActionButton.small(
                                        heroTag: 'north-up',
                                        onPressed: _resetNorthUp,
                                        child: const Icon(Icons.explore),
                                      ),
                                      const SizedBox(height: 8),
                                      FloatingActionButton.small(
                                        heroTag: 'center-user',
                                        onPressed: _centerOnUser,
                                        child: const Icon(Icons.my_location),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Acoes',
              onPressed: () => _openPlusActions(context),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Telemetria',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EventsScreen()),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Perfil',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
