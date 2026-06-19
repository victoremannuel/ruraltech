import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../primitives/rt_badge.dart';

class RTHealthComponent {
  const RTHealthComponent({required this.label, required this.ok});
  final String label;
  final bool ok;
}

/// Card hero verde com breakdown de subsistemas.
///
/// Usado em Device Details. Mostra status global + grid de componentes
/// (LoRa, MPU, MLX, Fila…) + badge "online / há X min".
class RTHealthHero extends StatelessWidget {
  const RTHealthHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.components,
    this.online = false,
    this.lastSeenLabel,
  });

  final String title;
  final String subtitle;
  final List<RTHealthComponent> components;
  final bool online;
  final String? lastSeenLabel;

  @override
  Widget build(BuildContext context) {
    final allOk = components.isNotEmpty && components.every((c) => c.ok);
    final statusColor = allOk ? RTColors.ok : RTColors.warn;

    return Container(
      padding: const EdgeInsets.all(RTSpacing.x5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RTColors.primary,
            RTColors.primaryDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(RTRadius.r4),
        boxShadow: RTElevation.sh2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: RTSpacing.x2),
              Text(
                'Saúde da coleira',
                style: RTTypography.eyebrow.copyWith(
                  color: RTColors.onPrimary.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: RTSpacing.x3),
          Text(
            title,
            style: RTTypography.h3.copyWith(
              color: RTColors.onPrimary,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: RTSpacing.x1),
          Text(
            subtitle,
            style: RTTypography.body.copyWith(
              color: RTColors.onPrimary.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: RTSpacing.x4),
          if (components.isNotEmpty) _componentGrid(components),
          if (components.isNotEmpty) const SizedBox(height: RTSpacing.x4),
          Row(
            children: [
              RTBadge(
                label: online ? 'ONLINE' : 'OFFLINE',
                tone: online ? RTTone.ok : RTTone.neutral,
                dot: true,
                mono: true,
              ),
              if (lastSeenLabel != null) ...[
                const SizedBox(width: RTSpacing.x2),
                Flexible(
                  child: Text(
                    lastSeenLabel!,
                    style: RTTypography.monoSmall.copyWith(
                      color: RTColors.onPrimary.withValues(alpha: 0.75),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _componentGrid(List<RTHealthComponent> comps) {
    final tiles = comps.map(_tile).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 360 ? 4 : 2;
        return Wrap(
          spacing: RTSpacing.x2,
          runSpacing: RTSpacing.x2,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: (constraints.maxWidth - (columns - 1) * RTSpacing.x2) /
                    columns,
                child: tile,
              ),
          ],
        );
      },
    );
  }

  Widget _tile(RTHealthComponent c) {
    final accent = c.ok ? RTColors.ok : RTColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x2,
        vertical: RTSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: RTColors.onPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RTRadius.r2),
        border: Border.all(
          color: RTColors.onPrimary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label.toUpperCase(),
            style: RTTypography.monoSmall.copyWith(
              color: RTColors.onPrimary.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                c.ok ? 'OK' : 'FALHA',
                style: RTTypography.mono.copyWith(
                  color: RTColors.onPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
