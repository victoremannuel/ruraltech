import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';
import '../utils/top_feedback.dart';

class AreaEditorScreen extends StatefulWidget {
  const AreaEditorScreen({super.key});

  @override
  State<AreaEditorScreen> createState() => _AreaEditorScreenState();
}

class _AreaEditorScreenState extends State<AreaEditorScreen> {
  static const int _maxAreaPoints = GatewayService.maxPolygonPoints;

  final List<LatLng> _points = [];
  String? _selectedPropertyId;
  bool _loadingProperties = true;
  List<Map<String, dynamic>> _properties = const [];
  final MapController _mapController = MapController();
  bool _fittedToProperty = false;

  LatLng? _toLatLng(dynamic value) {
    if (value is LatLng) return value;
    if (value is List && value.length >= 2) {
      final lat = value[0];
      final lon = value[1];
      if (lat is num && lon is num) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
    }
    if (value is Map) {
      final lat = value['lat'] ?? value['latitude'];
      final lon = value['lon'] ?? value['lng'] ?? value['longitude'];
      if (lat is num && lon is num) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
    }
    return null;
  }

  List<LatLng> get _selectedPropertyPolygon {
    if (_selectedPropertyId == null) return const [];
    final property = _properties.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id'].toString() == _selectedPropertyId,
          orElse: () => null,
        );
    if (property == null) return const [];
    final raw = (property['points'] as List?) ?? const [];
    return raw.map(_toLatLng).whereType<LatLng>().toList();
  }

  bool _isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / ((yj - yi) + 1e-12) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  void _fitToSelectedProperty() {
    if (_fittedToProperty || _selectedPropertyPolygon.length < 3) return;
    _fittedToProperty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_selectedPropertyPolygon),
          padding: const EdgeInsets.all(42),
        ),
      );
    });
  }

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
      _fittedToProperty = false;
    });
  }

  Future<void> _save() async {
    if (_selectedPropertyId == null || _selectedPropertyId!.isEmpty) {
      AppFeedback.error('Selecione uma propriedade rural.');
      return;
    }
    if (_points.length < 3) {
      AppFeedback.error('Desenhe ao menos 3 pontos no poligono.');
      return;
    }
    if (_points.length > _maxAreaPoints) {
      AppFeedback.error('Permitido apenas $_maxAreaPoints pontos por area.');
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
                    key: const Key('area_property_dropdown'),
                    initialValue: _selectedPropertyId,
                    items: _properties
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p['id'].toString(),
                            child: Text((p['name'] ?? p['id']).toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedPropertyId = v;
                      _fittedToProperty = false;
                    }),
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
                'Toque para desenhar o poligono (${_points.length}/$_maxAreaPoints pontos)'),
          ),
          Expanded(
            child: Builder(builder: (context) {
              _fitToSelectedProperty();
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(-23.0, -46.0),
                  initialZoom: 15,
                  onTap: (_, p) {
                    if (_points.length >= _maxAreaPoints) {
                      AppFeedback.error(
                        'Permitido apenas $_maxAreaPoints pontos por area.',
                      );
                      return;
                    }
                    final propertyPolygon = _selectedPropertyPolygon;
                    if (propertyPolygon.length < 3) return;
                    if (!_isPointInsidePolygon(p, propertyPolygon)) {
                      AppFeedback.error(
                        'Ponto fora do perimetro da propriedade selecionada.',
                      );
                      return;
                    }
                    setState(() => _points.add(p));
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                        ManualSettings.mapUserAgentPackageName,
                  ),
                  PolygonLayer(
                    polygons: [
                      if (_selectedPropertyPolygon.length >= 3)
                        Polygon(
                          points: _selectedPropertyPolygon,
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderColor: Colors.orange.shade700,
                          borderStrokeWidth: 3,
                        ),
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
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const Scalebar(
                    alignment: Alignment.bottomRight,
                    padding: EdgeInsets.only(
                      right: 12,
                      bottom: 12,
                    ),
                    lineColor: Color(0xFF173120),
                    textStyle: TextStyle(
                      color: Color(0xFF173120),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('area_undo_button'),
                    onPressed: _points.isEmpty
                        ? null
                        : () => setState(() => _points.removeLast()),
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('area_clear_button'),
                    onPressed: _points.isEmpty
                        ? null
                        : () => setState(() => _points.clear()),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('area_save_button'),
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
