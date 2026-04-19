import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

/// Stepper visual de múltiplas etapas — RuralTech v2.
///
/// Exibe [steps] barras horizontais com rótulo abaixo.
/// A etapa [currentStep] (0-indexada) fica marcada como ativa;
/// etapas anteriores ficam concluídas; posteriores, pendentes.
class RTStepper extends StatelessWidget {
  const RTStepper({
    super.key,
    required this.steps,
    required this.currentStep,
  }) : assert(steps.length > 0),
       assert(currentStep >= 0 && currentStep < steps.length);

  final List<String> steps;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(child: _StepItem(
            label: steps[i],
            state: i < currentStep
                ? _StepState.done
                : i == currentStep
                    ? _StepState.active
                    : _StepState.pending,
          )),
          if (i < steps.length - 1) const SizedBox(width: RTSpacing.x2),
        ],
      ],
    );
  }
}

enum _StepState { done, active, pending }

class _StepItem extends StatelessWidget {
  const _StepItem({required this.label, required this.state});
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final Color barColor;
    final Color labelColor;

    switch (state) {
      case _StepState.done:
        barColor = RTColors.primary;
        labelColor = RTColors.inkSoft;
      case _StepState.active:
        barColor = RTColors.primary;
        labelColor = RTColors.ink;
      case _StepState.pending:
        barColor = RTColors.hair;
        labelColor = RTColors.inkMute;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 3,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(RTRadius.rFull),
          ),
        ),
        const SizedBox(height: RTSpacing.x1 + 2),
        Text(
          label,
          style: RTTypography.eyebrow.copyWith(
            color: labelColor,
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
