import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

enum RTButtonVariant { primary, accent, tonal, ghost, danger }

enum RTButtonSize { md, lg }

/// Botão padrão do RuralTech v2.
///
/// Suporta variantes do handoff (primary, accent, tonal, ghost, danger) e um
/// estado `loading` que preserva a largura e mostra spinner.
class RTButton extends StatelessWidget {
  const RTButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = RTButtonVariant.primary,
    this.size = RTButtonSize.md,
    this.icon,
    this.trailing,
    this.loading = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final RTButtonVariant variant;
  final RTButtonSize size;
  final IconData? icon;
  final IconData? trailing;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final style = _styleFor(variant, disabled);
    final height = size == RTButtonSize.lg ? 56.0 : 48.0;
    final horizontalPad = size == RTButtonSize.lg ? 24.0 : 20.0;

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(style.fg),
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 18, color: style.fg),
            const SizedBox(width: RTSpacing.x2),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: RTTypography.label.copyWith(
                color: style.fg,
                fontSize: size == RTButtonSize.lg ? 15 : 14,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: RTSpacing.x2),
            Icon(trailing, size: 18, color: style.fg),
          ],
        ],
      ],
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RTRadius.r3),
      side: style.border,
    );

    final button = Material(
      color: style.bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onPressed,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

class _Style {
  const _Style({required this.bg, required this.fg, required this.border});
  final Color bg;
  final Color fg;
  final BorderSide border;
}

_Style _styleFor(RTButtonVariant variant, bool disabled) {
  BorderSide none = BorderSide.none;
  switch (variant) {
    case RTButtonVariant.primary:
      return _Style(
        bg: disabled ? RTColors.primary.withValues(alpha: 0.4) : RTColors.primary,
        fg: RTColors.onPrimary,
        border: none,
      );
    case RTButtonVariant.accent:
      return _Style(
        bg: disabled ? RTColors.accent.withValues(alpha: 0.4) : RTColors.accent,
        fg: RTColors.onAccent,
        border: none,
      );
    case RTButtonVariant.tonal:
      return _Style(
        bg: disabled ? RTColors.primarySoft.withValues(alpha: 0.5) : RTColors.primarySoft,
        fg: RTColors.primaryDeep,
        border: none,
      );
    case RTButtonVariant.ghost:
      return _Style(
        bg: Colors.transparent,
        fg: disabled ? RTColors.inkMute : RTColors.primary,
        border: BorderSide(
            color: disabled ? RTColors.hairSoft : RTColors.hair),
      );
    case RTButtonVariant.danger:
      return _Style(
        bg: disabled ? RTColors.danger.withValues(alpha: 0.4) : RTColors.danger,
        fg: RTColors.onPrimary,
        border: none,
      );
  }
}
