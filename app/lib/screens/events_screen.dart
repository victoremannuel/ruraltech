import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_event_card.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';

enum _EventFilter { all, critical, info }

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  _EventFilter _filter = _EventFilter.all;

  RTEventSeverity _severityFor(Map<String, dynamic> event) {
    final type = (event['type'] ?? '').toString().toLowerCase();
    final eventType = (event['eventType'] ?? '').toString().toLowerCase();
    final combined = '$type|$eventType';
    if (combined.contains('fence_breach') ||
        combined.contains('fence_exit') ||
        combined.contains('alert') ||
        combined.contains('critical') ||
        combined.contains('error')) {
      return RTEventSeverity.danger;
    }
    if (combined.contains('warn') ||
        combined.contains('low_battery') ||
        combined.contains('offline') ||
        combined.contains('gps_lost')) {
      return RTEventSeverity.warn;
    }
    if (combined.contains('ack') ||
        combined.contains('fence_ok') ||
        combined.contains('reconnect') ||
        combined.contains('published')) {
      return RTEventSeverity.ok;
    }
    if (combined.contains('telemetry') ||
        combined.contains('info') ||
        combined.contains('heartbeat')) {
      return RTEventSeverity.info;
    }
    return RTEventSeverity.neutral;
  }

  bool _isCritical(RTEventSeverity s) =>
      s == RTEventSeverity.danger || s == RTEventSeverity.warn;

  String _titleFor(Map<String, dynamic> event) {
    final raw = (event['type'] ?? event['eventType'] ?? 'evento').toString();
    if (raw.isEmpty) return 'Evento';
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _subtitleFor(Map<String, dynamic> event) {
    final gatewayId = (event['gatewayId'] ?? '').toString();
    final polygonKind = (event['polygonKind'] ?? '').toString();
    final parts = <String>[
      if (gatewayId.isNotEmpty) 'GW $gatewayId',
      if (polygonKind.isNotEmpty) polygonKind,
    ];
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  String _timestampFor(Map<String, dynamic> event) {
    final ms = event['receivedAtMs'];
    if (ms is! int || ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.user?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eventos e Telemetria')),
        body: Center(
          child: Text(
            'Usuário não autenticado.',
            style: RTTypography.body,
          ),
        ),
      );
    }

    final fb = context.read<CloudService>();
    return Scaffold(
      backgroundColor: RTColors.bgAlt,
      appBar: AppBar(title: const Text('Eventos e Telemetria')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: fb.streamCriticalEvents(uid: uid, isAdmin: auth.isAdmin),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(snapshot.error);
          }
          final events = snapshot.data ?? const <Map<String, dynamic>>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              events.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final withSeverity = events
              .map((e) => (event: e, severity: _severityFor(e)))
              .toList();

          final criticalCount =
              withSeverity.where((e) => _isCritical(e.severity)).length;
          final infoCount = withSeverity.length - criticalCount;

          final filtered = withSeverity.where((e) {
            switch (_filter) {
              case _EventFilter.all:
                return true;
              case _EventFilter.critical:
                return _isCritical(e.severity);
              case _EventFilter.info:
                return !_isCritical(e.severity);
            }
          }).toList();

          return Column(
            children: [
              _buildHeader(criticalCount, infoCount),
              _buildFilters(criticalCount, infoCount),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          RTSpacing.x4,
                          RTSpacing.x2,
                          RTSpacing.x4,
                          RTSpacing.x8,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: RTSpacing.x2),
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final deviceId = (e.event['deviceId'] ?? '').toString();
                          return RTEventCard(
                            title: _titleFor(e.event),
                            severity: e.severity,
                            subtitle: _subtitleFor(e.event).isEmpty
                                ? null
                                : _subtitleFor(e.event),
                            deviceId: deviceId.isEmpty ? null : deviceId,
                            timestamp: _timestampFor(e.event),
                            live: i == 0 &&
                                e.severity == RTEventSeverity.danger,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int criticalCount, int infoCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RTSpacing.x4,
        RTSpacing.x3,
        RTSpacing.x4,
        RTSpacing.x2,
      ),
      child: Row(
        children: [
          _counter(
            value: criticalCount.toString(),
            label: 'Críticos',
            color: RTColors.danger,
          ),
          const SizedBox(width: RTSpacing.x4),
          _counter(
            value: infoCount.toString(),
            label: 'Informativos',
            color: RTColors.info,
          ),
        ],
      ),
    );
  }

  Widget _counter({required String value, required String label, required Color color}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: RTSpacing.x2),
        Text(
          value,
          style: RTTypography.monoLarge.copyWith(color: RTColors.ink),
        ),
        const SizedBox(width: RTSpacing.x1),
        Text(label, style: RTTypography.bodySmall),
      ],
    );
  }

  Widget _buildFilters(int criticalCount, int infoCount) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x4),
        children: [
          _filterChip('Todos', null, _EventFilter.all),
          const SizedBox(width: RTSpacing.x2),
          _filterChip('Críticos', criticalCount, _EventFilter.critical),
          const SizedBox(width: RTSpacing.x2),
          _filterChip('Informativos', infoCount, _EventFilter.info),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int? count, _EventFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: RTSpacing.x3,
          vertical: RTSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: selected ? RTColors.primary : RTColors.bg,
          borderRadius: BorderRadius.circular(RTRadius.rFull),
          border: Border.all(
            color: selected ? RTColors.primary : RTColors.hair,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: RTTypography.label.copyWith(
                fontSize: 13,
                color: selected ? RTColors.onPrimary : RTColors.ink,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: RTSpacing.x2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? RTColors.onPrimary.withValues(alpha: 0.2)
                      : RTColors.bgSubtle,
                  borderRadius: BorderRadius.circular(RTRadius.rFull),
                ),
                child: Text(
                  count.toString(),
                  style: RTTypography.monoSmall.copyWith(
                    color: selected ? RTColors.onPrimary : RTColors.inkSoft,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: RTColors.primarySoft,
                borderRadius: BorderRadius.circular(RTRadius.r3),
              ),
              child: Icon(
                Icons.notifications_none_outlined,
                color: RTColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: RTSpacing.x4),
            Text(
              'Nenhum evento por aqui',
              style: RTTypography.h3.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RTSpacing.x2),
            Text(
              'Conecte ao gateway para receber eventos críticos e telemetria em tempo real.',
              style: RTTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RTSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: RTColors.danger, size: 32),
            const SizedBox(height: RTSpacing.x3),
            Text(
              'Falha ao carregar eventos',
              style: RTTypography.h3.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RTSpacing.x2),
            Text(
              '$error',
              style: RTTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
