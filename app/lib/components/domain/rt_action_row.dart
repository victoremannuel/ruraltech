import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Linha de ação clicável com ícone tonal + título + descrição opcional.
///
/// Substitui ListTile em Device Details e similares. Uniformiza estados
/// `enabled`/`disabled` com feedback visual próprio.
class RTActionRow extends StatelessWidget {
  const RTActionRow({
    super.key,
    required this.title,
    required this.icon,
    this.description,
    this.trailingValue,
    this.onTap,
    this.enabled = true,
    this.tone,
  });

  final String title;
  final IconData icon;
  final String? description;
  final String? trailingValue;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final effectiveTone = tone ?? RTColors.primary;
    final disabled = !enabled || onTap == null;
    final iconBg = disabled
        ? RTColors.bgSubtle
        : effectiveTone.withValues(alpha: 0.12);
    final iconFg = disabled ? RTColors.inkMute : effectiveTone;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RTRadius.r3),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RTSpacing.x3,
            vertical: RTSpacing.x3,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(RTRadius.r2),
                ),
                child: Icon(icon, size: 22, color: iconFg),
              ),
              const SizedBox(width: RTSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: RTTypography.label.copyWith(
                        color: disabled ? RTColors.inkMute : RTColors.ink,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: RTTypography.bodySmall.copyWith(
                          color: disabled ? RTColors.inkMute : RTColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailingValue != null) ...[
                const SizedBox(width: RTSpacing.x3),
                Text(
                  trailingValue!,
                  style: RTTypography.mono.copyWith(
                    color: disabled ? RTColors.inkMute : RTColors.inkSoft,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(width: RTSpacing.x2),
              Icon(
                Icons.chevron_right,
                color: disabled ? RTColors.inkMute : RTColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
