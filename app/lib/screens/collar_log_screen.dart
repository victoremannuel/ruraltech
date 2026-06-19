import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../components/map/rt_filter_chips.dart';
import '../components/primitives/rt_badge.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/device_model.dart';
import '../services/cloud_service.dart';
import '../utils/polygon_log_preview.dart';

/// Log da coleira em tema escuro ("terminal-style"), conforme Sprint 4 do
/// redesign v2. Mantém a lógica de auto-refresh + manual refresh e adiciona
/// chips de filtro por tipo de evento.
class CollarLogScreen extends StatefulWidget {
  final DeviceModel device;

  const CollarLogScreen({super.key, required this.device});

  @override
  State<CollarLogScreen> createState() => _CollarLogScreenState();
}

class _CollarLogScreenState extends State<CollarLogScreen> {
  bool _autoRefresh = false;
  late Future<List<Map<String, dynamic>>> _manualFuture;
  final Map<String, Future<PolygonLogPreviewResolution>> _previewFutures =
      <String, Future<PolygonLogPreviewResolution>>{};

  static const _filterAll = 'all';
  static const _filterTelemetry = 'telemetry';
  static const _filterHealth = 'health_daily';
  static const _filterPolygon = 'polygon';
  static const _filterOther = 'other';

  String _selectedFilter = _filterAll;

  static final Color _terminalBg = RTColors.ink;
  static final Color _terminalSurface = Color.alphaBlend(
    Colors.white.withValues(alpha: 0.04),
    RTColors.ink,
  );
  static final Color _terminalBorder = Colors.white.withValues(alpha: 0.10);
  static final Color _terminalInk = Colors.white.withValues(alpha: 0.92);
  static final Color _terminalInkSoft = Colors.white.withValues(alpha: 0.60);

  @override
  void initState() {
    super.initState();
    _manualFuture = _loadLog();
  }

  String? get _propertyId {
    final value = widget.device.propertyId?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? get _deviceId => widget.device.loraDeviceId;

  Future<List<Map<String, dynamic>>> _loadLog() {
    final propertyId = _propertyId;
    final deviceId = _deviceId;
    if (propertyId == null || deviceId == null) {
      return Future.value(const <Map<String, dynamic>>[]);
    }
    return context.read<CloudService>().getCollarLog(
          propertyId: propertyId,
          deviceId: deviceId,
        );
  }

  void _refreshManually() {
    setState(() {
      _manualFuture = _loadLog();
    });
  }

  String _formatTimestamp(int? ms) {
    if (ms == null || ms <= 0) return '--/--/---- --:--:--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  String _titleForEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString();
    final kind = (entry['kind'] ?? '').toString();
    if (_isPolygonAuditEntry(entry)) {
      final label = _polygonLabel(entry);
      return _isPolygonAuditSuccess(entry)
          ? 'Gravação OK · $label'
          : 'Falha gravação · $label';
    }
    if (type == 'telemetry') return 'Telemetria';
    if (type == 'health_daily') return 'Saúde diária';
    if (kind.isNotEmpty) return kind;
    return 'Evento';
  }

  String _typeTagForEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString();
    if (_isPolygonAuditEntry(entry)) {
      return _isPolygonAuditSuccess(entry) ? 'POLY_OK' : 'POLY_ERR';
    }
    if (type == 'telemetry') return 'TELEMETRY';
    if (type == 'health_daily') return 'HEALTH';
    final kind = (entry['kind'] ?? '').toString().trim().toUpperCase();
    return kind.isEmpty ? 'EVENT' : kind;
  }

