import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/gateway_service.dart';

class HerdingScreen extends StatefulWidget {
  final String deviceId;
  final String? gatewayId;
  final double? initialLat;
  final double? initialLon;

  const HerdingScreen({
    super.key,
    required this.deviceId,
    this.gatewayId,
    this.initialLat,
    this.initialLon,
  });

  @override
  State<HerdingScreen> createState() => _HerdingScreenState();
}

class _HerdingScreenState extends State<HerdingScreen> {
  static const int _maxPointsPerPhase = GatewayService.maxPolygonPoints;
  static const int _maxPhases = GatewayService.maxHerdPhases;
  static const List<Color> _phaseColors = <Color>[
    Colors.blue,
    Colors.teal,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.indigo,
    Colors.brown,
    Colors.green,
  ];

  final MapController _mapController = MapController();
  final List<List<LatLng>> _phases = <List<LatLng>>[<LatLng>[]];
  int _selectedPhase = 0;
  bool _isLoading = true;
  bool _isPublishing = false;
  bool _didFitLoadedPlan = false;
  late LatLng _center;

  @override
  void initState() {
    super.initState();
    _center = LatLng(widget.initialLat ?? -23.0, widget.initialLon ?? -46.0);
    _loadSavedPlan();
  }

  List<LatLng> get _activePhasePoints => _phases[_selectedPhase];

  List<LatLng> get _allPoints {
    final out = <LatLng>[];
    for (final phase in _phases) {
      out.addAll(phase);
    }
    return out;
  }

  Color _phaseColor(int phaseIndex) {
    return _phaseColors[phaseIndex % _phaseColors.length];
  }

  Future<void> _loadSavedPlan() async {
    try {
      final saved =
          await context.read<FirebaseService>().getHerdingPlan(widget.deviceId);
      if (!mounted) return;
      final parsed = saved
          .map(
            (phase) => phase
                .where((p) => p.length >= 2)
                .map((p) => LatLng(p[0], p[1]))
                .toList(),
          )
          .where((phase) => phase.isNotEmpty)
          .toList();

      if (parsed.isNotEmpty) {
        _phases
          ..clear()
          ..addAll(parsed);
        _selectedPhase = 0;
        _center = parsed.first.first;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _fitLoadedPlanIfNeeded() {
    if (_didFitLoadedPlan) return;
    final points = _allPoints;
    if (points.isEmpty) return;
    _didFitLoadedPlan = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length >= 2) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(42),
          ),
        );
        return;
      }
      _mapController.move(points.first, 16);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _addMapPoint(LatLng point) {
    if (_activePhasePoints.length >= _maxPointsPerPhase) {
      _showSnack(
        'Limite por fase atingido ($_maxPointsPerPhase pontos).',
      );
      return;
    }
    setState(() => _activePhasePoints.add(point));
  }

  void _addPhase() {
    if (_phases.length >= _maxPhases) {
      _showSnack('Limite de fases atingido ($_maxPhases).');
      return;
    }
    setState(() {
      _phases.add(<LatLng>[]);
      _selectedPhase = _phases.length - 1;
    });
  }

  void _removeCurrentPhase() {
    if (_phases.length <= 1) return;
    setState(() {
      _phases.removeAt(_selectedPhase);
      if (_selectedPhase >= _phases.length) {
        _selectedPhase = _phases.length - 1;
      }
    });
  }

