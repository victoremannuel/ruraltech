import 'package:flutter/material.dart';
import '../models/device_model.dart';
import 'geofence_screen.dart';
import 'herding_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  final DeviceModel device;
  const DeviceDetailsScreen({super.key, required this.device});

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
