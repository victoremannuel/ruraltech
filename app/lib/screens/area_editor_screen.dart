import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class AreaEditorScreen extends StatefulWidget {
  const AreaEditorScreen({super.key});

  @override
  State<AreaEditorScreen> createState() => _AreaEditorScreenState();
}

class _AreaEditorScreenState extends State<AreaEditorScreen> {
  final List<LatLng> _points = [];
  String? _selectedPropertyId;
  bool _loadingProperties = true;
  List<Map<String, dynamic>> _properties = const [];

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    final auth = context.read<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final props = await context
        .read<FirebaseService>()
        .getRuralProperties(uid: uid, isAdmin: auth.isAdmin);
    if (!mounted) return;
    setState(() {
      _properties = props;
      _selectedPropertyId =
          props.isNotEmpty ? props.first['id'].toString() : null;
      _loadingProperties = false;
    });
  }

  Future<void> _save() async {
    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma propriedade rural.')),
      );
      return;
    }
    if (_points.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desenhe ao menos 3 pontos no poligono.')),
      );
      return;
    }

    final uid = context.read<AuthService>().user?.uid;
    if (uid == null) return;
    final perimeter = _points.map((p) => [p.latitude, p.longitude]).toList();
    await context.read<FirebaseService>().addArea(
          ownerUid: uid,
          ruralPropertyId: _selectedPropertyId!,
          perimeter: perimeter,
        );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova area (poligono)')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loadingProperties
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    initialValue: _selectedPropertyId,
                    items: _properties
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p['id'].toString(),
                            child: Text((p['name'] ?? p['id']).toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPropertyId = v),
                    decoration: const InputDecoration(
                      labelText: 'Propriedade rural',
                    ),
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.08),
            child: Text(
                'Toque para desenhar o poligono (${_points.length} pontos)'),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(-23.0, -46.0),
                initialZoom: 15,
                onTap: (_, p) => setState(() => _points.add(p)),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.ruraltechApp',
                ),
                PolygonLayer(
                  polygons: [
                    if (_points.length >= 3)
                      Polygon(
                        points: _points,
                        color: Colors.teal.withValues(alpha: 0.3),
                        borderColor: Colors.teal,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: _points
                      .map(
                        (p) => Marker(
                          point: p,
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.teal.shade800,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _points.isEmpty
                        ? null
                        : () => setState(() => _points.removeLast()),
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _points.isEmpty
                        ? null
                        : () => setState(() => _points.clear()),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
