import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/domain/rt_event_card.dart';
import '../design/colors.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';

enum _EventFilter { all, critical, warn, ok }

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

          final criticalCount = withSeverity
              .where((e) => e.severity == RTEventSeverity.danger)
              .length;
          final warnCount = withSeverity
              .where((e) => e.severity == RTEventSeverity.warn)
              .length;
          final okCount = withSeverity
              .where((e) =>
                  e.severity == RTEventSeverity.ok ||
                  e.severity == RTEventSeverity.info ||
                  e.severity == RTEventSeverity.neutral)
              .length;

          final filtered = withSeverity.where((e) {
            switch (_filter) {
              case _EventFilter.all:
                return true;
              case _EventFilter.critical:
                return e.severity == RTEventSeverity.danger;
              case _EventFilter.warn:
                return e.severity == RTEventSeverity.warn;
              case _EventFilter.ok:
                return e.severity == RTEventSeverity.ok ||
                    e.severity == RTEventSeverity.info ||
                    e.severity == RTEventSeverity.neutral;
            }
          }).toList();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: RTColors.bg,
                surfaceTintColor: Colors.transparent,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Eventos',
                        style: RTTypography.h2.copyWith(fontSize: 24)),
                    Text('Últimas 24 horas',
                        style: RTTypography.bodySmall
                            .copyWith(color: RTColors.inkSoft)),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Expanded(
                      child: _CounterCard(
                        value: criticalCount,
                        label: 'Críticos',
                        tone: RTColors.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CounterCard(
                        value: warnCount + okCount,
                        label: 'Informativos',
                        tone: RTColors.info,
                      ),
                    ),
                  ]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              SliverToBoxAdapter(
                child: _buildFilters(
                    criticalCount, warnCount, okCount, withSeverity.length),
              ),
              filtered.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          final deviceId =
                              (e.event['deviceId'] ?? '').toString();
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

  Widget _buildFilters(
      int criticalCount, int warnCount, int okCount, int total) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x4),
        children: [
          _filterChip('Tudo · $total', null, _EventFilter.all),
          const SizedBox(width: RTSpacing.x2),
          _filterChip('Crítico · $criticalCount', RTColors.danger,
              _EventFilter.critical),
          const SizedBox(width: RTSpacing.x2),
          _filterChip(
              'Atenção · $warnCount', RTColors.warn, _EventFilter.warn),
          const SizedBox(width: RTSpacing.x2),
          _filterChip('OK · $okCount', RTColors.ok, _EventFilter.ok),
        ],
      ),
    );
  }

  Widget _filterChip(String label, Color? dot, _EventFilter value) {
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: selected ? RTColors.onPrimary : dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: RTTypography.label.copyWith(
                fontSize: 13,
                color: selected ? RTColors.onPrimary : RTColors.ink,
              ),
            ),
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

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.value,
    required this.label,
    required this.tone,
  });

  final int value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RTColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RTColors.hairSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: RTTypography.h1.copyWith(fontSize: 36, color: tone),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: RTTypography.eyebrow,
          ),
        ],
      ),
    );
  }
}
