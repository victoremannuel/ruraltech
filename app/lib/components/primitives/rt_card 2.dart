import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';

/// Superfície básica do RuralTech v2.
///
/// Borda sutil + sombra leve. Substitui `Card` padrão em listas e seções.
class RTCard extends StatelessWidget {
  const RTCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(RTSpacing.card),
    this.color,
    this.borderColor,
    this.borderRadius,
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(RTRadius.r3);
    final decoration = BoxDecoration(
      color: color ?? RTColors.bg,
      borderRadius: radius,
      border: Border.all(color: borderColor ?? RTColors.hairSoft),
      boxShadow: elevated ? RTElevation.sh2 : RTElevation.sh1,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
