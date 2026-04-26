import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_action_row.dart';
import '../components/domain/rt_health_hero.dart';
import '../components/domain/rt_telemetry_grid.dart';
import '../components/primitives/rt_card.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/device_model.dart';
import '../services/cloud_service.dart';
import 'collar_log_screen.dart';
import 'geofence_screen.dart';
import 'herding_screen.dart';

class DeviceDetailsScreen extends StatelessWidget {
  final DeviceModel device;
  const DeviceDetailsScreen({super.key, required this.device});

  String _boolLabel(bool value) => value ? 'OK' : 'Falha';

  String _formatHealthTimestamp() {
    final dt = device.healthReceivedAt;
    if (dt == null) return 'Sem registro';
    return _formatDateTime(dt, showSeconds: false);
  }

  String _formatTelemetryTimestamp() {
    final dt = device.telemetryReceivedAt;
    if (dt == null) return 'Sem registro no gateway matriz';
    return _formatDateTime(dt, showSeconds: true);
  }

  String _formatDateTime(DateTime dt, {required bool showSeconds}) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (!showSeconds) return '$d/$m/$y $hh:$mm';
    final ss = dt.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  String _formatTelemetryTimestampFromMs(int ms) {
    if (ms <= 0) return 'Sem registro no gateway matriz';
    return _formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(ms),
      showSeconds: true,
    );
  }

  String _formatCoord(double? lat, double? lon) {
    if (lat == null || lon == null) return 'Sem posicao';
    return '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
  }

  String _relativeFromMs(int? ms) {
    if (ms == null || ms <= 0) return 'sem dados';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inSeconds < 60) return 'há poucos segundos';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    return 'há ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final networkId = device.networkId;
    final loraDeviceId = device.loraDeviceId;
    final hasValidLoraId = loraDeviceId != null;
    final hasPropertyBinding =
        device.propertyId != null && device.propertyId!.trim().isNotEmpty;
    final canOpenLog = hasValidLoraId && hasPropertyBinding;

    return Scaffold(
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(
        title: Text(device.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {},
            tooltip: 'Mais',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RTSpacing.x4,
          RTSpacing.x3,
          RTSpacing.x4,
          RTSpacing.x8,
        ),
        children: [
          _buildHero(networkId),
          const SizedBox(height: RTSpacing.x3),
          _buildPositionCard(context),
          const SizedBox(height: RTSpacing.x3),
          if (device.hasDailyHealth) ...[
            _buildGpsBusGrid(),
            const SizedBox(height: RTSpacing.x3),
          ],
          _buildActions(context, hasValidLoraId, canOpenLog, loraDeviceId),
        ],
      ),
    );
  }

  Widget _buildHero(String networkId) {
    final components = <RTHealthComponent>[
      RTHealthComponent(label: 'LoRa', ok: device.healthLoRaReady),
      RTHealthComponent(label: 'MPU', ok: device.healthMpuReady),
      RTHealthComponent(label: 'MLX', ok: device.healthMlxReady),
      RTHealthComponent(label: 'Fila', ok: device.healthStorageReady),
    ];
    final hasHealth = device.hasDailyHealth;
    final title = hasHealth
        ? (device.isHealthOk ? 'Todos sistemas OK' : 'Atenção necessária')
        : 'Sem relatório diário';
    final subtitle = hasHealth
        ? 'Última saúde reportada em ${_formatHealthTimestamp()}'
        : 'Aguardando primeiro report diário da coleira.';
    return RTHealthHero(
      title: title,
      subtitle: subtitle,
      components: hasHealth ? components : const [],
      online: device.telemetryReceivedAtMs != null,
      lastSeenLabel:
          'ID $networkId · ${_relativeFromMs(device.telemetryReceivedAtMs)}',
    );
  }

  Widget _buildPositionCard(BuildContext context) {
    final propertyId = device.propertyId?.trim();
    final deviceId = device.loraDeviceId;
    CloudService? cloud;
    try {
      cloud = context.read<CloudService>();
    } catch (_) {
      cloud = null;
    }
    final fallbackPosition = _formatCoord(device.lat, device.lon);
    final fallbackTimestamp = _formatTelemetryTimestamp();

    if (propertyId == null ||
        propertyId.isEmpty ||
        deviceId == null ||
        cloud == null) {
      return _positionGrid(fallbackPosition, fallbackTimestamp);
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: cloud.streamLatestTelemetryEntryForDevice(
        propertyId: propertyId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        final live = snapshot.data;
        final liveLat = live?['lat'] as double?;
        final liveLon = live?['lon'] as double?;
        final liveTimestampMs = live?['telemetryReceivedAtMs'] as int?;
        final position = liveLat != null && liveLon != null
            ? _formatCoord(liveLat, liveLon)
            : fallbackPosition;
        final timestamp = liveTimestampMs == null || liveTimestampMs <= 0
            ? fallbackTimestamp
            : _formatTelemetryTimestampFromMs(liveTimestampMs);
        return _positionGrid(position, timestamp);
      },
    );
  }

  Widget _positionGrid(String position, String timestamp) {
    return RTTelemetryGrid(
      title: 'Última posição',
      entries: [
        RTTelemetryEntry(label: 'Coordenadas', value: position, emphasis: true),
        RTTelemetryEntry(label: 'Registro na matriz', value: timestamp),
      ],
    );
  }

  Widget _buildGpsBusGrid() {
    final sats = device.healthSatellites?.toString() ?? '-';
    final hdop = device.healthHdop?.toStringAsFixed(2) ?? '-';
    final i2c = device.healthI2cDevices?.toString() ?? '-';
    final entries = <RTTelemetryEntry>[
      RTTelemetryEntry(label: 'UART GPS', value: _boolLabel(device.healthGpsUartReady)),
      RTTelemetryEntry(label: 'NMEA', value: _boolLabel(device.healthGpsNmeaSeen)),
      RTTelemetryEntry(
        label: 'Fix',
        value: device.healthGpsFixValid ? 'OK' : 'Sem fix',
      ),
      RTTelemetryEntry(label: 'Satélites', value: sats),
      RTTelemetryEntry(label: 'HDOP', value: hdop),
      RTTelemetryEntry(label: 'I2C', value: i2c),
    ];
    return RTTelemetryGrid(
      title: 'GPS e barramento',
      entries: entries,
    );
  }

  Widget _buildActions(
    BuildContext context,
    bool hasValidLoraId,
    bool canOpenLog,
    String? loraDeviceId,
  ) {
    return RTCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RTSpacing.x3,
              RTSpacing.x3,
              RTSpacing.x3,
              0,
            ),
            child: Row(
              children: [
                Text(
                  'AÇÕES OPERACIONAIS',
                  style: RTTypography.eyebrow,
                ),
              ],
            ),
          ),
          RTActionRow(
            title: 'Configurar Geofence',
            description: hasValidLoraId
                ? 'Desenhar perímetro no mapa'
                : 'ID LoRa inválido. Edite a coleira e informe um ID numérico.',
            icon: Icons.crop_free,
            enabled: hasValidLoraId,
            onTap: !hasValidLoraId
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GeofenceScreen(
                          deviceId: loraDeviceId!,
                          propertyId: device.propertyId,
                          gatewayId: device.gatewayId,
                          initialLat: device.lat,
                          initialLon: device.lon,
                        ),
                      ),
                    ),
          ),
          Divider(height: 1, color: RTColors.hairSoft),
          RTActionRow(
            title: 'Plano de Condução',
            description: hasValidLoraId
                ? 'Arrebanhar para área-alvo'
                : 'ID LoRa inválido. Edite a coleira e informe um ID numérico.',
            icon: Icons.route_outlined,
            enabled: hasValidLoraId,
            onTap: !hasValidLoraId
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HerdingScreen(
                          initialDeviceId: loraDeviceId!,
                          initialPropertyId: device.propertyId,
                          initialLat: device.lat,
                          initialLon: device.lon,
                        ),
                      ),
                    ),
          ),
          Divider(height: 1, color: RTColors.hairSoft),
          RTActionRow(
            title: 'Abrir log da coleira',
            description: canOpenLog
                ? 'Mensagens recebidas pela matriz'
                : 'A coleira precisa ter propriedade vinculada e ID LoRa válido.',
            icon: Icons.receipt_long_outlined,
            enabled: canOpenLog,
            onTap: !canOpenLog
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CollarLogScreen(device: device),
                      ),
                    ),
          ),
          const SizedBox(height: RTSpacing.x2),
        ],
      ),
    );
  }
}
