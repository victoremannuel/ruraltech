import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/manual_settings.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class RuralPropertyEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? initialProperty;

  const RuralPropertyEditorScreen({
    super.key,
    this.initialProperty,
  });

  @override
  State<RuralPropertyEditorScreen> createState() =>
      _RuralPropertyEditorScreenState();
}

class _RuralPropertyEditorScreenState extends State<RuralPropertyEditorScreen> {
  final _nameCtrl = TextEditingController();
  final List<LatLng> _points = [];
  final LatLng _fallbackCenter = const LatLng(-23.0, -46.0);
  final MapController _mapController = MapController();
  final Set<String> _selectedUserUids = <String>{};

  List<Map<String, String>> _userOptions = const <Map<String, String>>[];
  Set<String> _initialLinkedUserUids = <String>{};
  bool _isSaving = false;
  bool _didTimeout = false;
  bool _isLoadingUsers = false;
  bool _fitDone = false;

  bool get _isEditMode => widget.initialProperty != null;

  String? get _editingPropertyId {
    final raw = widget.initialProperty?['id'];
    if (raw == null) return null;
    final id = raw.toString().trim();
    return id.isEmpty ? null : id;
  }

  LatLng get _initialCenter =>
      _points.isNotEmpty ? _points.first : _fallbackCenter;

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
  void initState() {
    super.initState();
    _hydrateInitialProperty();
    unawaited(_loadUserOptionsIfNeeded());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  LatLng? _toLatLng(dynamic value) {
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    if (value is List && value.length >= 2) {
      final a = value[0];
      final b = value[1];
      if (a is num && b is num) return LatLng(a.toDouble(), b.toDouble());
      if (a is GeoPoint) return LatLng(a.latitude, a.longitude);
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

  Set<String> _extractUserIds(dynamic rawUsers) {
    final out = <String>{};
    if (rawUsers is! List) return out;
    for (final u in rawUsers) {
      String id = '';
      if (u is DocumentReference) {
        id = u.id;
      } else if (u is String) {
        final trimmed = u.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.contains('/')) {
          final parts = trimmed.split('/').where((e) => e.isNotEmpty).toList();
          id = parts.isEmpty ? '' : parts.last;
        } else {
          id = trimmed;
        }
      } else if (u is Map && u['id'] != null) {
        id = u['id'].toString().trim();
      }
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  void _hydrateInitialProperty() {
    final p = widget.initialProperty;
    if (p == null) return;

    _nameCtrl.text = (p['name'] ?? '').toString().trim();
    _initialLinkedUserUids = _extractUserIds(p['userUids']);

    final rawPoints = p['points'];
    if (rawPoints is List) {
      final parsed = rawPoints.map(_toLatLng).whereType<LatLng>().toList();
      if (parsed.length >= 3) {
        _points
          ..clear()
          ..addAll(parsed);
      }
    }
  }

  void _fitToPoints(List<LatLng> points) {
    if (_fitDone || points.length < 2) return;
    _fitDone = true;
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

  Future<void> _loadUserOptionsIfNeeded() async {
    final auth = context.read<AuthService>();
    if (!auth.isAdmin) return;

    setState(() => _isLoadingUsers = true);
    try {
      final users = await context.read<FirebaseService>().getUserOptions();
      if (!mounted) return;
      final validUids = users
          .map((u) => (u['uid'] ?? '').trim())
          .where((u) => u.isNotEmpty)
          .toSet();
      final seeded = _initialLinkedUserUids.where(validUids.contains).toSet();
      setState(() {
        _userOptions = users;
        _isLoadingUsers = false;
        if (_selectedUserUids.isEmpty && seeded.isNotEmpty) {
          _selectedUserUids
            ..clear()
            ..addAll(seeded);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingUsers = false);
    }
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
      _fitDone = false;
    });
    _fitToPoints(imported);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('KML importado com ${imported.length} pontos.')),
    );
  }

  String _emailForUid(String uid) {
    final user = _userOptions.cast<Map<String, String>?>().firstWhere(
          (u) => (u?['uid'] ?? '').trim() == uid,
          orElse: () => null,
        );
    return (user?['email'] ?? uid).trim();
  }

  Future<void> _showUsersDropdownPicker() async {
    if (_isLoadingUsers || _isSaving) return;
    final searchCtrl = TextEditingController();
    final tempSelected = <String>{..._selectedUserUids};
    var confirmed = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (pickerContext) {
          return StatefulBuilder(
            builder: (context, setPickerState) {
              final query = searchCtrl.text.trim().toLowerCase();
              final filtered = _userOptions.where((u) {
                final email = (u['email'] ?? '').trim().toLowerCase();
                return query.isEmpty || email.contains(query);
              }).toList();

              return AlertDialog(
                title: const Text('Selecionar emails'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Buscar email',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setPickerState(() {}),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: filtered.isEmpty
                            ? const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Nenhum email encontrado.'),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final user = filtered[i];
                                  final uid = (user['uid'] ?? '').trim();
                                  final email = (user['email'] ?? uid).trim();
                                  final checked = tempSelected.contains(uid);
                                  return CheckboxListTile(
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: checked,
                                    title: Text(email),
                                    onChanged: (v) {
                                      setPickerState(() {
                                        if (v == true) {
                                          tempSelected.add(uid);
                                        } else {
                                          tempSelected.remove(uid);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(pickerContext),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      confirmed = true;
                      Navigator.pop(pickerContext);
                    },
                    child: const Text('Aplicar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchCtrl.dispose();
    }

    if (!confirmed || !mounted) return;
    setState(() {
      _selectedUserUids
        ..clear()
        ..addAll(tempSelected);
    });
  }

  Future<void> _deleteProperty() async {
    final id = _editingPropertyId;
    if (id == null || id.isEmpty || _isSaving) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Apagar propriedade'),
            content: const Text(
              'Deseja apagar esta propriedade? Essa acao remove tambem areas/gateways/coleiras vinculados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Apagar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await context.read<FirebaseService>().deleteRuralProperty(id: id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      await _showMessage('Erro', 'Erro ao apagar propriedade: $e');
      setState(() => _isSaving = false);
    }
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

    final emails = _selectedUserUids
        .map(_emailForUid)
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

      final fb = context.read<FirebaseService>();
      if (_isEditMode) {
        final id = _editingPropertyId;
        if (id == null || id.isEmpty) {
          throw Exception('id_da_propriedade_invalido');
        }
        await fb
            .updateRuralProperty(
              id: id,
              name: _nameCtrl.text.trim(),
              points: points,
              editorUid: uid,
              isAdmin: auth.isAdmin,
              userEmails: emails,
            )
            .timeout(const Duration(seconds: 15));
      } else {
        await fb
            .addRuralProperty(
              name: _nameCtrl.text.trim(),
              points: points,
              creatorUid: uid,
              isAdmin: auth.isAdmin,
              userEmails: emails,
            )
            .timeout(const Duration(seconds: 15));
      }

      if (_didTimeout) return;
      if (!mounted) return;
      await _showMessage(
        'Sucesso',
        _isEditMode
            ? 'Propriedade rural atualizada com sucesso.'
            : 'Propriedade rural salva com sucesso.',
      );
      if (mounted) Navigator.pop(context, true);
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
    _fitToPoints(_points);
    final selectedEmails = _selectedUserUids.map(_emailForUid).toList()..sort();
    final selectedEmailsText = selectedEmails.isEmpty
        ? 'Nenhum email selecionado'
        : selectedEmails.join(', ');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode
            ? 'Editar propriedade rural'
            : 'Nova propriedade rural'),
        actions: [
          if (_isEditMode && auth.isAdmin)
            IconButton(
              key: const Key('property_delete_button'),
              onPressed: _isSaving ? null : _deleteProperty,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Apagar propriedade',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              key: const Key('property_name_input'),
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nome da propriedade'),
            ),
          ),
          if (auth.isAdmin)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: InkWell(
                key: const Key('property_users_picker'),
                onTap: _isSaving || _isLoadingUsers
                    ? null
                    : _showUsersDropdownPicker,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Usuarios com acesso (emails)',
                    helperText:
                        'Toque para abrir a lista e pesquisar; selecione um ou mais emails.',
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  isEmpty: selectedEmails.isEmpty,
                  child: _isLoadingUsers
                      ? const SizedBox(
                          height: 20,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Text(selectedEmailsText),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('property_import_kml_button'),
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
              'Desenhe no mapa ou importe KML (${_points.length} pontos)',
            ),
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
                  userAgentPackageName: ManualSettings.mapUserAgentPackageName,
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
                    key: const Key('property_clear_points_button'),
                    onPressed: _isSaving || _points.isEmpty
                        ? null
                        : () => setState(() {
                              _points.clear();
                              _fitDone = false;
                            }),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('property_undo_point_button'),
                    onPressed: _isSaving || _points.isEmpty
                        ? null
                        : () => setState(() {
                              _points.removeLast();
                              _fitDone = false;
                            }),
                    child: const Text('Desfazer'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('property_save_button'),
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
