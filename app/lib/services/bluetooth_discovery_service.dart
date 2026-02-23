import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothDiscoveryService extends ChangeNotifier {
  static const int manufacturerId = 0x1234;
  static const List<int> _signature = [0x52, 0x54, 0x42, 0x31]; // RTB1
  static const String ruraltechServiceUuid =
      '7f920001-0a26-4d09-a606-0cfef4f9a1f0';

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  Timer? _scanTimer;

  final Map<String, Map<String, dynamic>> _byKey = {};
  bool _initialized = false;

  bool isScanning = false;
  String? lastError;
  DateTime? lastScanAt;

  List<Map<String, dynamic>> get discoveredCollars {
    final items = _byKey.values
        .where((d) => d['kind'] == 'collar' && _isEligibleForOnboarding(d))
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    items.sort((a, b) =>
        (a['device_id_str'] as String).compareTo(b['device_id_str'] as String));
    return items;
  }

  List<Map<String, dynamic>> get discoveredGateways {
    final items = _byKey.values
        .where((d) =>
            (d['kind'] == 'gateway' || d['kind'] == 'gateway_matrix') &&
            _isEligibleForOnboarding(d))
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
    items.sort((a, b) =>
        (a['gateway_id'] as String).compareTo(b['gateway_id'] as String));
    return items;
  }

  bool _isEligibleForOnboarding(Map<String, dynamic> d) {
    // Coleiras podem aparecer via nome/serviço mesmo quando o app ainda não
    // conseguiu ler manufacturer data completo.
    final kind = (d['kind'] ?? '').toString().toLowerCase();
    if (kind == 'collar') return true;

    // Gateways permanecem condicionados ao sinal de Wi-Fi/OTA ativo.
    final wifiEnabled = d['wifi_enabled'];
    return wifiEnabled is bool && wifiEnabled;
  }

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (Object e) {
        lastError = e.toString();
        notifyListeners();
      },
    );
    _isScanningSub = FlutterBluePlus.isScanning.listen((v) {
      if (isScanning == v) return;
      isScanning = v;
      notifyListeners();
    });
    _initialized = true;
  }

  Future<void> _ensureAdapterOn() async {
    final supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      throw Exception('bluetooth_not_supported');
    }

    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      return;
    }

    try {
      await FlutterBluePlus.turnOn(timeout: 8);
    } catch (_) {}

    await FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on)
        .timeout(const Duration(seconds: 8));
  }

  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 8)}) async {
    await _initIfNeeded();
    try {
      await _ensureAdapterOn();
      lastError = null;
      lastScanAt = DateTime.now();
      notifyListeners();
      await FlutterBluePlus.startScan(
        timeout: timeout,
        continuousUpdates: true,
        androidUsesFineLocation: true,
      );
      _scanTimer?.cancel();
      _scanTimer = Timer(timeout + const Duration(milliseconds: 500), () {
        if (!isScanning) return;
        isScanning = false;
        notifyListeners();
      });
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (isScanning) {
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    _byKey.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    super.dispose();
  }

  void _onScanResults(List<ScanResult> results) {
    var changed = false;
    for (final r in results) {
      final parsed = _parseResult(r);
      if (parsed == null) continue;
      final key = parsed['key']?.toString();
      if (key == null || key.isEmpty) continue;

      final prev = _byKey[key];
      if (prev == null) {
        _byKey[key] = parsed;
        changed = true;
        continue;
      }

      final merged = Map<String, dynamic>.from(prev)..addAll(parsed);
      if (!mapEquals(prev, merged)) {
        _byKey[key] = merged;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Map<String, dynamic>? _parseResult(ScanResult result) {
    final fromMsd = _parseFromMsd(result);
    if (fromMsd != null) return fromMsd;
    return _parseFromName(result);
  }

  Map<String, dynamic>? _parseFromMsd(ScanResult result) {
    final msd = result.advertisementData.manufacturerData;
    if (msd.isEmpty) return null;

    for (final entry in msd.entries) {
      final bytes = entry.value;
      if (entry.key != manufacturerId && entry.key != _swap16(manufacturerId)) {
        continue;
      }
      if (bytes.length < 6) continue;
      var payloadOffset = 0;
      if (_matchesSignature(bytes)) {
        payloadOffset = 0;
      } else if (bytes.length >= 8 &&
          _matchesEmbeddedCompanyId(bytes) &&
          _matchesSignature(bytes.sublist(2))) {
        // Alguns stacks retornam companyId também dentro do payload.
        payloadOffset = 2;
      } else {
        continue;
      }

      final kindCode = bytes[payloadOffset + 4];
      final idLen = bytes[payloadOffset + 5];
      if (idLen <= 0) continue;

      final requiredLength = payloadOffset + 6 + idLen + 1 + 8;
      if (bytes.length < requiredLength) continue;

      final id = ascii.decode(
        bytes.sublist(payloadOffset + 6, payloadOffset + 6 + idLen),
        allowInvalid: true,
      );
      final normalizedId = _normalizeId(id);
      if (normalizedId.isEmpty) continue;

      final flags = bytes[payloadOffset + 6 + idLen];
      final hasPosition = (flags & 0x01) != 0;
      final wifiEnabled = (flags & 0x02) != 0;
      final internetConnected = (flags & 0x04) != 0;

      final latRaw = _readInt32LE(bytes, payloadOffset + 7 + idLen);
      final lonRaw = _readInt32LE(bytes, payloadOffset + 11 + idLen);
      final lat = hasPosition ? latRaw / 1e6 : null;
      final lon = hasPosition ? lonRaw / 1e6 : null;
      final kind = _kindFromCode(kindCode);
      if (kind == null) continue;

      final remoteId = result.device.remoteId.str;
      final name = _bestName(result);
      return _candidateMap(
        kind: kind,
        id: normalizedId,
        name: name,
        lat: lat,
        lon: lon,
        rssi: result.rssi,
        remoteId: remoteId,
        wifiEnabled: wifiEnabled,
        internetConnected: internetConnected,
        source: 'ble_msd',
      );
    }
    return null;
  }

  Map<String, dynamic>? _parseFromName(ScanResult result) {
    final name = _bestName(result);
    if (name.isEmpty) return null;

    final upper = name.toUpperCase();
    String? kind;
    String rawId = '';
    if (upper.startsWith('RT-C-')) {
      kind = 'collar';
      rawId = name.substring(5);
    } else if (upper.startsWith('RT-G-')) {
      kind = 'gateway';
      rawId = name.substring(5);
    } else if (upper.startsWith('RT-M-')) {
      kind = 'gateway_matrix';
      rawId = name.substring(5);
    } else {
      return null;
    }

    final id = _normalizeId(rawId);
    if (id.isEmpty) return null;

    return _candidateMap(
      kind: kind,
      id: id,
      name: name,
      lat: null,
      lon: null,
      rssi: result.rssi,
      remoteId: result.device.remoteId.str,
      wifiEnabled: false,
      internetConnected: false,
      source: 'ble_name',
    );
  }

  bool _matchesSignature(List<int> bytes) {
    if (bytes.length < _signature.length) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  bool _matchesEmbeddedCompanyId(List<int> bytes) {
    if (bytes.length < 2) return false;
    const lo = manufacturerId & 0xFF;
    const hi = (manufacturerId >> 8) & 0xFF;
    return (bytes[0] == lo && bytes[1] == hi) ||
        (bytes[0] == hi && bytes[1] == lo);
  }

  int _swap16(int value) {
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF);
  }

  int _readInt32LE(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    final v = (bytes[offset] & 0xFF) |
        ((bytes[offset + 1] & 0xFF) << 8) |
        ((bytes[offset + 2] & 0xFF) << 16) |
        ((bytes[offset + 3] & 0xFF) << 24);
    return v.toSigned(32);
  }

  String _normalizeId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  }

  String _bestName(ScanResult result) {
    final adv = result.advertisementData.advName.trim();
    if (adv.isNotEmpty) return adv;
    final platform = result.device.platformName.trim();
    if (platform.isNotEmpty) return platform;
    return '';
  }

  String? _kindFromCode(int code) {
    if (code == 1) return 'collar';
    if (code == 2) return 'gateway';
    if (code == 3) return 'gateway_matrix';
    return null;
  }

  Map<String, dynamic> _candidateMap({
    required String kind,
    required String id,
    required String name,
    required double? lat,
    required double? lon,
    required int rssi,
    required String remoteId,
    required bool wifiEnabled,
    required bool internetConnected,
    required String source,
  }) {
    final common = <String, dynamic>{
      'kind': kind,
      'id': id,
      'name': name.isEmpty ? null : name,
      'lat': lat,
      'lon': lon,
      'rssi': rssi,
      'remote_id': remoteId,
      'wifi_enabled': wifiEnabled,
      'internet_connected': internetConnected,
      'source': source,
      'service_uuid': ruraltechServiceUuid,
    };

    if (kind == 'collar') {
      return {
        'key': 'collar:$id',
        ...common,
        'device_id_str': id,
      };
    }

    return {
      'key': 'gateway:$id',
      ...common,
      'gateway_id': id,
      'gateway_id_raw': id,
      'host_ws': null,
      'host_http': null,
      'ip': null,
    };
  }
}
