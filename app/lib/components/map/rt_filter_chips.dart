import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

class RTFilterChipData {
  const RTFilterChipData({
    required this.id,
    required this.label,
    this.count,
    this.icon,
  });

  final String id;
  final String label;
  final int? count;
  final IconData? icon;
}

/// Linha horizontal de chips de filtro para sobreposição no mapa.
///
/// Fundo translúcido + shadow leve para não competir com o canvas. Usado pelo
/// Dashboard (Mapa) e outras telas com filtro rápido.
class RTFilterChips extends StatelessWidget {
  const RTFilterChips({
    super.key,
    required this.chips,
    required this.selectedIds,
    required this.onToggle,
    this.padding = const EdgeInsets.symmetric(horizontal: RTSpacing.x4),
  });

  final List<RTFilterChipData> chips;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: RTSpacing.x2),
        itemBuilder: (_, i) {
          final chip = chips[i];
          final selected = selectedIds.contains(chip.id);
          return _chipButton(chip, selected);
        },
      ),
    );
  }

  Widget _chipButton(RTFilterChipData chip, bool selected) {
    return GestureDetector(
      onTap: () => onToggle(chip.id),
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
          boxShadow: RTElevation.sh1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chip.icon != null) ...[
              Icon(
                chip.icon,
                size: 15,
                color: selected ? RTColors.onPrimary : RTColors.inkSoft,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              chip.label,
              style: RTTypography.label.copyWith(
                fontSize: 13,
                color: selected ? RTColors.onPrimary : RTColors.ink,
              ),
            ),
            if (chip.count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? RTColors.onPrimary.withValues(alpha: 0.2)
                      : RTColors.bgSubtle,
                  borderRadius: BorderRadius.circular(RTRadius.rFull),
                ),
                child: Text(
                  chip.count.toString(),
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
}
