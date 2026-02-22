import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class GatewayService extends ChangeNotifier {
  static const int maxLoraPayloadBytes = 128;
  static const int maxPolygonPoints = 32;
  static const int maxHerdPhases = 8;
  static const Duration _gatewayProbeTimeout = Duration(milliseconds: 500);
  static const int _gatewayProbeBatchSize = 24;

  WebSocketChannel? _channel;
  final List<Map<String, dynamic>> messages = [];
  String gatewayHost = 'ws://192.168.4.1:81';
  bool isConnected = false;
  String? lastError;

  void connect() {
    _channel?.sink.close();
    isConnected = false;
    lastError = null;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(gatewayHost));
      _channel!.stream.listen(
        (event) {
          final parsed = jsonDecode(event as String) as Map<String, dynamic>;
          messages.insert(0, parsed);
          if (messages.length > 200) messages.removeLast();
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

  String? _validatePayloadByCommand(
      String command, Map<String, dynamic> payload) {
    switch (command) {
      case 'SET_FENCE':
        return _validateFencePayload(payload);
      case 'SET_HERDING_PLAN':
        return _validateHerdingPayload(payload);
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
    final uri = Uri.tryParse(gatewayHost);
    if (uri == null || uri.host.isEmpty) return const [];
    final host = uri.host.trim();
    if (!_isValidIpv4(host)) return [host];

    final parts = host.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    final hosts = <String>{host};
    final limit = maxHosts.clamp(1, 254);
    for (var i = 1; i <= limit; i++) {
      hosts.add('$prefix.$i');
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
      final resp = await http
          .get(Uri.parse('http://$host/status'))
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

  List<Map<String, dynamic>> get discoveredCollars {
    final byDeviceId = <int, Map<String, dynamic>>{};

    for (final msg in messages) {
      final type = (msg['type'] ?? '').toString().toLowerCase();
      if (type != 'telemetry' &&
          type != 'event' &&
          type != 'ack' &&
          type != 'nack' &&
          type != 'lora') {
        continue;
      }

      final deviceId = _toInt(msg['device_id']);
      if (deviceId == null || deviceId <= 0) continue;
      if (byDeviceId.containsKey(deviceId)) continue;

      final payload = _decodePayloadMap(msg['payload']);
      final lat = _toFiniteDouble(payload?['lat']);
      final lon = _toFiniteDouble(payload?['lon']);

      byDeviceId[deviceId] = {
        'device_id': deviceId,
        'device_id_str': deviceId.toString(),
        'lat': lat,
        'lon': lon,
        'source_type': type,
      };
    }

    final discovered = byDeviceId.values.toList();
    discovered.sort(
      (a, b) => (a['device_id'] as int).compareTo(b['device_id'] as int),
    );
    return discovered;
  }

  void sendCommand(
      {required String deviceId,
      required String command,
      required Map<String, dynamic> payload}) {
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
      return;
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
      return;
    }

    final msg = {
      'type': 'send_command',
      'device_id': parsedDeviceId,
      'command': command,
      'payload': payload
    };
    _channel?.sink.add(jsonEncode(msg));
  }
}