  RTTone _toneForEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString();
    if (_isPolygonAuditEntry(entry)) {
      return _isPolygonAuditSuccess(entry) ? RTTone.ok : RTTone.danger;
    }
    if (type == 'telemetry') return RTTone.info;
    if (type == 'health_daily') return RTTone.primary;
    return RTTone.neutral;
  }

  String _subtitleForEntry(Map<String, dynamic> entry) {
    final parts = <String>[];
    final type = (entry['type'] ?? '').toString();
    if (type == 'telemetry') {
      final lat = entry['lat'] as double?;
      final lon = entry['lon'] as double?;
      if (lat != null && lon != null) {
        parts.add('${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}');
      }
    } else if (type == 'health_daily') {
      final sat = entry['sat'];
      final temperatureDeciC = entry['temperatureDeciC'];
      if (temperatureDeciC is int) {
        parts.add('temp ${(temperatureDeciC / 10.0).toStringAsFixed(1)}°C');
      }
      if (sat != null) parts.add('sat $sat');
    } else if (_isPolygonAuditEntry(entry)) {
      final command = (entry['command'] ?? '').toString().trim();
      if (command.isNotEmpty) parts.add(command);
      final cmdId = (entry['cmdId'] ?? '').toString().trim();
      if (cmdId.isNotEmpty) parts.add('cmd=$cmdId');
    } else {
      final kind = (entry['kind'] ?? '').toString().trim();
      if (kind.isNotEmpty) parts.add(kind);
    }
    final gatewayId = (entry['gatewayId'] ?? '').toString().trim();
    if (gatewayId.isNotEmpty) parts.add('gw=$gatewayId');
    final gatewayRole = (entry['gatewayRole'] ?? '').toString().trim();
    if (gatewayRole.isNotEmpty) parts.add(gatewayRole);
    return parts.join(' · ');
  }

  bool _isPolygonAuditEntry(Map<String, dynamic> entry) {
    return (entry['eventType'] ?? '').toString().trim().toLowerCase() ==
        'polygon_apply_result';
  }

  String _polygonAuditStatus(Map<String, dynamic> entry) {
    return (entry['status'] ?? '').toString().trim().toLowerCase();
  }

  bool _isPolygonAuditSuccess(Map<String, dynamic> entry) {
    return _polygonAuditStatus(entry) == 'success';
  }

  String _polygonLabel(Map<String, dynamic> entry) {
    final polygonKind = (entry['polygonKind'] ?? '').toString().trim();
    if (polygonKind.isNotEmpty) {
      return polygonLogPreviewKindLabel(polygonKind).toLowerCase();
    }
    final originDocType = (entry['originDocType'] ?? '').toString().trim();
    if (originDocType == 'ruralProperty') return 'fazenda';
    if (originDocType == 'area') return 'piquete';
    if (originDocType == 'herdingOperation') return 'condução';
    return 'polígono';
  }

  String _friendlyPolygonFailure(Map<String, dynamic> entry) {
    final errorCode = (entry['errorCode'] ?? '').toString().trim();
    final errorStage = (entry['errorStage'] ?? '').toString().trim();
    final source = entry['fallbackFromCommandTrail'] == true
        ? 'Falha inferida pelo trilho de comando'
        : 'Falha reportada pela coleira';
    if (errorCode.isEmpty && errorStage.isEmpty) return source;
    final parts = <String>[source];
    if (errorStage.isNotEmpty) parts.add('etapa $errorStage');
    if (errorCode.isNotEmpty) parts.add(errorCode);
    return parts.join(' · ');
  }

  Future<PolygonLogPreviewResolution> _previewForEntry(
    Map<String, dynamic> entry,
  ) {
    final entryId = (entry['id'] ?? '').toString();
    return _previewFutures.putIfAbsent(
      entryId,
      () => context.read<CloudService>().resolvePolygonLogPreview(
            propertyId: _propertyId!,
            device: widget.device,
            entry: entry,
          ),
    );
  }

  String _prettyJson(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  bool _matchesFilter(Map<String, dynamic> entry) {
    if (_selectedFilter == _filterAll) return true;
    final type = (entry['type'] ?? '').toString();
    final isPoly = _isPolygonAuditEntry(entry);
    switch (_selectedFilter) {
      case _filterTelemetry:
        return type == 'telemetry';
      case _filterHealth:
        return type == 'health_daily';
      case _filterPolygon:
        return isPoly;
      case _filterOther:
        return !isPoly && type != 'telemetry' && type != 'health_daily';
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = _propertyId;
    final deviceId = _deviceId;

    return Scaffold(
      backgroundColor: _terminalBg,
      appBar: AppBar(
        backgroundColor: _terminalBg,
        foregroundColor: _terminalInk,
        elevation: 0,
        title: Text(
          'Log ${widget.device.networkId}',
          style: RTTypography.mono.copyWith(
            color: _terminalInk,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: _terminalInk),
        actions: [
          IconButton(
            tooltip: 'Atualizar manual',
            icon: const Icon(Icons.refresh),
            onPressed: _autoRefresh ? null : _refreshManually,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControlBar(),
          Divider(height: 1, color: _terminalBorder),
          Expanded(
            child: (propertyId == null || deviceId == null)
                ? _emptyMessage(
                    'A coleira precisa ter propriedade vinculada e ID LoRa válido para exibir o log.',
                  )
                : _autoRefresh
                    ? StreamBuilder<List<Map<String, dynamic>>>(
                        stream: context.read<CloudService>().streamCollarLog(
                              propertyId: propertyId,
                              deviceId: deviceId,
                            ),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _emptyMessage(
                              'Falha ao carregar log em tempo real: ${snapshot.error}',
                            );
                          }
                          final items = snapshot.data ??
                              const <Map<String, dynamic>>[];
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              items.isEmpty) {
                            return _loading();
                          }
                          return _buildLogList(items);
                        },
                      )
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future: _manualFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _emptyMessage(
                              'Falha ao carregar log: ${snapshot.error}',
                            );
                          }
                          final items = snapshot.data ??
                              const <Map<String, dynamic>>[];
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              items.isEmpty) {
                            return _loading();
                          }
                          return _buildLogList(items);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      color: _terminalBg,
      padding: const EdgeInsets.fromLTRB(
        0,
        RTSpacing.x2,
        RTSpacing.x4,
        RTSpacing.x2,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Theme(
                  data: ThemeData.dark(),
                  child: RTFilterChips(
                    chips: const [
                      RTFilterChipData(
                        id: _filterAll,
                        label: 'Todos',
                        icon: Icons.list,
                      ),
                      RTFilterChipData(
                        id: _filterTelemetry,
                        label: 'Telemetria',
                        icon: Icons.location_on_outlined,
                      ),
                      RTFilterChipData(
                        id: _filterHealth,
                        label: 'Saúde',
                        icon: Icons.favorite_outline,
                      ),
                      RTFilterChipData(
                        id: _filterPolygon,
                        label: 'Polígono',
                        icon: Icons.crop_free,
                      ),
                      RTFilterChipData(
                        id: _filterOther,
                        label: 'Outros',
                        icon: Icons.more_horiz,
                      ),
                    ],
                    selectedIds: {_selectedFilter},
                    onToggle: (id) => setState(() => _selectedFilter = id),
                  ),
                ),
              ),
              const SizedBox(width: RTSpacing.x2),
              Text('AUTO', style: RTTypography.eyebrow.copyWith(
                color: _terminalInkSoft,
              )),
              Switch.adaptive(
                value: _autoRefresh,
                activeThumbColor: RTColors.ok,
                onChanged: (value) {
                  setState(() {
                    _autoRefresh = value;
                    if (!value) _manualFuture = _loadLog();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loading() {
    return Center(
      child: CircularProgressIndicator(color: RTColors.ok),
    );
  }

  Widget _emptyMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x4),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: RTTypography.mono.copyWith(
            color: _terminalInkSoft,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLogList(List<Map<String, dynamic>> items) {
    final filtered = items.where(_matchesFilter).toList();
    if (filtered.isEmpty) {
      return _emptyMessage(
        items.isEmpty
            ? 'Nenhuma mensagem da coleira foi encontrada no backend ainda.'
            : 'Nenhum evento corresponde ao filtro atual.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        RTSpacing.x3,
        RTSpacing.x3,
        RTSpacing.x3,
        RTSpacing.x6,
      ),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: RTSpacing.x2),
      itemBuilder: (context, index) => _buildLogEntry(filtered[index]),
    );
  }

  Widget _buildLogEntry(Map<String, dynamic> entry) {
    final timestamp = _formatTimestamp(entry['receivedAtMs'] as int?);
    final title = _titleForEntry(entry);
    final subtitle = _subtitleForEntry(entry);
    return Theme(
      data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: _terminalSurface,
          borderRadius: BorderRadius.circular(RTRadius.r2),
          border: Border.all(color: _terminalBorder),
        ),
        child: ExpansionTile(
          iconColor: _terminalInkSoft,
          collapsedIconColor: _terminalInkSoft,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: RTSpacing.x3,
            vertical: RTSpacing.x1,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            RTSpacing.x3,
            0,
            RTSpacing.x3,
            RTSpacing.x3,
          ),
          title: Row(
            children: [
              RTBadge(
                label: _typeTagForEntry(entry),
                tone: _toneForEntry(entry),
                mono: true,
              ),
              const SizedBox(width: RTSpacing.x2),
              Expanded(
                child: Text(
                  timestamp,
                  style: RTTypography.monoSmall.copyWith(
                    color: _terminalInk,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              title,
              style: RTTypography.bodyStrong.copyWith(color: _terminalInk),
            ),
          ),
          children: [
            if (subtitle.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle,
                  style: RTTypography.mono.copyWith(
                    color: _terminalInkSoft,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: RTSpacing.x2),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PAYLOAD',
                style: RTTypography.eyebrow.copyWith(color: _terminalInkSoft),
              ),
            ),
            const SizedBox(height: RTSpacing.x1),
            _payloadBlock(_prettyJson(entry['raw'])),
            if (_isPolygonAuditEntry(entry)) ...[
              const SizedBox(height: RTSpacing.x3),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isPolygonAuditSuccess(entry)
                      ? 'MAPA DO POLÍGONO'
                      : 'RESUMO DA FALHA',
                  style:
                      RTTypography.eyebrow.copyWith(color: _terminalInkSoft),
                ),
              ),
              const SizedBox(height: RTSpacing.x1),
              _buildPolygonResultSection(entry),
            ],
          ],
        ),
      ),
    );
  }

  Widget _payloadBlock(String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RTSpacing.x3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(RTRadius.r2),
        border: Border.all(color: _terminalBorder),
      ),
      child: SelectableText(
        content,
        style: RTTypography.monoSmall.copyWith(
          color: RTColors.ok,
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildPolygonResultSection(Map<String, dynamic> entry) {
    if (!_isPolygonAuditEntry(entry)) return const SizedBox.shrink();
    if (!_isPolygonAuditSuccess(entry)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RTSpacing.x3),
        decoration: BoxDecoration(
          color: RTColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(RTRadius.r2),
          border: Border.all(
            color: RTColors.danger.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          _friendlyPolygonFailure(entry),
          style: RTTypography.bodySmall.copyWith(color: _terminalInk),
        ),
      );
    }
    return FutureBuilder<PolygonLogPreviewResolution>(
      future: _previewForEntry(entry),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: RTSpacing.x3),
            child: Center(
              child: CircularProgressIndicator(color: RTColors.ok),
            ),
          );
        }
        final resolution = snapshot.data;
        if (snapshot.hasError) {
          return _inlineWarning(
            'Falha ao montar preview do mapa: ${snapshot.error}',
            RTColors.danger,
          );
        }
        if (resolution == null || !resolution.ok || resolution.data == null) {
          return _inlineWarning(
            resolution?.errorMessage ??
                'Não foi possível montar o mapa desse evento.',
            RTColors.warn,
          );
        }
        final svg = buildPolygonLogPreviewSvg(resolution.data!);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RTSpacing.x3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(RTRadius.r2),
            border: Border.all(color: _terminalBorder),
          ),
          child: AspectRatio(
            aspectRatio: 420 / 280,
            child: SvgPicture.string(svg, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Widget _inlineWarning(String message, Color tone) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RTSpacing.x3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(RTRadius.r2),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: RTTypography.bodySmall.copyWith(color: _terminalInk),
      ),
    );
  }
}
