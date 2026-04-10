import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../models/polygon_map_context.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../utils/cloud_compat.dart';
import '../utils/polygon_edit_session.dart';
import '../utils/polygon_metrics.dart';
import '../utils/top_feedback.dart';
import '../widgets/polygon_editing_map.dart';

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
  final Set<String> _selectedUserUids = <String>{};
  late final PolygonEditSessionController _draftController;

  List<Map<String, String>> _userOptions = const <Map<String, String>>[];
  Set<String> _initialLinkedUserUids = <String>{};
  String _initialOwnerUid = '';
  String? _selectedOwnerUid;
  bool _isSaving = false;
  bool _didTimeout = false;
  bool _isLoadingUsers = false;
  int _viewportRevision = 0;

  bool get _isEditMode => widget.initialProperty != null;

  String? get _editingPropertyId {
    final raw = widget.initialProperty?['id'];
    if (raw == null) return null;
    final id = _normalizeId(raw);
    return id.isEmpty ? null : id;
  }

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
    _draftController = PolygonEditSessionController(
      initialPoints: _initialPropertyPoints(widget.initialProperty),
    );
    _hydrateInitialProperty();
    unawaited(_loadUserOptionsIfNeeded());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _draftController.dispose();
    super.dispose();
  }

  String _normalizeId(dynamic value) {
    if (value is DocumentReference) return value.id;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '';
      if (!trimmed.contains('/')) return trimmed;
      final parts = trimmed.split('/').where((e) => e.isNotEmpty).toList();
      return parts.isEmpty ? '' : parts.last;
    }
    if (value is Map && value['id'] != null) {
      return value['id'].toString().trim();
    }
    if (value == null) return '';
    return value.toString().trim();
  }

  LatLng? _toLatLng(dynamic value) {
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    if (value is LatLng) return value;
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

  List<LatLng> _initialPropertyPoints(Map<String, dynamic>? property) {
    final rawPoints = property?['points'];
    if (rawPoints is! List) return const <LatLng>[];
    return rawPoints.map(_toLatLng).whereType<LatLng>().toList();
  }

  String _extractUserId(dynamic rawUser) => _normalizeId(rawUser);

  Set<String> _extractUserIds(dynamic rawUsers) {
    final out = <String>{};
    if (rawUsers is! List) return out;
    for (final user in rawUsers) {
      final id = _extractUserId(user);
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  void _hydrateInitialProperty() {
    final property = widget.initialProperty;
    if (property == null) return;

    _nameCtrl.text = (property['name'] ?? '').toString().trim();
    _initialLinkedUserUids = _extractUserIds(property['userUids']);
    final ownerId = _extractUserId(property['ownerUid']);
    final createdById = _extractUserId(property['createdByUid']);
    _initialOwnerUid = ownerId.isNotEmpty ? ownerId : createdById;
    if (_initialOwnerUid.isNotEmpty) {
      _selectedOwnerUid = _initialOwnerUid;
    }
  }

  Future<void> _loadUserOptionsIfNeeded() async {
    final auth = context.read<AuthService>();
    if (!auth.isAdmin) return;

    setState(() => _isLoadingUsers = true);
    try {
      final users = await context.read<CloudService>().getUserOptions();
      if (!mounted) return;
      final validUids = users
          .map((user) => (user['uid'] ?? '').trim())
          .where((uid) => uid.isNotEmpty)
          .toSet();
      final seeded = _initialLinkedUserUids.where(validUids.contains).toSet();
      final currentUid = auth.user?.uid;
      final seededOwner =
          _initialOwnerUid.isNotEmpty && validUids.contains(_initialOwnerUid)
              ? _initialOwnerUid
              : null;
      String? ownerToSelect = _selectedOwnerUid;
      if (ownerToSelect == null ||
          ownerToSelect.isEmpty ||
          !validUids.contains(ownerToSelect)) {
        if (seededOwner != null) {
          ownerToSelect = seededOwner;
        } else if (currentUid != null && validUids.contains(currentUid)) {
          ownerToSelect = currentUid;
        } else if (users.isNotEmpty) {
          ownerToSelect = (users.first['uid'] ?? '').trim();
        }
      }
      setState(() {
        _userOptions = users;
        _isLoadingUsers = false;
        _selectedOwnerUid = ownerToSelect;
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

    List<LatLng> best = <LatLng>[];
    for (final match in matches) {
      final raw = match.group(1);
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

  Future<List<int>?> _readSelectedFileBytes(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }

    final stream = file.readStream;
    if (stream == null) {
      return null;
    }

    final buffer = BytesBuilder(copy: false);
    try {
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          buffer.add(chunk);
        }
      }
    } catch (_) {
      return null;
    }

    final collected = buffer.takeBytes();
    return collected.isEmpty ? null : collected;
  }

  Future<void> _importKml() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['kml'],
      withData: true,
      withReadStream: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = await _readSelectedFileBytes(file);
    String? kmlText;
    if (bytes != null && bytes.isNotEmpty) {
      kmlText = utf8.decode(bytes, allowMalformed: true);
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

    _draftController.replaceAllPoints(imported);
    if (!mounted) return;
    setState(() => _viewportRevision++);
    AppFeedback.success('KML importado com ${imported.length} pontos.');
  }

  String _emailForUid(String uid) {
    final user = _userOptions.cast<Map<String, String>?>().firstWhere(
          (option) => (option?['uid'] ?? '').trim() == uid,
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
              final filtered = _userOptions.where((user) {
                final email = (user['email'] ?? '').trim().toLowerCase();
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
                                itemBuilder: (_, index) {
                                  final user = filtered[index];
                                  final uid = (user['uid'] ?? '').trim();
                                  final email = (user['email'] ?? uid).trim();
                                  final checked = tempSelected.contains(uid);
                                  return CheckboxListTile(
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: checked,
                                    title: Text(email),
                                    onChanged: (value) {
                                      setPickerState(() {
                                        if (value == true) {
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
      await context.read<CloudService>().deleteRuralProperty(id: id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      await _showMessage('Erro', 'Erro ao apagar propriedade: $e');
      setState(() => _isSaving = false);
    }
  }

  String? _contextOwnerUid(AuthService auth) {
    final candidate = auth.isAdmin ? _selectedOwnerUid : auth.user?.uid;
    final normalized = candidate?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  bool _propertyBelongsToOwner(
    Map<String, dynamic> property,
    String ownerUid,
  ) {
    final propertyOwner = _normalizeId(property['ownerUid']);
    if (propertyOwner == ownerUid) return true;
    final createdBy = _normalizeId(property['createdByUid']);
    return createdBy == ownerUid;
  }

  LatLng? _devicePosition(DeviceModel device) {
    final lat = device.lat;
    final lon = device.lon;
    if (lat == null || lon == null) return null;
    if (!lat.isFinite || !lon.isFinite) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  LatLng? _gatewayPosition(Map<String, dynamic> gateway) {
    final lat = gateway['lat'];
    final lon = gateway['lon'];
    if (lat is! num || lon is! num) return null;
    final parsedLat = lat.toDouble();
    final parsedLon = lon.toDouble();
    if (!parsedLat.isFinite || !parsedLon.isFinite) return null;
    if (parsedLat < -90 ||
        parsedLat > 90 ||
        parsedLon < -180 ||
        parsedLon > 180) {
      return null;
    }
    return LatLng(parsedLat, parsedLon);
  }

  String _gatewayLabel(Map<String, dynamic> gateway) {
    final name = (gateway['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final id = _normalizeId(gateway['id'] ?? gateway['gatewayId']);
    return id.isEmpty ? 'Gateway' : id;
  }

  bool _gatewayAccessibleToOwner(
    Map<String, dynamic> gateway,
    String ownerUid,
    Set<String> ownerPropertyIds,
  ) {
    final linkedUserIds = _extractUserIds(gateway['userUids']);
    if (linkedUserIds.contains(ownerUid)) {
      return true;
    }
    final propertyId = _normalizeId(gateway['propertyId']);
    return propertyId.isNotEmpty && ownerPropertyIds.contains(propertyId);
  }

  PolygonMapContext _buildMapContext({
    required AuthService auth,
    required List<Map<String, dynamic>> properties,
    required List<Map<String, dynamic>> areas,
    required List<DeviceModel> devices,
    required List<Map<String, dynamic>> gateways,
  }) {
    if (_isEditMode) {
      final propertyId = _editingPropertyId;
      if (propertyId == null || propertyId.isEmpty) {
        return const PolygonMapContext();
      }

      final areaPolygons = areas
          .where((area) => _normalizeId(area['propertyId']) == propertyId)
          .map((area) {
            final raw = (area['perimeter'] as List?) ?? const <dynamic>[];
            return raw.map(_toLatLng).whereType<LatLng>().toList();
          })
          .where((polygon) => polygon.length >= 3)
          .toList();

      final propertyDevices = devices
          .where((device) => (device.propertyId ?? '').trim() == propertyId)
          .map((device) {
            final point = _devicePosition(device);
            if (point == null) return null;
            return PolygonMapDeviceOverlay(
              id: device.loraDeviceId ?? device.id,
              label: device.name,
              point: point,
            );
          })
          .whereType<PolygonMapDeviceOverlay>()
          .toList();

      final propertyGateways = gateways
          .where((gateway) => _normalizeId(gateway['propertyId']) == propertyId)
          .map((gateway) {
            final point = _gatewayPosition(gateway);
            if (point == null) return null;
            return PolygonMapGatewayOverlay(
              id: _normalizeId(gateway['id'] ?? gateway['gatewayId']),
              label: _gatewayLabel(gateway),
              point: point,
            );
          })
          .whereType<PolygonMapGatewayOverlay>()
          .toList();

      return PolygonMapContext(
        areaPolygons: areaPolygons,
        devices: propertyDevices,
        gateways: propertyGateways,
      );
    }

    final ownerUid = _contextOwnerUid(auth);
    if (ownerUid == null || ownerUid.isEmpty) {
      return const PolygonMapContext();
    }

    final ownerPropertyIds = properties
        .where((property) => _propertyBelongsToOwner(property, ownerUid))
        .map((property) => _normalizeId(property['id']))
        .where((id) => id.isNotEmpty)
        .toSet();

    final ownerDevices = devices
        .where((device) => (device.ownerUid ?? '').trim() == ownerUid)
        .map((device) {
          final point = _devicePosition(device);
          if (point == null) return null;
          return PolygonMapDeviceOverlay(
            id: device.loraDeviceId ?? device.id,
            label: device.name,
            point: point,
          );
        })
        .whereType<PolygonMapDeviceOverlay>()
        .toList();

    final ownerGateways = gateways
        .where(
          (gateway) =>
              _gatewayAccessibleToOwner(gateway, ownerUid, ownerPropertyIds),
        )
        .map((gateway) {
          final point = _gatewayPosition(gateway);
          if (point == null) return null;
          return PolygonMapGatewayOverlay(
            id: _normalizeId(gateway['id'] ?? gateway['gatewayId']),
            label: _gatewayLabel(gateway),
            point: point,
          );
        })
        .whereType<PolygonMapGatewayOverlay>()
        .toList();

    return PolygonMapContext(
      devices: ownerDevices,
      gateways: ownerGateways,
    );
  }

  Object _viewportSignature(AuthService auth) {
    if (_isEditMode) {
      return 'property:${_editingPropertyId ?? ''}:$_viewportRevision';
    }
    return 'owner:${_contextOwnerUid(auth) ?? ''}:$_viewportRevision';
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_nameCtrl.text.trim().isEmpty) {
      _showMessage('Campo obrigatorio', 'Informe o nome da propriedade.');
      return;
    }
    if (_draftController.points.length < 3) {
      _showMessage(
        'Pontos insuficientes',
        'Desenhe ao menos 3 pontos no mapa.',
      );
      return;
    }

    final auth = context.read<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final ownerUid = auth.isAdmin ? _selectedOwnerUid?.trim() : uid;
    if (ownerUid == null || ownerUid.isEmpty) {
      await _showMessage(
        'Campo obrigatorio',
        'Selecione o dono da propriedade.',
      );
      return;
    }

    final emails = _selectedUserUids
        .map(_emailForUid)
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toList();

    final points = _draftController.points
        .map((point) => <double>[point.latitude, point.longitude])
        .toList();
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

      final firebase = context.read<CloudService>();
      if (_isEditMode) {
        final id = _editingPropertyId;
        if (id == null || id.isEmpty) {
          throw Exception('id_da_propriedade_invalido');
        }
        await firebase
            .updateRuralProperty(
              id: id,
              name: _nameCtrl.text.trim(),
              points: points,
              editorUid: uid,
              ownerUid: ownerUid,
              isAdmin: auth.isAdmin,
              userEmails: emails,
            )
            .timeout(const Duration(seconds: 15));
      } else {
        await firebase
            .addRuralProperty(
              name: _nameCtrl.text.trim(),
              points: points,
              creatorUid: uid,
              ownerUid: ownerUid,
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
    } on CloudException catch (e) {
      if (!mounted) return;
      await _showMessage(
        'Erro de backend',
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
    final uid = auth.user?.uid;
    if (uid == null || uid.trim().isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedEmails = _selectedUserUids.map(_emailForUid).toList()..sort();
    final ownerOptions = <Map<String, String>>[..._userOptions];
    final ownerUid = _selectedOwnerUid?.trim();
    if (ownerUid != null &&
        ownerUid.isNotEmpty &&
        ownerOptions.every((user) => (user['uid'] ?? '').trim() != ownerUid)) {
      ownerOptions
          .insert(0, <String, String>{'uid': ownerUid, 'email': ownerUid});
    }
    final ownerValue = ownerUid != null &&
            ownerUid.isNotEmpty &&
            ownerOptions.any((user) => (user['uid'] ?? '').trim() == ownerUid)
        ? ownerUid
        : null;
    final firebase = context.read<CloudService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Editar propriedade rural' : 'Nova propriedade rural',
        ),
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
              child: DropdownButtonFormField<String>(
                key: const Key('property_owner_dropdown'),
                initialValue: ownerValue,
                decoration:
                    const InputDecoration(labelText: 'Dono da propriedade'),
                items: ownerOptions
                    .map(
                      (user) => DropdownMenuItem<String>(
                        value: (user['uid'] ?? '').trim(),
                        child: Text(
                          (user['email'] ?? user['uid'] ?? '').trim(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _isSaving || _isLoadingUsers
                    ? null
                    : (value) => setState(() => _selectedOwnerUid = value),
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
                    hintText: 'Nenhum email selecionado',
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
                      : selectedEmails.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              selectedEmails.join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
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
          AnimatedBuilder(
            animation: _draftController,
            builder: (context, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.green.withValues(alpha: 0.08),
                child: Text(
                  'Toque no mapa para adicionar os primeiros pontos. Toque em um ponto para mover e no perimetro para inserir novos pontos. '
                  'Pontos: ${_draftController.points.length}',
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: firebase.streamRuralProperties(
                uid: uid,
                isAdmin: auth.isAdmin,
              ),
              builder: (context, propertySnap) {
                if (propertySnap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar propriedades: ${propertySnap.error}',
                    ),
                  );
                }
                final properties =
                    propertySnap.data ?? const <Map<String, dynamic>>[];

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: firebase.streamAreas(uid: uid, isAdmin: auth.isAdmin),
                  builder: (context, areaSnap) {
                    if (areaSnap.hasError) {
                      return Center(
                        child:
                            Text('Erro ao carregar areas: ${areaSnap.error}'),
                      );
                    }
                    final areas =
                        areaSnap.data ?? const <Map<String, dynamic>>[];

                    return StreamBuilder<List<DeviceModel>>(
                      stream: firebase.streamDevices(
                        uid: uid,
                        isAdmin: auth.isAdmin,
                      ),
                      builder: (context, deviceSnap) {
                        if (deviceSnap.hasError) {
                          return Center(
                            child: Text(
                              'Erro ao carregar coleiras: ${deviceSnap.error}',
                            ),
                          );
                        }
                        final devices =
                            deviceSnap.data ?? const <DeviceModel>[];

                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: firebase.streamGateways(
                            uid: uid,
                            isAdmin: auth.isAdmin,
                          ),
                          builder: (context, gatewaySnap) {
                            if (gatewaySnap.hasError) {
                              return Center(
                                child: Text(
                                  'Erro ao carregar gateways: ${gatewaySnap.error}',
                                ),
                              );
                            }
                            final gateways = gatewaySnap.data ??
                                const <Map<String, dynamic>>[];
                            final mapContext = _buildMapContext(
                              auth: auth,
                              properties: properties,
                              areas: areas,
                              devices: devices,
                              gateways: gateways,
                            );

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: PolygonEditingMap(
                                  controller: _draftController,
                                  contextData: mapContext,
                                  allowFreeAdd: !_isEditMode,
                                  viewportSignature: _viewportSignature(auth),
                                  boundaryFillColor: const Color(0x26FF9800),
                                  boundaryBorderColor: const Color(0xFFE65100),
                                  areaFillColor: const Color(0x26009688),
                                  areaBorderColor: const Color(0xFF00897B),
                                  draftFillColor: const Color(0x4DFF9800),
                                  draftBorderColor: const Color(0xFFE65100),
                                  vertexColor: const Color(0xFFE65100),
                                  selectedVertexColor: const Color(0xFFC62828),
                                  idleTapMessage: _isEditMode
                                      ? 'Toque em um ponto para mover ou no perimetro para inserir novo ponto.'
                                      : 'Toque em um ponto para mover, no perimetro para inserir ou em uma area livre para adicionar.',
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: _draftController,
            builder: (context, _) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.green.withValues(alpha: 0.08),
                child: Text(
                  'Area da edicao: ${PolygonMetrics.areaTextInline(_draftController.points)}'
                  ' | Pontos: ${_draftController.points.length}',
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _draftController,
            builder: (context, _) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('property_clear_points_button'),
                        onPressed: _isSaving || _draftController.points.isEmpty
                            ? null
                            : _draftController.clear,
                        child: const Text('Limpar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('property_undo_point_button'),
                        onPressed: _isSaving || !_draftController.canUndo
                            ? null
                            : _draftController.undo,
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
