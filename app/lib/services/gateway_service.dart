import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/manual_settings.dart';

typedef GatewayWebSocketConnector = WebSocketChannel Function(Uri uri);
typedef GatewayHttpGet = Future<http.Response> Function(
  Uri uri, {
  Map<String, String>? headers,
});
typedef GatewayClock = DateTime Function();

class GatewayTelemetrySample {
  const GatewayTelemetrySample({
    required this.deviceId,
    required this.lat,
    required this.lon,
    required this.receivedAtMs,
    this.seq,
    this.sourceTimestampSec,
    this.gatewayId,
    this.gatewayRole,
    this.gatewayWifiOtaEnabled,
    this.sourceType,
  });

  final String deviceId;
  final double lat;
  final double lon;
  final int receivedAtMs;
  final int? seq;
  final int? sourceTimestampSec;
  final String? gatewayId;
  final String? gatewayRole;
  final bool? gatewayWifiOtaEnabled;
  final String? sourceType;
}

class GatewayService extends ChangeNotifier {
  static const int maxLoraPayloadBytes = 128;
  static const int maxPolygonPoints = 32;
  static const int maxHerdPhases = 8;
  static const Duration _gatewayProbeTimeout = Duration(milliseconds: 500);
  static const int _gatewayProbeBatchSize = 24;

  GatewayService({
    GatewayWebSocketConnector? webSocketConnector,
    GatewayHttpGet? httpGet,
    GatewayClock? clock,
    String? initialGatewayHost,
  })  : _webSocketConnector = webSocketConnector ?? _defaultWebSocketConnector,
        _httpGet = httpGet ?? _defaultHttpGet,
        _clock = clock ?? _defaultClock {
    if (initialGatewayHost != null && initialGatewayHost.trim().isNotEmpty) {
      gatewayHost = initialGatewayHost.trim();
    }
  }

  static WebSocketChannel _defaultWebSocketConnector(Uri uri) =>
      WebSocketChannel.connect(uri);
  static Future<http.Response> _defaultHttpGet(
    Uri uri, {
    Map<String, String>? headers,
  }) =>
      http.get(uri, headers: headers);
  static DateTime _defaultClock() => DateTime.now();

  final GatewayWebSocketConnector _webSocketConnector;
  final GatewayHttpGet _httpGet;
  final GatewayClock _clock;

  WebSocketChannel? _channel;
  final List<Map<String, dynamic>> messages = [];
  final Map<String, Map<String, dynamic>> _networkDiscoveredCollars = {};
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<GatewayTelemetrySample> _telemetryController =
      StreamController<GatewayTelemetrySample>.broadcast();
  String gatewayHost = ManualSettings.defaultGatewayWsHost;
  bool isConnected = false;
  bool isDiscoveringCollars = false;
  String? lastError;

  Stream<GatewayTelemetrySample> get telemetryStream =>
      _telemetryController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void clearTransientDiscoveryState({bool notify = true}) {
    messages.clear();
    _networkDiscoveredCollars.clear();
    if (notify) {
      notifyListeners();
    }
  }