  Future<void> _publishPlan() async {
    if (_isPublishing) return;
    if (_phases.isEmpty) {
      _showSnack('Adicione ao menos uma fase.');
      return;
    }

    for (var i = 0; i < _phases.length; i++) {
      if (_phases[i].length < 3) {
        _showSnack('A fase ${i + 1} precisa de ao menos 3 pontos.');
        return;
      }
    }

    final uid = context.read<AuthService>().user?.uid;
    if (uid == null) return;
    final firebase = context.read<FirebaseService>();
    final gateway = context.read<GatewayService>();

    final phases = _phases
        .map(
          (phase) =>
              phase.map((p) => <double>[p.latitude, p.longitude]).toList(),
        )
        .toList();

    setState(() => _isPublishing = true);
    try {
      await firebase.saveHerdingPlan(widget.deviceId, uid, phases);
      final gatewayWsHost = await firebase.resolveGatewayWsHostForDevice(
        deviceId: widget.deviceId,
        fallbackGatewayId: widget.gatewayId,
      );
      final sent = await gateway.sendCommandEnsuringConnection(
        deviceId: widget.deviceId,
        command: 'SET_HERDING_PLAN',
        hostOverride: gatewayWsHost,
        payload: {
          'phases': phases,
          'params': {'beepLevel': 2},
        },
      );
      if (!mounted) return;
      if (sent) {
        _showSnack('Plano de condução publicado com sucesso.');
        return;
      }

      final reason = gateway.lastError ?? 'gateway_not_connected';
      _showSnack('Plano salvo, mas falhou o envio para a coleira ($reason).');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao publicar plano: $e');
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _fitLoadedPlanIfNeeded();

    return Scaffold(
      appBar: AppBar(title: const Text('Plano de condução')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey<String>(
                            'herding_phase_dropdown_${_phases.length}_$_selectedPhase',
                          ),
                          initialValue: _selectedPhase,
                          items: List.generate(
                            _phases.length,
                            (i) => DropdownMenuItem<int>(
                              value: i,
                              child: Text(
                                  'Fase ${i + 1} (${_phases[i].length} pts)'),
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedPhase = value);
                          },
                          decoration:
                              const InputDecoration(labelText: 'Fase ativa'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const Key('herding_add_phase_button'),
                        onPressed:
                            _phases.length >= _maxPhases ? null : _addPhase,
                        tooltip: 'Adicionar fase',
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        key: const Key('herding_remove_phase_button'),
                        onPressed:
                            _phases.length <= 1 ? null : _removeCurrentPhase,
                        tooltip: 'Remover fase ativa',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.green.withValues(alpha: 0.08),
                  child: Text(
                    'Toque no mapa para desenhar a fase ${_selectedPhase + 1}. '
                    'Fases: ${_phases.length}/$_maxPhases | '
                    'Pontos: ${_activePhasePoints.length}/$_maxPointsPerPhase',
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 16,
                      onTap: (_, point) => _addMapPoint(point),
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
                          for (var i = 0; i < _phases.length; i++)
                            if (_phases[i].length >= 3)
                              Polygon(
                                points: _phases[i],
                                color: _phaseColor(i).withValues(
                                  alpha: i == _selectedPhase ? 0.28 : 0.14,
                                ),
                                borderColor: _phaseColor(i),
                                borderStrokeWidth: i == _selectedPhase ? 3 : 2,
                              ),
                        ],
                      ),
                      PolylineLayer(
                        polylines: [
                          for (var i = 0; i < _phases.length; i++)
                            if (_phases[i].length >= 2)
                              Polyline(
                                points: _phases[i],
                                strokeWidth: i == _selectedPhase ? 3 : 2,
                                color: _phaseColor(i),
                              ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          for (var phaseIndex = 0;
                              phaseIndex < _phases.length;
                              phaseIndex++)
                            for (final point in _phases[phaseIndex])
                              Marker(
                                point: point,
                                width: 18,
                                height: 18,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _phaseColor(phaseIndex),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: phaseIndex == _selectedPhase
                                          ? Colors.white
                                          : Colors.white70,
                                      width: phaseIndex == _selectedPhase
                                          ? 2.4
                                          : 1.2,
                                    ),
                                  ),
                                ),
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
                          key: const Key('herding_undo_button'),
                          onPressed: _activePhasePoints.isEmpty
                              ? null
                              : () => setState(
                                  () => _activePhasePoints.removeLast()),
                          child: const Text('Desfazer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('herding_clear_phase_button'),
                          onPressed: _activePhasePoints.isEmpty
                              ? null
                              : () =>
                                  setState(() => _activePhasePoints.clear()),
                          child: const Text('Limpar fase'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          key: const Key('herding_publish_button'),
                          onPressed: _isPublishing ? null : _publishPlan,
                          child: _isPublishing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Publicar'),
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
