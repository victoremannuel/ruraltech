import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/cloud_service.dart';
import 'collar_log_screen.dart';
import 'geofence_screen.dart';
import 'herding_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  final DeviceModel device;
  const DeviceDetailsScreen({super.key, required this.device});

  String _boolLabel(bool value) => value ? 'OK' : 'Falha';

  String _formatHealthTimestamp() {
    final dt = device.healthReceivedAt;
    if (dt == null) return 'Sem registro';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  String _formatTelemetryTimestamp() {
    final dt = device.telemetryReceivedAt;
    if (dt == null) return 'Sem registro no gateway matriz';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  String _formatPosition() {
    final lat = device.lat;
    final lon = device.lon;
    if (lat == null || lon == null) return 'Sem posicao';
    return '$lat, $lon';
  }

  String _formatPositionFromValues(double? lat, double? lon) {
    if (lat == null || lon == null) return 'Sem posicao';
    return '$lat, $lon';
  }

  String _healthComponentsSummary() {
    return [
      'LoRa ${_boolLabel(device.healthLoRaReady)}',
      'MPU ${_boolLabel(device.healthMpuReady)}',
      'MLX ${_boolLabel(device.healthMlxReady)}',
      'Fila ${_boolLabel(device.healthStorageReady)}',
    ].join(' | ');
  }

  String _healthGpsSummary() {
    final sats = device.healthSatellites?.toString() ?? '-';
    final hdop = device.healthHdop?.toStringAsFixed(2) ?? '-';
    final i2c = device.healthI2cDevices?.toString() ?? '-';
    return [
      'UART ${_boolLabel(device.healthGpsUartReady)}',
      'NMEA ${_boolLabel(device.healthGpsNmeaSeen)}',
      'Fix ${device.healthGpsFixValid ? 'OK' : 'Sem fix'}',
      'Sat $sats',
      'HDOP $hdop',
      'I2C $i2c',
    ].join(' | ');
  }

  Widget _buildLatestPositionTile(BuildContext context) {
    final propertyId = device.propertyId?.trim();
    final deviceId = device.loraDeviceId;
    CloudService? firebase;
    try {
      firebase = context.read<CloudService>();
    } catch (_) {
      firebase = null;
    }
    final fallbackPosition = _formatPosition();
    final fallbackTimestamp = _formatTelemetryTimestamp();

    if (propertyId == null ||
        propertyId.isEmpty ||
        deviceId == null ||
        firebase == null) {
      return ListTile(
        title: const Text('Última posição'),
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(fallbackPosition)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                fallbackTimestamp,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: firebase.streamLatestTelemetryEntryForDevice(
        propertyId: propertyId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        final live = snapshot.data;
        final liveLat = live?['lat'] as double?;
        final liveLon = live?['lon'] as double?;
        final liveTimestampMs = live?['telemetryReceivedAtMs'] as int?;
        final position =
            _formatPositionFromValues(liveLat, liveLon) == 'Sem posicao'
                ? fallbackPosition
                : _formatPositionFromValues(liveLat, liveLon);
        final timestamp = liveTimestampMs == null || liveTimestampMs <= 0
            ? fallbackTimestamp
            : _formatTelemetryTimestampFromMs(liveTimestampMs);

        return ListTile(
          title: const Text('Última posição'),
          subtitle: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(position)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  timestamp,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTelemetryTimestampFromMs(int ms) {
    if (ms <= 0) return 'Sem registro no gateway matriz';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final networkId = device.networkId;
    final loraDeviceId = device.loraDeviceId;
    final hasValidLoraId = loraDeviceId != null;
    final hasPropertyBinding =
        device.propertyId != null && device.propertyId!.trim().isNotEmpty;
    final canOpenLog = hasValidLoraId && hasPropertyBinding;
    return Scaffold(
      appBar: AppBar(title: Text('Dispositivo ${device.name}')),
      body: ListView(
        children: [
          ListTile(title: const Text('ID'), subtitle: Text(networkId)),
          _buildLatestPositionTile(context),
          ListTile(
            title: const Text('Saude diaria'),
            subtitle: Text(device.healthSummary),
          ),
          if (device.hasDailyHealth)
            ListTile(
              title: const Text('Ultimo relatorio'),
              subtitle: Text(_formatHealthTimestamp()),
            ),
          if (device.hasDailyHealth)
            ListTile(
              title: const Text('Componentes'),
              subtitle: Text(_healthComponentsSummary()),
            ),
          if (device.hasDailyHealth)
            ListTile(
              title: const Text('GPS e barramento'),
              subtitle: Text(_healthGpsSummary()),
            ),
          ListTile(
            title: const Text('Configurar Geofence'),
            subtitle: hasValidLoraId
                ? null
                : const Text(
                    'ID LoRa invalido. Edite a coleira e informe um ID numerico.',
                  ),
            enabled: hasValidLoraId,
            onTap: !hasValidLoraId
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeofenceScreen(
                          deviceId: loraDeviceId,
                          propertyId: device.propertyId,
                          gatewayId: device.gatewayId,
                          initialLat: device.lat,
                          initialLon: device.lon,
                        ),
                      ),
                    ),
          ),
          ListTile(
            title: const Text('Plano de Condução'),
            subtitle: hasValidLoraId
                ? null
                : const Text(
                    'ID LoRa invalido. Edite a coleira e informe um ID numerico.',
                  ),
            enabled: hasValidLoraId,
            onTap: !hasValidLoraId
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HerdingScreen(
                          initialDeviceId: loraDeviceId,
                          initialPropertyId: device.propertyId,
                          initialLat: device.lat,
                          initialLon: device.lon,
                        ),
                      ),
                    ),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Abrir log da coleira'),
            subtitle: canOpenLog
                ? const Text(
                    'Mensagens recebidas no backend pela matriz.',
                  )
                : const Text(
                    'A coleira precisa ter propriedade vinculada e ID LoRa valido.',
                  ),
            enabled: canOpenLog,
            onTap: !canOpenLog
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CollarLogScreen(device: device),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
