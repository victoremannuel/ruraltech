import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/firebase_service.dart';

class CollarLogScreen extends StatefulWidget {
  final DeviceModel device;

  const CollarLogScreen({super.key, required this.device});

  @override
  State<CollarLogScreen> createState() => _CollarLogScreenState();
}

class _CollarLogScreenState extends State<CollarLogScreen> {
  bool _autoRefresh = false;
  late Future<List<Map<String, dynamic>>> _manualFuture;

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
    return context.read<FirebaseService>().getCollarFirebaseLog(
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
    if (ms == null || ms <= 0) return 'Sem horario';
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
    if (type == 'telemetry') return 'Telemetria';
    if (type == 'health_daily') return 'Saude diaria';
    if (kind.isNotEmpty) return kind;
    return 'Evento';
  }

  String _subtitleForEntry(Map<String, dynamic> entry) {
    final parts = <String>[
      _formatTimestamp(entry['receivedAtMs'] as int?),
    ];

    final type = (entry['type'] ?? '').toString();
    if (type == 'telemetry') {
      final lat = entry['lat'] as double?;
      final lon = entry['lon'] as double?;
      if (lat != null && lon != null) {
        parts.add(
          '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
        );
      }
    } else if (type == 'health_daily') {
      final sat = entry['sat'];
      final temperatureDeciC = entry['temperatureDeciC'];
      if (temperatureDeciC is int) {
        parts.add('Temp ${(temperatureDeciC / 10.0).toStringAsFixed(1)} C');
      }
      if (sat != null) parts.add('Sat $sat');
    } else {
      final kind = (entry['kind'] ?? '').toString().trim();
      if (kind.isNotEmpty) parts.add(kind);
    }

    final gatewayId = (entry['gatewayId'] ?? '').toString().trim();
    if (gatewayId.isNotEmpty) parts.add('GW $gatewayId');

    final gatewayRole = (entry['gatewayRole'] ?? '').toString().trim();
    if (gatewayRole.isNotEmpty) parts.add(gatewayRole);

    return parts.join(' | ');
  }

  IconData _iconForEntry(Map<String, dynamic> entry) {
    final type = (entry['type'] ?? '').toString();
    if (type == 'telemetry') return Icons.location_on;
    if (type == 'health_daily') return Icons.health_and_safety;
    return Icons.notifications_active_outlined;
  }

  Color _colorForEntry(Map<String, dynamic> entry, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = (entry['type'] ?? '').toString();
    if (type == 'telemetry') return Colors.blue;
    if (type == 'health_daily') return scheme.primary;
    return scheme.secondary;
  }

  String _prettyJson(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  Widget _buildLogList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Nenhuma mensagem da coleira foi encontrada no Firebase ainda.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = items[index];
        return Card(
          child: ExpansionTile(
            leading: Icon(
              _iconForEntry(entry),
              color: _colorForEntry(entry, context),
            ),
            title: Text(_titleForEntry(entry)),
            subtitle: Text(_subtitleForEntry(entry)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Payload recebido no Firebase',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FAF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB8CFBD)),
                ),
                child: SelectableText(
                  _prettyJson(entry['raw']),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final propertyId = _propertyId;
    final deviceId = _deviceId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Log ${widget.device.networkId}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mensagens recebidas no Firebase para a coleira ${widget.device.networkId}.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _autoRefresh ? null : _refreshManually,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Atualizar log'),
                    ),
                    const Spacer(),
                    const Text('Atualizar automatico'),
                    Switch.adaptive(
                      value: _autoRefresh,
                      onChanged: (value) {
                        setState(() {
                          _autoRefresh = value;
                          if (!value) {
                            _manualFuture = _loadLog();
                          }
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: (propertyId == null || deviceId == null)
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'A coleira precisa ter propriedade vinculada e ID LoRa valido para exibir o log.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _autoRefresh
                    ? StreamBuilder<List<Map<String, dynamic>>>(
                        stream: context
                            .read<FirebaseService>()
                            .streamCollarFirebaseLog(
                              propertyId: propertyId,
                              deviceId: deviceId,
                            ),
                        builder: (context, snapshot) {
                          final items =
                              snapshot.data ?? const <Map<String, dynamic>>[];
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Falha ao carregar log em tempo real:\n${snapshot.error}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              items.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _buildLogList(items);
                        },
                      )
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future: _manualFuture,
                        builder: (context, snapshot) {
                          final items =
                              snapshot.data ?? const <Map<String, dynamic>>[];
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Falha ao carregar log:\n${snapshot.error}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              items.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return _buildLogList(items);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
