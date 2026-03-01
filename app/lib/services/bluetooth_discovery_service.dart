import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothDiscoveryService extends ChangeNotifier {
  static const int manufacturerId = 0x1234;
  static const List<int> _signature = [0x52, 0x54, 0x42, 0x31]; // RTB1
  static const List<int> _positionSignature = [0x52, 0x54, 0x50, 0x31]; // RTP1
  static const String ruraltechServiceUuid =
      '7f920001-0a26-4d09-a606-0cfef4f9a1f0';
  static const String ruraltechPositionCharacteristicUuid =
      '7f920002-0a26-4d09-a606-0cfef4f9a1f0';

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

  Future<({double lat, double lon})?> requestCollarPositionByBleRead({
    required String collarId,
    Duration connectTimeout = const Duration(seconds: 15),
    int operationTimeoutSeconds = 12,
  }) async {
    await _initIfNeeded();
    await _ensureAdapterOn();

    final key = 'collar:${_normalizeId(collarId)}';
    final candidate = _byKey[key];
    final remoteId = candidate?['remote_id']?.toString();
    if (remoteId == null || remoteId.trim().isEmpty) {
      lastError = 'ble_missing_remote_id_for_$collarId';
      notifyListeners();
      return null;
    }

    final device = BluetoothDevice.fromId(remoteId.trim());
    final wasConnected = device.isConnected;
    try {
      // iOS fica mais estavel para conectar quando o scan e pausado antes do GATT.
      await stopScan();
      if (!wasConnected) {
        await _connectWithRetry(
          device,
          firstTimeout: connectTimeout,
          secondTimeout: connectTimeout + const Duration(seconds: 8),
        );
      }

      final services =
          await device.discoverServices(timeout: operationTimeoutSeconds);
      BluetoothCharacteristic? positionCharacteristic;
      for (final service in services) {
        if (service.uuid.str.toLowerCase() != ruraltechServiceUuid) continue;
        for (final c in service.characteristics) {
          if (c.uuid.str.toLowerCase() == ruraltechPositionCharacteristicUuid) {
            positionCharacteristic = c;
            break;
          }
        }
        if (positionCharacteristic != null) break;
      }
      if (positionCharacteristic == null) {
        lastError = 'ble_position_characteristic_not_found';
        notifyListeners();
        return null;
      }

      final value = await _readCharacteristicWithFallback(
        device: device,
        characteristic: positionCharacteristic,
        operationTimeoutSeconds: operationTimeoutSeconds,
      );
      final parsed = _parsePositionPayload(value);
      if (parsed == null) {
        lastError = 'ble_position_unavailable';
        notifyListeners();
        return null;
      }

      final lat = parsed.lat;
      final lon = parsed.lon;
      final current = _byKey[key];
      if (current != null) {
        current['lat'] = lat;
        current['lon'] = lon;
        current['source'] = 'ble_gatt';
        _byKey[key] = current;
      }
      lastError = null;
      notifyListeners();
      return (lat: lat, lon: lon);
    } catch (e) {
      lastError = 'ble_position_read_failed: $e';
      notifyListeners();
      return null;
    } finally {
      if (!wasConnected && device.isConnected) {
        try {
          await device.disconnect(timeout: operationTimeoutSeconds);
        } catch (_) {}
      }
    }
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

  ({double lat, double lon})? _parsePositionPayload(List<int> bytes) {
    // Formato binario legado: RTP1 + flags + latE6 + lonE6
    if (bytes.length >= 13) {
      var signatureMatches = true;
      for (var i = 0; i < _positionSignature.length; i++) {
        if (bytes[i] != _positionSignature[i]) {
          signatureMatches = false;
          break;
        }
      }
      if (signatureMatches) {
        final flags = bytes[4];
        final hasPosition = (flags & 0x01) != 0;
        if (!hasPosition) return null;

        final lat = _readInt32LE(bytes, 5) / 1e6;
        final lon = _readInt32LE(bytes, 9) / 1e6;
        if (!lat.isFinite || !lon.isFinite) return null;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
        return (lat: lat, lon: lon);
      }
    }

    // Formato ASCII atual: RTP1;hasPos;latE6;lonE6
    final text = ascii.decode(bytes, allowInvalid: true).trim();
    if (!text.startsWith('RTP1;')) return null;
    final parts = text.split(';');
    if (parts.length < 4) return null;
    final hasPosition = parts[1].trim() == '1';
    if (!hasPosition) return null;
    final latE6 = int.tryParse(parts[2].trim());
    final lonE6 = int.tryParse(parts[3].trim());
    if (latE6 == null || lonE6 == null) return null;
    final lat = latE6 / 1e6;
    final lon = lonE6 / 1e6;
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return (lat: lat, lon: lon);
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

  Future<void> _connectWithRetry(
    BluetoothDevice device, {
    required Duration firstTimeout,
    required Duration secondTimeout,
  }) async {
    final timeouts = <Duration>[firstTimeout, secondTimeout];
    Object? lastConnectError;
    for (var i = 0; i < timeouts.length; i++) {
      final timeout = timeouts[i];
      try {
        await device.connect(timeout: timeout, mtu: null);
        return;
      } catch (e) {
        lastConnectError = e;
        final shouldRetry =
            i < (timeouts.length - 1) && _isRetryableConnectError(e);
        if (!shouldRetry) break;

        try {
          await device.disconnect(timeout: 4, queue: false);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    if (lastConnectError != null) {
      throw lastConnectError;
    }
    throw Exception('ble_connect_failed_without_details');
  }

  bool _isRetryableConnectError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('| connect |')) return true;
    if (lower.contains('fbp-code: 1')) return true;
    if (lower.contains('timed out')) return true;
    return false;
  }

  Future<List<int>> _readCharacteristicWithRetry({
    required BluetoothDevice device,
    required BluetoothCharacteristic characteristic,
    required int operationTimeoutSeconds,
  }) async {
    Object? lastError;
    var currentCharacteristic = characteristic;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          // iOS pode precisar de pequeno settle time antes do read após reconnect/discover.
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        return await currentCharacteristic.read(
          timeout: operationTimeoutSeconds + (attempt * 6),
        );
      } catch (e) {
        lastError = e;
        final canRetry = attempt == 0 && _isRetryableReadError(e);
        if (!canRetry) break;

        final services =
            await device.discoverServices(timeout: operationTimeoutSeconds);
        currentCharacteristic =
            _findPositionCharacteristic(services) ?? characteristic;
      }
    }

    if (lastError != null) throw lastError;
    throw Exception('ble_read_failed_without_details');
  }

  Future<List<int>> _readCharacteristicWithFallback({
    required BluetoothDevice device,
    required BluetoothCharacteristic characteristic,
    required int operationTimeoutSeconds,
  }) async {
    late final Object readError;
    try {
      return await _readCharacteristicWithRetry(
        device: device,
        characteristic: characteristic,
        operationTimeoutSeconds: operationTimeoutSeconds,
      );
    } catch (e) {
      readError = e;
    }

    final supportsNotify =
        characteristic.properties.notify || characteristic.properties.indicate;
    if (!supportsNotify) {
      throw readError;
    }

    try {
      return await _readCharacteristicViaNotify(
        characteristic: characteristic,
        timeoutSeconds: operationTimeoutSeconds + 8,
      );
    } catch (notifyError) {
      throw Exception('read_failed: $readError | notify_failed: $notifyError');
    }
  }

  Future<List<int>> _readCharacteristicViaNotify({
    required BluetoothCharacteristic characteristic,
    required int timeoutSeconds,
  }) async {
    final completer = Completer<List<int>>();
    StreamSubscription<List<int>>? sub;
    try {
      sub = characteristic.onValueReceived.listen(
        (value) {
          if (value.isEmpty || completer.isCompleted) return;
          completer.complete(List<int>.from(value));
        },
        onError: (Object e) {
          if (completer.isCompleted) return;
          completer.completeError(e);
        },
      );

      await characteristic.setNotifyValue(true, timeout: timeoutSeconds);

      final cached = characteristic.lastValue;
      if (cached.isNotEmpty && !completer.isCompleted) {
        completer.complete(List<int>.from(cached));
      }

      return await completer.future.timeout(Duration(seconds: timeoutSeconds));
    } finally {
      await sub?.cancel();
      try {
        if (characteristic.isNotifying) {
          await characteristic.setNotifyValue(false, timeout: 6);
        }
      } catch (_) {}
    }
  }

  bool _isRetryableReadError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('| readcharacteristic |')) return true;
    if (lower.contains('fbp-code: 1')) return true;
    if (lower.contains('timed out')) return true;
    return false;
  }

  BluetoothCharacteristic? _findPositionCharacteristic(
    List<BluetoothService> services,
  ) {
    for (final service in services) {
      if (service.uuid.str.toLowerCase() != ruraltechServiceUuid) continue;
      for (final c in service.characteristics) {
        if (c.uuid.str.toLowerCase() == ruraltechPositionCharacteristicUuid) {
          return c;
        }
      }
    }
    return null;
  }
}
