import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';

class GeofenceScreen extends StatefulWidget {
  final String deviceId;
  const GeofenceScreen({super.key, required this.deviceId});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final _points = TextEditingController(text: '-23.0,-46.0\n-23.0,-46.1\n-23.1,-46.1\n-23.1,-46.0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Geofence')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _points, maxLines: 8, decoration: const InputDecoration(labelText: 'lat,lon por linha')),
          ElevatedButton(
              onPressed: () {
                final points = _points.text
                    .split('\n')
                    .map((e) => e.split(','))
                    .where((e) => e.length == 2)
                    .map((e) => [double.parse(e[0]), double.parse(e[1])])
                    .toList();
                context.read<FirebaseService>().saveFence(widget.deviceId, points);
                context.read<GatewayService>().sendCommand(deviceId: widget.deviceId, command: 'SET_FENCE', payload: {'points': points});
              },
              child: const Text('Publicar Cerca')),
        ]),
      ),
    );
  }
}
