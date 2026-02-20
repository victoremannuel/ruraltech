import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';

class HerdingScreen extends StatelessWidget {
  final String deviceId;
  const HerdingScreen({super.key, required this.deviceId});

  List<List<List<double>>> _generateSimplePhases() {
    return [
      [
        [-23.0, -46.0],
        [-23.0, -46.2],
        [-23.2, -46.2],
        [-23.2, -46.0]
      ],
      [
        [-23.05, -46.05],
        [-23.05, -46.15],
        [-23.15, -46.15],
        [-23.15, -46.05]
      ],
      [
        [-23.08, -46.08],
        [-23.08, -46.12],
        [-23.12, -46.12],
        [-23.12, -46.08]
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Condução')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            final uid = context.read<AuthService>().user?.uid;
            if (uid == null) return;
            final phases = _generateSimplePhases();
            context
                .read<FirebaseService>()
                .saveHerdingPlan(deviceId, uid, phases);
            context.read<GatewayService>().sendCommand(
                deviceId: deviceId,
                command: 'SET_HERDING_PLAN',
                payload: {
                  'phases': phases,
                  'params': {'beepLevel': 2}
                });
          },
          child: const Text('Gerar e Publicar Plano (3 fases)'),
        ),
      ),
    );
  }
}
