import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

enum RTTone { ok, warn, danger, info, primary, accent, neutral }

class _ToneColors {
  const _ToneColors(this.bg, this.fg, this.dot);
  final Color bg;
  final Color fg;
  final Color dot;
}

_ToneColors _colorsFor(RTTone tone) {
  switch (tone) {
    case RTTone.ok:
      return _ToneColors(RTColors.okSoft, RTColors.ok, RTColors.ok);
    case RTTone.warn:
      return _ToneColors(RTColors.warnSoft, RTColors.ink, RTColors.warn);
    case RTTone.danger:
      return _ToneColors(RTColors.dangerSoft, RTColors.danger, RTColors.danger);
    case RTTone.info:
      return _ToneColors(RTColors.infoSoft, RTColors.info, RTColors.info);
    case RTTone.primary:
      return _ToneColors(
          RTColors.primarySoft, RTColors.primaryDeep, RTColors.primary);
    case RTTone.accent:
      return _ToneColors(RTColors.accentSoft, RTColors.accent, RTColors.accent);
    case RTTone.neutral:
      return _ToneColors(RTColors.bgAlt, RTColors.inkSoft, RTColors.inkSoft);
  }
}

/// Badge compacto com cor tonal + opção de dot.
class RTBadge extends StatelessWidget {
  const RTBadge({
    super.key,
    required this.label,
    this.tone = RTTone.neutral,
    this.mono = false,
    this.dot = false,
    this.icon,
  });

  final String label;
  final RTTone tone;
  final bool mono;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(tone);
    final textStyle = (mono ? RTTypography.monoSmall : RTTypography.bodySmall)
        .copyWith(
      color: colors.fg,
      fontWeight: FontWeight.w700,
      letterSpacing: mono ? 0.0 : 0.04 * 11,
      fontSize: mono ? 11 : 11,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x3,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(RTRadius.rFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: RTSpacing.x1),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: colors.fg),
            const SizedBox(width: RTSpacing.x1),
          ],
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}
