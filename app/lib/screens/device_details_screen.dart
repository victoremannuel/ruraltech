import 'package:flutter/material.dart';
import '../models/device_model.dart';
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

  @override
  Widget build(BuildContext context) {
    final networkId = device.networkId;
    final loraDeviceId = device.loraDeviceId;
    final hasValidLoraId = loraDeviceId != null;
    return Scaffold(
      appBar: AppBar(title: Text('Dispositivo ${device.name}')),
      body: ListView(
        children: [
          ListTile(title: const Text('ID'), subtitle: Text(networkId)),
          ListTile(
              title: const Text('Última posição'),
              subtitle: Text('${device.lat ?? 0}, ${device.lon ?? 0}')),
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
                          deviceId: loraDeviceId,
                          gatewayId: device.gatewayId,
                          initialLat: device.lat,
                          initialLon: device.lon,
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
