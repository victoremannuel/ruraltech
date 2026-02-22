import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class RuralPropertyEditorScreen extends StatefulWidget {
  const RuralPropertyEditorScreen({super.key});

  @override
  State<RuralPropertyEditorScreen> createState() =>
      _RuralPropertyEditorScreenState();
}

class _RuralPropertyEditorScreenState extends State<RuralPropertyEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _userEmailsCtrl = TextEditingController();
  final List<LatLng> _points = [];
  final LatLng _initialCenter = const LatLng(-23.0, -46.0);
  final MapController _mapController = MapController();
  bool _isSaving = false;
  bool _didTimeout = false;

  Future<void> _showMessage(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userEmailsCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<LatLng> _extractPolygonFromKml(String kml) {
    final matches = RegExp(
      r'<coordinates[^>]*>([\s\S]*?)</coordinates>',
      caseSensitive: false,
    ).allMatches(kml);

    List<LatLng> best = [];
    for (final m in matches) {
      final raw = m.group(1);
      if (raw == null || raw.trim().isEmpty) continue;

      final points = <LatLng>[];
      for (final token in raw.trim().split(RegExp(r'\s+'))) {
        if (token.trim().isEmpty) continue;
        final parts = token.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lat == null || lon == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
        points.add(LatLng(lat, lon));
      }

      if (points.length >= 3) {
        final first = points.first;
        final last = points.last;
        if ((first.latitude - last.latitude).abs() < 1e-9 &&
            (first.longitude - last.longitude).abs() < 1e-9) {
          points.removeLast();
        }
      }

      if (points.length >= 3 && points.length > best.length) {
        best = points;
      }
    }

    return best;
  }

  void _fitToPoints(List<LatLng> points) {
    if (points.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(42),
        ),
      );
    });
  }

  Future<void> _importKml() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kml'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    String? kmlText;
    if (bytes != null && bytes.isNotEmpty) {
      kmlText = utf8.decode(bytes, allowMalformed: true);
    } else if (file.path != null && file.path!.isNotEmpty) {
      try {
        final rawBytes = await File(file.path!).readAsBytes();
        if (rawBytes.isNotEmpty) {
          kmlText = utf8.decode(rawBytes, allowMalformed: true);
        }
      } catch (_) {}
    }
    if (kmlText == null || kmlText.trim().isEmpty) {
      await _showMessage(
        'Erro de arquivo',
        'Nao foi possivel ler o KML selecionado.',
      );
      return;
    }
    final imported = _extractPolygonFromKml(kmlText);
    if (imported.length < 3) {
      await _showMessage(
        'KML invalido',
        'Nao foi encontrado poligono valido com ao menos 3 pontos.',
      );
      return;
    }

    setState(() {
      _points
        ..clear()
        ..addAll(imported);
    });
    _fitToPoints(imported);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('KML importado com ${imported.length} pontos.')),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_nameCtrl.text.trim().isEmpty) {
      _showMessage('Campo obrigatorio', 'Informe o nome da propriedade.');
      return;
    }
    if (_points.length < 3) {
      _showMessage(
        'Pontos insuficientes',
        'Desenhe ao menos 3 pontos no mapa.',
      );
      return;
    }

    final auth = context.read<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final emails = _userEmailsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final points = _points.map((p) => [p.latitude, p.longitude]).toList();
    setState(() => _isSaving = true);
    _didTimeout = false;
    Timer? watchdog;
    try {
      watchdog = Timer(const Duration(seconds: 16), () async {
        if (!mounted || !_isSaving) return;
        _didTimeout = true;
        setState(() => _isSaving = false);
        await _showMessage(
          'Tempo limite',
          'A gravacao nao respondeu. Verifique internet/firestore e tente novamente.',
        );
      });
      await context
          .read<FirebaseService>()
          .addRuralProperty(
            name: _nameCtrl.text.trim(),
            points: points,
            creatorUid: uid,
            isAdmin: auth.isAdmin,
            userEmails: emails,
          )
          .timeout(const Duration(seconds: 15));
      if (_didTimeout) return;
      if (!mounted) return;
      await _showMessage(
        'Sucesso',
        'Propriedade rural salva com sucesso.',
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      await _showMessage(
        'Erro Firebase',
        '${e.code}: ${e.message ?? 'Falha ao salvar a propriedade.'}',
      );
    } on TimeoutException catch (e) {
      if (_didTimeout) return;
      if (!mounted) return;
      await _showMessage(
        'Tempo limite',
        e.message ?? 'A operacao excedeu o tempo limite.',
      );
    } catch (e) {
      if (!mounted) return;
      await _showMessage(
        'Erro',
        'Erro ao salvar propriedade: $e',
      );
    } finally {
      watchdog?.cancel();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nova propriedade rural')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nome da propriedade'),
            ),
          ),
          if (auth.isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _userEmailsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Emails user (separados por virgula)',
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _importKml,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importar KML'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.08),
            child: Text(
                'Desenhe no mapa ou importe KML (${_points.length} pontos)'),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
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
                        color: Colors.orange.withValues(alpha: 0.3),
                        borderColor: Colors.orange.shade800,
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
                              color: Colors.orange.shade800,
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
                    onPressed: _isSaving || _points.isEmpty
                        ? null
                        : () => setState(() => _points.clear()),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving || _points.isEmpty
                        ? null
                        : () => setState(() => _points.removeLast()),
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar'),
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
