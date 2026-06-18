import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Banner de confirmação para operações LoRa irreversíveis.
///
/// Exibe aviso amarelo com ícone de alerta e texto explicativo.
/// Use antes do CTA de publicação de cerca, arrebanhamento, etc.
class RTConfirmLoRa extends StatelessWidget {
  const RTConfirmLoRa({
    super.key,
    this.message =
        'Comandos LoRa são irreversíveis. Confirme antes de publicar.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RTSpacing.x3,
        vertical: RTSpacing.x3,
      ),
      decoration: BoxDecoration(
        color: RTColors.warnSoft,
        borderRadius: BorderRadius.circular(RTRadius.r3),
        border: Border.all(color: RTColors.warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: RTColors.warn,
            size: 18,
          ),
          const SizedBox(width: RTSpacing.x2),
          Expanded(
            child: Text(
              message,
              style: RTTypography.bodySmall.copyWith(color: RTColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
