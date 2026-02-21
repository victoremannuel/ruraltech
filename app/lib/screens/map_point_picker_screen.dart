import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPointPickerScreen extends StatefulWidget {
  const MapPointPickerScreen({
    super.key,
    this.initial,
    this.propertyPolygon = const [],
  });

  final LatLng? initial;
  final List<LatLng> propertyPolygon;

  @override
  State<MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<MapPointPickerScreen> {
  LatLng? _selected;
  final MapController _mapController = MapController();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  void _fitToProperty() {
    if (_fitted || widget.propertyPolygon.length < 3) return;
    _fitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(widget.propertyPolygon);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _fitToProperty();
    final center = _selected ?? const LatLng(-23.0, -46.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Selecionar posicao')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.08),
            child: const Text('Toque no mapa para marcar a posicao.'),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                onTap: (_, p) => setState(() => _selected = p),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.ruraltechApp',
                ),
                PolygonLayer(
                  polygons: [
                    if (widget.propertyPolygon.length >= 3)
                      Polygon(
                        points: widget.propertyPolygon,
                        color: Colors.orange.withValues(alpha: 0.22),
                        borderColor: Colors.orange.shade700,
                        borderStrokeWidth: 3,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_selected != null)
                      Marker(
                        point: _selected!,
                        width: 32,
                        height: 32,
                        child:
                            const Icon(Icons.location_pin, color: Colors.red),
                      ),
                  ],
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
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(context, _selected),
                    child: const Text('Confirmar'),
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
