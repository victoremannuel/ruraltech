import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

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
  LatLng? _userPosition;
  double _userHeading = 0;
  String? _lastAuthKey;
  bool _ranLegacyBackfill = false;
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
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
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
          _userHeading = current.heading;
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
        if (pos.heading.isFinite && pos.heading >= 0) {
          _userHeading = pos.heading;
        }
      });
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

  Future<void> _openSelectedPolygonEditor(BuildContext context) async {
    final fb = context.read<FirebaseService>();
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
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PolygonEditorScreen(
            title: 'Editar propriedade',
            initialPoints: _selectedPolygonPoints,
            onSave: (points) =>
                fb.updateRuralPropertyPolygon(id: propertyId, points: points),
          ),
        ),
      );
      if (ok == true && mounted) {
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
    final gatewayCtrl = TextEditingController();
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
                  TextFormField(
                    controller: gatewayCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Gateway ID (opcional)'),
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPosition == null) return;
                await fb.updateDevice(
                  id: device.id,
                  name: nameCtrl.text.trim(),
                  status: statusCtrl.text.trim(),
                  lat: selectedPosition!.latitude,
                  lon: selectedPosition!.longitude,
                  ownerUid: ownerUid ?? uid,
                  gatewayId: gatewayCtrl.text.trim().isEmpty
                      ? null
                      : gatewayCtrl.text.trim(),
                  propertyId: propertyId,
                );
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (selectedPosition == null) return;
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
                );
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
    if (!gatewayService.isConnected) {
      gatewayService.connect();
    }
    unawaited(bleService.startScan());

    final properties =
        await fb.getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    if (!context.mounted) return;
    String? propertyId =
        properties.isNotEmpty ? properties.first['id'].toString() : null;
    LatLng? selectedPosition;
    String? selectedDetectedDeviceId;

    final ownerCtrl = TextEditingController(text: uid);
    final deviceIdCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final gatewayCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String mergeSource(String? current, String next) {
      if (current == null || current.isEmpty) return next;
      if (current == next) return current;
      final parts = current.split('+');
      if (parts.contains(next)) return current;
      if ((current == 'lora' && next == 'ble') ||
          (current == 'ble' && next == 'lora')) {
        return 'lora+ble';
      }
      return '$current+$next';
    }

    List<Map<String, dynamic>> mergedDiscoveredCollars() {
      final byId = <String, Map<String, dynamic>>{};

      for (final lora in gatewayService.discoveredCollars) {
        final id = lora['device_id_str']?.toString();
        if (id == null || id.isEmpty) continue;
        byId[id] = {
          ...lora,
          'device_id_str': id,
          'source_type': 'lora',
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
        if (current['lat'] == null && ble['lat'] is num) {
          current['lat'] = ble['lat'];
        }
        if (current['lon'] == null && ble['lon'] is num) {
          current['lon'] = ble['lon'];
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
      if (source == 'lora+ble' || source == 'ble+lora') return 'LoRa+BLE';
      if (source == 'lora') return 'LoRa';
      if (source == 'ble') return 'BLE';
      return source;
    }

    void applyDetectedCollar(Map<String, dynamic> detected) {
      final detectedId = detected['device_id_str']?.toString();
      if (detectedId == null || detectedId.isEmpty) return;
      selectedDetectedDeviceId = detectedId;
      if (deviceIdCtrl.text.trim().isEmpty ||
          deviceIdCtrl.text.trim() == selectedDetectedDeviceId) {
        deviceIdCtrl.text = detectedId;
      }
      if (deviceIdCtrl.text.trim().isEmpty) {
        deviceIdCtrl.text = detectedId;
      }
      if (nameCtrl.text.trim().isEmpty ||
          nameCtrl.text.startsWith('Coleira ')) {
        final suggested = detected['name']?.toString().trim();
        nameCtrl.text = (suggested == null || suggested.isEmpty)
            ? 'Coleira $detectedId'
            : suggested;
      }
      if (detected['lat'] is num && detected['lon'] is num) {
        selectedPosition = LatLng(
          (detected['lat'] as num).toDouble(),
          (detected['lon'] as num).toDouble(),
        );
      }
    }

    final initiallyDiscovered = mergedDiscoveredCollars();
    if (initiallyDiscovered.isNotEmpty) {
      applyDetectedCollar(initiallyDiscovered.first);
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AnimatedBuilder(
          animation: Listenable.merge([gatewayService, bleService]),
          builder: (context, _) {
            final discoveredCollars = mergedDiscoveredCollars();
            final hasSelectedDetected = selectedDetectedDeviceId != null &&
                discoveredCollars.any(
                  (d) =>
                      d['device_id_str']?.toString() ==
                      selectedDetectedDeviceId,
                );
            if (!hasSelectedDetected && discoveredCollars.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                setState(() => applyDetectedCollar(discoveredCollars.first));
              });
            }

            return AlertDialog(
              title: const Text('Incluir coleira'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: ownerCtrl,
                        decoration:
                            const InputDecoration(labelText: 'UID dono'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o UID do usuario'
                            : null,
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
                      if (discoveredCollars.isNotEmpty)
                        DropdownButtonFormField<String>(
                          initialValue: hasSelectedDetected
                              ? selectedDetectedDeviceId
                              : discoveredCollars.first['device_id_str']
                                  ?.toString(),
                          items: discoveredCollars
                              .map(
                                (d) => DropdownMenuItem<String>(
                                  value: d['device_id_str']?.toString(),
                                  child: Text(
                                    () {
                                      final extras = <String>[];
                                      final src = collarSourceLabel(d);
                                      if (src.isNotEmpty) extras.add(src);
                                      if (d['lat'] is num && d['lon'] is num) {
                                        extras.add('GPS');
                                      }
                                      if (extras.isEmpty) {
                                        return 'Coleira ${d['device_id_str']}';
                                      }
                                      return 'Coleira ${d['device_id_str']} (${extras.join(', ')})';
                                    }(),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            if (v == null) return;
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
                            labelText: 'Coleira detectada (LoRa/BLE)',
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            'Nenhuma coleira detectada ainda. Use Bluetooth ou aguarde telemetria LoRa.',
                          ),
                        ),
                      TextFormField(
                        controller: deviceIdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'ID da coleira (LoRa)'),
                        validator: (v) {
                          final raw = (v ?? '').trim();
                          if (raw.isEmpty) return 'Informe o ID da coleira';
                          if (int.tryParse(raw) == null) {
                            return 'ID deve ser numerico';
                          }
                          return null;
                        },
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
                      TextFormField(
                        controller: gatewayCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Gateway ID (opcional)'),
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (selectedPosition == null) return;
                    await fb.addDevice(
                      ownerUid: ownerCtrl.text.trim(),
                      name: nameCtrl.text.trim(),
                      status: statusCtrl.text.trim(),
                      deviceId: deviceIdCtrl.text.trim(),
                      lat: selectedPosition!.latitude,
                      lon: selectedPosition!.longitude,
                      gatewayId: gatewayCtrl.text.trim().isEmpty
                          ? null
                          : gatewayCtrl.text.trim(),
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

    final ownerCtrl = TextEditingController(text: uid);
    final gatewayIdCtrl =
        TextEditingController(text: selectedDetectedGatewayId ?? '');
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final hostCtrl = TextEditingController(text: 'ws://192.168.4.1:81');
    final formKey = GlobalKey<FormState>();

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
            final hasSelectedDetected = selectedDetectedGatewayId != null &&
                discoveredGateways.any(
                  (g) =>
                      g['gateway_id']?.toString() == selectedDetectedGatewayId,
                );
            if (!hasSelectedDetected && discoveredGateways.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                setState(() => applyDetectedGateway(discoveredGateways.first));
              });
            }

            return AlertDialog(
              title: const Text('Incluir gateway'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: ownerCtrl,
                        decoration:
                            const InputDecoration(labelText: 'UID dono'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Informe o UID do usuario'
                            : null,
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
                      if (discoveredGateways.isNotEmpty)
                        DropdownButtonFormField<String>(
                          initialValue: hasSelectedDetected
                              ? selectedDetectedGatewayId
                              : discoveredGateways.first['gateway_id']
                                  ?.toString(),
                          items: discoveredGateways
                              .map(
                                (g) => DropdownMenuItem<String>(
                                  value: g['gateway_id']?.toString(),
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
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            if (v == null) return;
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
                            labelText: 'Gateway detectado',
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 2),
                          child: Text(
                            'Nenhum gateway detectado ainda. Use rede local, Bluetooth ou informe o ID manualmente.',
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
                    if (selectedPosition == null) return;
                    await fb.addGateway(
                      ownerUid: ownerCtrl.text.trim(),
                      name: nameCtrl.text.trim(),
                      status: statusCtrl.text.trim(),
                      gatewayId: gatewayIdCtrl.text.trim(),
                      host: hostCtrl.text.trim().isEmpty
                          ? null
                          : hostCtrl.text.trim(),
                      propertyId: propertyId,
                      lat: selectedPosition!.latitude,
                      lon: selectedPosition!.longitude,
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

                      final properties = filters.propertyIds.isEmpty
                          ? allProperties
                          : allProperties
                              .where(
                                  (p) => filters.propertyIds.contains(p['id']))
                              .toList();
                      final devices = filters.collarIds.isEmpty
                          ? allDevices
                          : allDevices
                              .where((d) => filters.collarIds.contains(d.id))
                              .toList();
                      final gateways = filters.gatewayIds.isEmpty
                          ? allGateways
                          : allGateways
                              .where(
                                  (g) => filters.gatewayIds.contains(g['id']))
                              .toList();
                      final areas = filters.propertyIds.isEmpty
                          ? allAreas
                          : allAreas
                              .where((a) => filters.propertyIds.contains(
                                    (a['propertyId'] ?? '').toString(),
                                  ))
                              .toList();
                      final filteredAreas = filters.areaIds.isEmpty
                          ? areas
                          : areas
                              .where(
                                (a) => filters.areaIds
                                    .contains(a['id'].toString()),
                              )
                              .toList();

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
                      final center = viewPoints.isNotEmpty
                          ? viewPoints.first
                          : const LatLng(-23.0, -46.0);
                      final fitBounds = viewPoints.length >= 2
                          ? LatLngBounds.fromPoints(viewPoints)
                          : null;
                      final mapKey = ValueKey<String>(
                        'home-${filters.revision}-${properties.length}-${filteredAreas.length}-${markers.length}-$_refreshTick',
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
                                    initialZoom: 14,
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
