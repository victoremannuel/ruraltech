import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';

class RTMapControlAction {
  const RTMapControlAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badgeColor,
    this.heroTag,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? badgeColor;
  final String? heroTag;
}

/// Stack vertical de controles de mapa (camadas, bússola, GPS).
///
/// Substitui as antigas `FloatingActionButton.small` empilhadas. Cada botão
/// respeita touch target ≥ 44px e usa a paleta neutra do design system para
/// não competir com o canvas do mapa.
class RTMapControls extends StatelessWidget {
  const RTMapControls({
    super.key,
    required this.actions,
    this.alignment = Alignment.bottomLeft,
    this.padding = const EdgeInsets.all(RTSpacing.x3),
  });

  final List<RTMapControlAction> actions;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: Container(
          decoration: BoxDecoration(
            color: RTColors.bg,
            borderRadius: BorderRadius.circular(RTRadius.r3),
            border: Border.all(color: RTColors.hair),
            boxShadow: RTElevation.sh2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: RTColors.hairSoft,
                    thickness: 1,
                  ),
                _MapControlButton(action: actions[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.action});

  final RTMapControlAction action;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.tooltip ?? '',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(RTRadius.r3),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(action.icon, size: 22, color: RTColors.inkSoft),
              if (action.badgeColor != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: action.badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: RTColors.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
