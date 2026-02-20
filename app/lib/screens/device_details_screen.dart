import 'package:flutter/material.dart';
import '../models/device_model.dart';
import 'geofence_screen.dart';
import 'herding_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  final DeviceModel device;
  const DeviceDetailsScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dispositivo ${device.name}')),
      body: ListView(
        children: [
          ListTile(title: const Text('ID'), subtitle: Text(device.id)),
          ListTile(
              title: const Text('Última posição'),
              subtitle: Text('${device.lat ?? 0}, ${device.lon ?? 0}')),
          ListTile(
              title: const Text('Configurar Geofence'),
              onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GeofenceScreen(
                        deviceId: device.id,
                        initialLat: device.lat,
                        initialLon: device.lon,
                      ),
                    ),
                  )),
          ListTile(
              title: const Text('Plano de Condução'),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => HerdingScreen(deviceId: device.id)))),
        ],
      ),
    );
  }
}
