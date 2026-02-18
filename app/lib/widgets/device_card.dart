import 'package:flutter/material.dart';
import '../models/device_model.dart';

class DeviceCard extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback onTap;
  const DeviceCard({super.key, required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(device.name),
        subtitle: Text('Status: ${device.status}'),
        onTap: onTap,
      ),
    );
  }
}
