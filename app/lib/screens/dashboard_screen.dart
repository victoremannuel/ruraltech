import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';
import 'device_details_screen.dart';
import 'events_screen.dart';
import 'profile_screen.dart';
import 'rural_property_editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _showAddDeviceDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final ownerCtrl = TextEditingController(text: auth.user?.uid ?? '');
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final gatewayCtrl = TextEditingController();
    final propertyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Incluir coleira'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(labelText: 'UID dono'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o UID do usuario'
                      : null,
                ),
                TextFormField(
                  controller: propertyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Property ID (opcional)'),
                ),
                TextFormField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nome da coleira'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                TextFormField(
                  controller: statusCtrl,
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                TextFormField(
                  controller: latCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Lat (opcional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                TextFormField(
                  controller: lonCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Lon (opcional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                TextFormField(
                  controller: gatewayCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Gateway ID (opcional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await fb.addDevice(
                ownerUid: ownerCtrl.text.trim(),
                name: nameCtrl.text.trim(),
                status: statusCtrl.text.trim(),
                lat: double.tryParse(latCtrl.text.trim()),
                lon: double.tryParse(lonCtrl.text.trim()),
                gatewayId: gatewayCtrl.text.trim().isEmpty
                    ? null
                    : gatewayCtrl.text.trim(),
                propertyId: propertyCtrl.text.trim().isEmpty
                    ? null
                    : propertyCtrl.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddGatewayDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final fb = context.read<FirebaseService>();
    final ownerCtrl = TextEditingController(text: auth.user?.uid ?? '');
    final nameCtrl = TextEditingController();
    final statusCtrl = TextEditingController(text: 'active');
    final hostCtrl = TextEditingController(text: 'ws://192.168.4.1:81');
    final propertyCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Incluir gateway'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(labelText: 'UID dono'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o UID do usuario'
                      : null,
                ),
                TextFormField(
                  controller: propertyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Property ID (opcional)'),
                ),
                TextFormField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nome do gateway'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                TextFormField(
                  controller: statusCtrl,
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                TextFormField(
                  controller: latCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Lat (opcional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                TextFormField(
                  controller: lonCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Lon (opcional)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                TextFormField(
                  controller: hostCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Host (opcional)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await fb.addGateway(
                ownerUid: ownerCtrl.text.trim(),
                name: nameCtrl.text.trim(),
                status: statusCtrl.text.trim(),
                host:
                    hostCtrl.text.trim().isEmpty ? null : hostCtrl.text.trim(),
                propertyId: propertyCtrl.text.trim().isEmpty
                    ? null
                    : propertyCtrl.text.trim(),
                lat: double.tryParse(latCtrl.text.trim()),
                lon: double.tryParse(lonCtrl.text.trim()),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateRoleDialog(BuildContext context) async {
    final auth = context.read<AuthService>();
    final emailCtrl = TextEditingController();
    String role = 'adm';

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Vincular adm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'Email do usuario'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const [
                  DropdownMenuItem(value: 'adm', child: Text('adm')),
                  DropdownMenuItem(value: 'user', child: Text('user')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => role = v);
                },
                decoration: const InputDecoration(labelText: 'Perfil'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final targetEmail = emailCtrl.text.trim();
                if (targetEmail.isEmpty) return;
                try {
                  await auth.updateRoleByEmail(targetEmail, role);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _openPlusActions(BuildContext context) {
    final auth = context.read<AuthService>();
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('Novo poligono'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RuralPropertyEditorScreen(),
                  ),
                );
              },
            ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.pets),
                title: const Text('Incluir coleira'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAddDeviceDialog(context);
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.wifi),
                title: const Text('Incluir gateway'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAddGatewayDialog(context);
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.landscape),
                title: const Text('Incluir propriedade rural'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RuralPropertyEditorScreen(),
                    ),
                  );
                },
              ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Vincular adm'),
                onTap: () async {
                  Navigator.pop(context);
                  await _showUpdateRoleDialog(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final gateway = context.watch<GatewayService>();
    final fb = context.read<FirebaseService>();
    final uid = auth.user?.uid;

    if (uid == null || auth.isProfileLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Home (${auth.isAdmin ? 'adm' : 'user'})'),
        actions: [
          IconButton(icon: const Icon(Icons.wifi), onPressed: gateway.connect),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthService>().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: fb.streamRuralProperties(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, propsSnap) {
          return StreamBuilder<List<DeviceModel>>(
            stream: fb.streamDevices(uid: uid, isAdmin: auth.isAdmin),
            builder: (context, devicesSnap) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: fb.streamGateways(uid: uid, isAdmin: auth.isAdmin),
                builder: (context, gatewaySnap) {
                  final properties = propsSnap.data ?? const [];
                  final devices = devicesSnap.data ?? const <DeviceModel>[];
                  final gateways = gatewaySnap.data ?? const [];

                  final markers = <Marker>[
                    ...devices.where((d) => d.lat != null && d.lon != null).map(
                          (d) => Marker(
                            point: LatLng(d.lat!, d.lon!),
                            width: 36,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      DeviceDetailsScreen(device: d),
                                ),
                              ),
                              child: const Icon(Icons.pets,
                                  color: Colors.red, size: 28),
                            ),
                          ),
                        ),
                    ...gateways
                        .where((g) => g['lat'] != null && g['lon'] != null)
                        .map(
                          (g) => Marker(
                            point: LatLng(
                              (g['lat'] as num).toDouble(),
                              (g['lon'] as num).toDouble(),
                            ),
                            width: 34,
                            height: 34,
                            child: const Icon(Icons.wifi,
                                color: Colors.blue, size: 26),
                          ),
                        ),
                  ];

                  final polygons = properties
                      .map((p) {
                        final points = (p['points'] as List?) ?? const [];
                        final latLngs = points
                            .whereType<List>()
                            .where((row) => row.length >= 2)
                            .map(
                              (row) => LatLng(
                                (row[0] as num).toDouble(),
                                (row[1] as num).toDouble(),
                              ),
                            )
                            .toList();
                        if (latLngs.length < 3) return null;
                        return Polygon(
                          points: latLngs,
                          color: Colors.orange.withValues(alpha: 0.25),
                          borderColor: Colors.orange.shade700,
                          borderStrokeWidth: 3,
                        );
                      })
                      .whereType<Polygon>()
                      .toList();

                  final center = markers.isNotEmpty
                      ? markers.first.point
                      : const LatLng(-23.0, -46.0);

                  return Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.green.withValues(alpha: 0.08),
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Propriedades: ${properties.length} | Coleiras: ${devices.length} | Gateways: ${gateways.length}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 14,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.ruraltechApp',
                            ),
                            PolygonLayer(polygons: polygons),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Acoes',
              onPressed: () => _openPlusActions(context),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Perfil',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
