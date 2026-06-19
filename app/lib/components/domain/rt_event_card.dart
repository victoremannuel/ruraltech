import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../primitives/rt_badge.dart';
import '../primitives/rt_card.dart';

enum RTEventSeverity { danger, warn, ok, info, neutral }

/// Card de evento/telemetria com ícone tonal + severidade + timestamp.
///
/// Usado no feed de Eventos. A cor é estritamente tonal (apenas o ícone/badge
/// colorem), o fundo permanece neutro para não poluir o feed.
class RTEventCard extends StatelessWidget {
  const RTEventCard({
    super.key,
    required this.title,
    required this.severity,
    this.subtitle,
    this.timestamp,
    this.deviceId,
    this.live = false,
    this.onTap,
    this.icon,
  });

  final String title;
  final RTEventSeverity severity;
  final String? subtitle;
  final String? timestamp;
  final String? deviceId;
  final bool live;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(severity);
    final effectiveIcon = icon ?? _iconFor(severity);

    return RTCard(
      padding: const EdgeInsets.all(RTSpacing.x3),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.soft,
              borderRadius: BorderRadius.circular(RTRadius.r2),
            ),
            child: Icon(effectiveIcon, color: palette.base, size: 22),
          ),
          const SizedBox(width: RTSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: RTTypography.label.copyWith(
                          color: RTColors.ink,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: RTSpacing.x2),
                      RTBadge(
                        label: 'VIVO',
                        tone: RTTone.danger,
                        dot: true,
                        mono: true,
                      ),
                    ],
                  ],
                ),
                if (subtitle != null || deviceId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (deviceId != null) 'C-$deviceId',
                      if (subtitle != null) subtitle!,
                    ].join(' · '),
                    style: RTTypography.bodySmall,
                  ),
                ],
                if (timestamp != null) ...[
                  const SizedBox(height: RTSpacing.x2),
                  Text(
                    timestamp!,
                    style: RTTypography.monoSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(RTEventSeverity s) {
    switch (s) {
      case RTEventSeverity.danger:
        return Icons.error_outline;
      case RTEventSeverity.warn:
        return Icons.warning_amber_outlined;
      case RTEventSeverity.ok:
        return Icons.check_circle_outline;
      case RTEventSeverity.info:
        return Icons.info_outline;
      case RTEventSeverity.neutral:
        return Icons.circle_outlined;
    }
  }
}

class _Palette {
  const _Palette(this.base, this.soft);
  final Color base;
  final Color soft;
}

_Palette _paletteFor(RTEventSeverity severity) {
  switch (severity) {
    case RTEventSeverity.danger:
      return _Palette(RTColors.danger, RTColors.dangerSoft);
    case RTEventSeverity.warn:
      return _Palette(RTColors.warn, RTColors.warnSoft);
    case RTEventSeverity.ok:
      return _Palette(RTColors.ok, RTColors.okSoft);
    case RTEventSeverity.info:
      return _Palette(RTColors.info, RTColors.infoSoft);
    case RTEventSeverity.neutral:
      return _Palette(RTColors.inkSoft, RTColors.bgAlt);
  }
}
