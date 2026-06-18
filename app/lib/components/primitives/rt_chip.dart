import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

enum RTChipVariant { filter, action, status }

/// Chip reutilizável do RuralTech v2.
///
/// - **filter**: toggle selecionado/não selecionado (ex.: chips de mapa)
/// - **action**: ação rápida sem estado de seleção
/// - **status**: exibe dot colorido + label (ex.: coleira online/offline)
class RTChip extends StatelessWidget {
  const RTChip({
    super.key,
    required this.label,
    this.variant = RTChipVariant.filter,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dotColor,
    this.count,
    this.enabled = true,
  });

  final String label;
  final RTChipVariant variant;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Cor do dot de status (apenas para [RTChipVariant.status]).
  final Color? dotColor;

  /// Badge numérico opcional no chip de filtro.
  final int? count;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isSelected = variant == RTChipVariant.filter && selected;
    final isDisabled = !enabled || onTap == null;

    final bg = isSelected ? RTColors.primary : RTColors.bg;
    final borderColor = isSelected ? RTColors.primary : RTColors.hair;
    final labelColor = isSelected
        ? RTColors.onPrimary
        : (isDisabled ? RTColors.inkMute : RTColors.ink);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: RTSpacing.x3,
          vertical: RTSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(RTRadius.rFull),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (variant == RTChipVariant.status && dotColor != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: RTSpacing.x2),
            ],
            if (icon != null && variant != RTChipVariant.status) ...[
              Icon(
                icon,
                size: 14,
                color: labelColor,
              ),
              const SizedBox(width: RTSpacing.x1 + 2),
            ],
            Text(
              label,
              style: RTTypography.label.copyWith(
                fontSize: 13,
                color: labelColor,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: RTSpacing.x2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? RTColors.onPrimary.withValues(alpha: 0.2)
                      : RTColors.bgSubtle,
                  borderRadius: BorderRadius.circular(RTRadius.rFull),
                ),
                child: Text(
                  count.toString(),
                  style: RTTypography.monoSmall.copyWith(
                    color: isSelected ? RTColors.onPrimary : RTColors.inkSoft,
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
}