  void connect() {
    _channel?.sink.close();
    isConnected = false;
    lastError = null;
    notifyListeners();

    try {
      _channel = _webSocketConnector(Uri.parse(gatewayHost));
      _channel!.stream.listen(
        (event) {
          final parsed = jsonDecode(event as String) as Map<String, dynamic>;
          messages.insert(0, parsed);
          if (messages.length > 200) messages.removeLast();
          _messageController.add(Map<String, dynamic>.from(parsed));
          final sample = _extractTelemetrySample(parsed);
          if (sample != null) _telemetryController.add(sample);
          isConnected = true;
          lastError = null;
          notifyListeners();
        },
        onError: (Object e) {
          isConnected = false;
          lastError = e.toString();
          notifyListeners();
        },
        onDone: () {
          isConnected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      isConnected = false;
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<bool> ensureConnected({
    String? hostOverride,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final trimmedHost = hostOverride?.trim();
    if (trimmedHost != null && trimmedHost.isNotEmpty) {
      gatewayHost = trimmedHost;
    }

    if (isConnected && _channel != null) return true;
    connect();

    final deadline = _clock().add(timeout);
    while ((!isConnected || _channel == null) && _clock().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    if (!isConnected || _channel == null) {
      // Cancela a tentativa de conexão pendente para evitar que o timeout do OS
      // (~60s no iOS) dispare onError em background e polua lastError na UI.
      _channel?.sink.close();
      _channel = null;
      lastError = 'gateway_not_connected';
      notifyListeners();
      return false;
    }
    return true;
  }

  void _pushLocalCommandResult({
    required int deviceId,
    required String command,
    required bool ok,
    required String reason,
  }) {
    messages.insert(0, {
      'type': 'command_result',
      'source': 'app_validation',
      'ok': ok,
      'device_id': deviceId,
      'command': command,
      'reason': reason,
    });
    if (messages.length > 200) messages.removeLast();
  }

  void _pushLocalOperationResult({
    required String operationId,
    required bool ok,
    required String reason,
  }) {
    messages.insert(0, {
      'type': 'herding_operation_update',
      'source': 'app_validation',
      'operation_id': operationId,
      'ok': ok,
      'status': ok ? 'accepted' : 'failed',
      'reason': reason,
    });
    if (messages.length > 200) messages.removeLast();
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  double? _toFiniteDouble(dynamic value) {
    if (value is! num) return null;
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }

  bool _isValidPointPair(dynamic value) {
    if (value is! List || value.length < 2) return false;
    final lat = _toFiniteDouble(value[0]);
    final lon = _toFiniteDouble(value[1]);
    if (lat == null || lon == null) return false;
    return lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0;
  }

  String? _validateFencePayload(Map<String, dynamic> payload) {
    final points = payload['points'];
    if (points is! List) return 'missing_points';
    if (points.length < 3) return 'too_few_points';
    if (points.length > maxPolygonPoints) return 'too_many_points';
    for (var i = 0; i < points.length; i++) {
      if (!_isValidPointPair(points[i])) return 'invalid_point_$i';
    }
    return null;
  }

  String? _validateHerdingPayload(Map<String, dynamic> payload) {
    final phases = payload['phases'];
    if (phases is! List) return 'missing_phases';
    if (phases.isEmpty) return 'too_few_phases';
    if (phases.length > maxHerdPhases) return 'too_many_phases';

    for (var p = 0; p < phases.length; p++) {
      final phase = phases[p];
      if (phase is! List) return 'invalid_phase_$p';
      if (phase.length < 3) return 'phase_${p}_too_few_points';
      if (phase.length > maxPolygonPoints) return 'phase_${p}_too_many_points';
      for (var i = 0; i < phase.length; i++) {
        if (!_isValidPointPair(phase[i])) return 'invalid_phase_${p}_point_$i';
      }
    }
    return null;
  }

  String? _validateSetParamsPayload(Map<String, dynamic> payload) {
    final wifiEnabled = payload['wifi_ota_enabled'];
    if (wifiEnabled is! bool) return 'missing_wifi_ota_enabled';
    if (wifiEnabled) return null;

    final requestedByAdmin = payload['requested_by_admin'] == true;
    final requestedByRole =
        (payload['requested_by_role'] ?? payload['actor_role'])
            ?.toString()
            .trim()
            .toLowerCase();
    if (requestedByAdmin ||
        requestedByRole == 'adm' ||
        requestedByRole == 'admin') {
      return null;
    }
    return 'admin_required_for_lora_only';
  }

  String? _validateHerdingOperationPayload(Map<String, dynamic> payload) {
    final operationId = (payload['operation_id'] ?? '').toString().trim();
    if (operationId.isEmpty) return 'missing_operation_id';

    final selectedDeviceIds = payload['selected_device_ids'];
    if (selectedDeviceIds is! List || selectedDeviceIds.isEmpty) {
      return 'missing_selected_device_ids';
    }
    for (var i = 0; i < selectedDeviceIds.length; i++) {
      final raw = selectedDeviceIds[i];
      final parsed = int.tryParse(raw.toString().trim());
      if (parsed == null || parsed <= 0) {
        return 'invalid_selected_device_$i';
      }
    }

    final targetPolygon = payload['target_polygon'];
    if (targetPolygon is! List) return 'missing_target_polygon';
    if (targetPolygon.length < 3) return 'too_few_target_points';
    if (targetPolygon.length > maxPolygonPoints) {
      return 'too_many_target_points';
    }
    for (var i = 0; i < targetPolygon.length; i++) {
      if (!_isValidPointPair(targetPolygon[i])) {
        return 'invalid_target_point_$i';
      }
    }

    return null;
  }

  String? _validatePayloadByCommand(
      String command, Map<String, dynamic> payload) {
    switch (command) {
      case 'SET_FENCE':
        return _validateFencePayload(payload);
      case 'SET_HERDING_PLAN':
        return _validateHerdingPayload(payload);
      case 'SET_PARAMS':
        return _validateSetParamsPayload(payload);
      default:
        return null;
    }
  }

  Map<String, dynamic>? _decodePayloadMap(dynamic rawPayload) {
    if (rawPayload is Map<String, dynamic>) return rawPayload;
    if (rawPayload is! String || rawPayload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  GatewayTelemetrySample? _extractTelemetrySample(Map<String, dynamic> msg) {
    final type = (msg['type'] ?? '').toString().toLowerCase();
    if (type != 'telemetry' && type != 'event') return null;

    final payload = _decodePayloadMap(msg['payload']);
    final deviceId = _extractDeviceId(msg, payload);
    if (deviceId == null || deviceId <= 0) return null;

    double? lat = _toFiniteDouble(payload?['lat']);
    double? lon = _toFiniteDouble(payload?['lon']);
    final gps = payload?['gps'];
    if (gps is Map<String, dynamic>) {
      lat ??= _toFiniteDouble(gps['lat']);
      lon ??= _toFiniteDouble(gps['lon']);
    }
    if (lat == null ||
        lon == null ||
        lat < -90.0 ||
        lat > 90.0 ||
        lon < -180.0 ||
        lon > 180.0) {
      return null;
    }

    final connectedHost = connectedGatewayCandidate;
    final gatewayId = (msg['gateway_id'] ??
            msg['gatewayId'] ??
            connectedHost?['gateway_id'] ??
            connectedHost?['gateway_id_raw'])
        ?.toString();
    final gatewayRole = (msg['gateway_role'] ?? msg['gatewayRole'])?.toString();
    final wifiOtaFlag = msg['gateway_wifi_ota_enabled'];
    final gatewayWifiOtaEnabled = wifiOtaFlag is bool ? wifiOtaFlag : null;

    return GatewayTelemetrySample(
      deviceId: deviceId.toString(),
      lat: lat,
      lon: lon,
      receivedAtMs: _clock().millisecondsSinceEpoch,
      seq: _toInt(msg['seq']),
      sourceTimestampSec: _toInt(msg['timestamp']),
      gatewayId: gatewayId == null || gatewayId.trim().isEmpty
          ? null
          : gatewayId.trim(),
      gatewayRole: gatewayRole == null || gatewayRole.trim().isEmpty
          ? null
          : gatewayRole.trim(),
      gatewayWifiOtaEnabled: gatewayWifiOtaEnabled,
      sourceType: type,
    );
  }

  String _sanitizeDocId(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    return cleaned.isEmpty ? 'gateway-unknown' : cleaned;
  }

  bool _isValidIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  List<String> _hostsToProbe({int maxHosts = 40}) {
    final hosts = <String>{};
    final limit = maxHosts.clamp(1, 254);

    void addSubnet(String prefix, int hostLimit) {
      final bounded = hostLimit.clamp(1, 254);
      for (var i = 1; i <= bounded; i++) {
        hosts.add('$prefix.$i');
      }
    }

    final uri = Uri.tryParse(gatewayHost);
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host.trim();
      if (_isValidIpv4(host)) {
        hosts.add(host);
        final parts = host.split('.');
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        addSubnet(prefix, limit);
      } else {
        hosts.add(host);
      }
    }

    // Sub-redes locais de onboarding dos firmwares (coleira/gateway).
    for (final subnet in ManualSettings.onboardingSubnets) {
      final trimmedSubnet = subnet.trim();
      if (trimmedSubnet.isEmpty) continue;
      addSubnet(
        trimmedSubnet,
        math.min(limit, ManualSettings.onboardingSubnetProbeLimit),
      );
    }

    return hosts.toList()..sort();
  }

  Map<String, dynamic>? get connectedGatewayCandidate {
    final uri = Uri.tryParse(gatewayHost);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.trim();
    final gatewayId = _sanitizeDocId(host);
    return {
      'gateway_id': gatewayId,
      'gateway_id_raw': host,
      'host_ws': gatewayHost,
      'host_http': 'http://$host',
      'ip': host,
      'name': 'Gateway $host',
      'source': 'connected_host',
    };
  }

  Future<Map<String, dynamic>?> _probeGateway(String host) async {
    try {
      final resp = await _httpGet(Uri.parse('http://$host/status'))
          .timeout(_gatewayProbeTimeout);
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      final service = (decoded['service']?.toString().toLowerCase() ?? '');
      if (service != 'gateway' && service != 'gateway_matrix') {
        return null;
      }

      final rawId = (decoded['gatewayId'] ??
              decoded['ap_ssid'] ??
              decoded['ap_ip'] ??
              host)
          .toString();
      final gatewayId = _sanitizeDocId(rawId);
      return {
        'gateway_id': gatewayId,
        'gateway_id_raw': rawId,
        'host_ws': 'ws://$host:81',
        'host_http': 'http://$host',
        'ip': host,
        'name': decoded['ap_ssid']?.toString() ?? 'Gateway $gatewayId',
        'fw': decoded['fw']?.toString(),
        'kind': service == 'gateway_matrix' ? 'gateway_matrix' : 'gateway',
        'source': 'network_probe',
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _probeCollar(String host) async {
    try {
      final resp = await _httpGet(Uri.parse('http://$host/status'))
          .timeout(_gatewayProbeTimeout);
      if (resp.statusCode != 200) return null;

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return null;
      final service = (decoded['service']?.toString().toLowerCase() ?? '');
      if (service != 'collar') {
        return null;
      }

      final rawId = (decoded['device_id'] ??
              decoded['deviceId'] ??
              decoded['id'] ??
              decoded['ap_ssid'] ??
              host)
          .toString();
      final deviceId = _sanitizeDocId(rawId);

      double? lat = _toFiniteDouble(decoded['lat']);
      double? lon = _toFiniteDouble(decoded['lon']);
      final gps = decoded['gps'];
      if (gps is Map<String, dynamic>) {
        lat ??= _toFiniteDouble(gps['lat']);
        lon ??= _toFiniteDouble(gps['lon']);
      }
      if (lat != null &&
          lon != null &&
          (lat < -90 || lat > 90 || lon < -180 || lon > 180)) {
        lat = null;
        lon = null;
      }

      return {
        'device_id': int.tryParse(deviceId) ?? deviceId,
        'device_id_str': deviceId,
        'lat': lat,
        'lon': lon,
        'name': decoded['name']?.toString() ?? decoded['ap_ssid']?.toString(),
        'host_http': 'http://$host',
        'ip': host,
        'source_type': 'wifi',
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> discoverGatewaysOnLocalNetwork(
      {int maxHosts = 120}) async {
    final hosts = _hostsToProbe(maxHosts: maxHosts);
    if (hosts.isEmpty) return const [];

    final byId = <String, Map<String, dynamic>>{};
    final connected = connectedGatewayCandidate;
    if (connected != null) {
      byId[connected['gateway_id'] as String] = connected;
    }

    for (var i = 0; i < hosts.length; i += _gatewayProbeBatchSize) {
      final end = math.min(i + _gatewayProbeBatchSize, hosts.length);
      final batch = hosts.sublist(i, end);
      await Future.wait(
        batch.map((host) async {
          final found = await _probeGateway(host);
          if (found == null) return;
          byId[found['gateway_id'] as String] = found;
        }),
      );
    }

    final result = byId.values.toList();
    result.sort(
      (a, b) => (a['host_ws'] as String).compareTo(b['host_ws'] as String),
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> discoverCollarsOnLocalNetwork({
    int maxHosts = 120,
  }) async {
    final hosts = _hostsToProbe(maxHosts: maxHosts);
    if (hosts.isEmpty) return const [];

    final byId = <String, Map<String, dynamic>>{};

    for (var i = 0; i < hosts.length; i += _gatewayProbeBatchSize) {
      final end = math.min(i + _gatewayProbeBatchSize, hosts.length);
      final batch = hosts.sublist(i, end);
      await Future.wait(
        batch.map((host) async {
          final found = await _probeCollar(host);
          if (found == null) return;
          final id = found['device_id_str']?.toString();
          if (id == null || id.isEmpty) return;
          byId[id] = found;
        }),
      );
    }

    _networkDiscoveredCollars
      ..clear()
      ..addAll(byId);

    final result = _networkDiscoveredCollars.values.toList();
    result.sort(
      (a, b) => (a['device_id_str'] as String)
          .compareTo(b['device_id_str'] as String),
    );
    for (final found in result) {
      final id = found['device_id_str']?.toString();
      final lat = _toFiniteDouble(found['lat']);
      final lon = _toFiniteDouble(found['lon']);
      if (id == null || id.isEmpty || lat == null || lon == null) continue;
      _telemetryController.add(
        GatewayTelemetrySample(
          deviceId: id,
          lat: lat,
          lon: lon,
          receivedAtMs: _clock().millisecondsSinceEpoch,
          gatewayId: found['ip']?.toString(),
          gatewayRole: 'collar',
          gatewayWifiOtaEnabled: true,
          sourceType: 'status_poll',
        ),
      );
    }
    notifyListeners();
    return result;
  }

  Future<void> requestCollarDiscovery() async {
    if (isDiscoveringCollars) return;
    isDiscoveringCollars = true;
    lastError = null;
    notifyListeners();

    try {
      await discoverCollarsOnLocalNetwork(maxHosts: 120);
      if (_networkDiscoveredCollars.isEmpty) {
        lastError = 'nenhuma_coleira_wifi_encontrada';
      } else {
        lastError = null;
      }
    } finally {
      isDiscoveringCollars = false;
      notifyListeners();
    }
  }

  int? _extractDeviceId(
    Map<String, dynamic> msg,
    Map<String, dynamic>? payload,
  ) {
    final fromMessage = _toInt(msg['device_id']) ??
        _toInt(msg['deviceId']) ??
        _toInt(msg['device_id_str']) ??
        _toInt(msg['id']);
    if (fromMessage != null) return fromMessage;

    return _toInt(payload?['device_id']) ??
        _toInt(payload?['deviceId']) ??
        _toInt(payload?['id']);
  }

  List<Map<String, dynamic>> get discoveredCollars {
    final byDeviceId = <String, Map<String, dynamic>>{};

    for (final msg in messages) {
      final type = (msg['type'] ?? '').toString().toLowerCase();
      if (type != 'telemetry' &&
          type != 'event' &&
          type != 'ack' &&
          type != 'nack' &&
          type != 'lora') {
        continue;
      }

      final payload = _decodePayloadMap(msg['payload']);
      final deviceId = _extractDeviceId(msg, payload);
      if (deviceId == null || deviceId <= 0) continue;
      final deviceIdStr = deviceId.toString();
      if (byDeviceId.containsKey(deviceIdStr)) continue;

      final lat = _toFiniteDouble(payload?['lat']);
      final lon = _toFiniteDouble(payload?['lon']);

      byDeviceId[deviceIdStr] = {
        'device_id': deviceId,
        'device_id_str': deviceIdStr,
        'lat': lat,
        'lon': lon,
        'gateway_id': (msg['gateway_id'] ?? msg['gatewayId'])?.toString(),
        'source_type': 'wifi',
      };
    }

    for (final net in _networkDiscoveredCollars.values) {
      final id = net['device_id_str']?.toString();
      if (id == null || id.isEmpty) continue;
      final current = byDeviceId[id];
      if (current == null) {
        byDeviceId[id] = Map<String, dynamic>.from(net);
        continue;
      }
      current['source_type'] = 'wifi';
      current['lat'] ??= net['lat'];
      current['lon'] ??= net['lon'];
      if ((current['name']?.toString().trim() ?? '').isEmpty &&
          (net['name']?.toString().trim() ?? '').isNotEmpty) {
        current['name'] = net['name'];
      }
    }

    final discovered = byDeviceId.values.toList();
    discovered.sort(
      (a, b) => (a['device_id_str'] as String)
          .compareTo(b['device_id_str'] as String),
    );
    return discovered;
  }

  bool sendCommand({
    required String deviceId,
    required String command,
    required Map<String, dynamic> payload,
  }) {
    final parsedDeviceId = int.tryParse(deviceId.trim());
    if (parsedDeviceId == null) {
      lastError = '[send_command] invalid_device_id';
      _pushLocalCommandResult(
        deviceId: 0,
        command: command,
        ok: false,
        reason: 'invalid_device_id',
      );
      notifyListeners();
      return false;
    }

    final validationError = _validatePayloadByCommand(command, payload);
    if (validationError != null) {
      lastError = '[send_command] $validationError';
      _pushLocalCommandResult(
        deviceId: parsedDeviceId,
        command: command,
        ok: false,
        reason: validationError,
      );
      notifyListeners();
      return false;
    }

    if (!isConnected || _channel == null) {
      lastError = '[send_command] gateway_not_connected';
      _pushLocalCommandResult(
        deviceId: parsedDeviceId,
        command: command,
        ok: false,
        reason: 'gateway_not_connected',
      );
      notifyListeners();
      return false;
    }

    final msg = {
      'type': 'send_command',
      'device_id': parsedDeviceId,
      'command': command,
      'payload': payload
    };
    try {
      _channel!.sink.add(jsonEncode(msg));
      lastError = null;
      return true;
    } catch (e) {
      lastError = '[send_command] send_failed: $e';
      _pushLocalCommandResult(
        deviceId: parsedDeviceId,
        command: command,
        ok: false,
        reason: 'send_failed',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendCommandEnsuringConnection({
    required String deviceId,
    required String command,
    required Map<String, dynamic> payload,
    String? hostOverride,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final connected =
        await ensureConnected(hostOverride: hostOverride, timeout: timeout);
    if (!connected) return false;

    return sendCommand(deviceId: deviceId, command: command, payload: payload);
  }

  bool startHerdingOperation({
    required Map<String, dynamic> payload,
  }) {
    final operationId = (payload['operation_id'] ?? '').toString().trim();
    final validationError = _validateHerdingOperationPayload(payload);
    if (validationError != null) {
      lastError = '[start_herding_operation] $validationError';
      _pushLocalOperationResult(
        operationId: operationId,
        ok: false,
        reason: validationError,
      );
      notifyListeners();
      return false;
    }

    if (!isConnected || _channel == null) {
      lastError = '[start_herding_operation] gateway_not_connected';
      _pushLocalOperationResult(
        operationId: operationId,
        ok: false,
        reason: 'gateway_not_connected',
      );
      notifyListeners();
      return false;
    }

    try {
      _channel!.sink.add(
        jsonEncode({
          'type': 'start_herding_operation',
          'payload': payload,
        }),
      );
      lastError = null;
      return true;
    } catch (e) {
      lastError = '[start_herding_operation] send_failed: $e';
      _pushLocalOperationResult(
        operationId: operationId,
        ok: false,
        reason: 'send_failed',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> startHerdingOperationEnsuringConnection({
    required Map<String, dynamic> payload,
    String? hostOverride,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final connected =
        await ensureConnected(hostOverride: hostOverride, timeout: timeout);
    if (!connected) return false;
    return startHerdingOperation(payload: payload);
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.close();
    _telemetryController.close();
    super.dispose();
  }
}
