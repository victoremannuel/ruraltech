import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/models/device_model.dart';
import 'package:ruraltech_app/screens/device_details_screen.dart';

void main() {
  testWidgets('shows latest telemetry timestamp and log action',
      (tester) async {
    final timestamp = DateTime(2026, 4, 2, 18, 17, 43);
    final device = DeviceModel(
      id: '3222380545',
      deviceId: '3222380545',
      name: 'RT-C-3222380545',
      status: 'active',
      lat: -16.67541,
      lon: -49.485042,
      propertyId: 'property-1',
      gatewayId: 'gateway-1',
      telemetryReceivedAtMs: timestamp.millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceDetailsScreen(device: device),
      ),
    );

    expect(find.text('02/04/2026 18:17:43'), findsOneWidget);
    expect(find.text('Abrir log da coleira'), findsOneWidget);
  });
}
