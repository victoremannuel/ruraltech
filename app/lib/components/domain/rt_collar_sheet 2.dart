import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../primitives/rt_badge.dart';
import '../primitives/rt_button.dart';
import 'rt_telemetry_grid.dart';

class RTCollarSheetAction {
  const RTCollarSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.variant = RTButtonVariant.tonal,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final RTButtonVariant variant;
}

/// Bottom sheet arrastável com resumo + telemetria + ações da coleira.
///
/// Peek inicial curto, expansível até 70% da altura. Drag handle visível,
/// conteúdo em 3 camadas: identidade → telemetria → ações rápidas.
class RTCollarSheet extends StatelessWidget {
  const RTCollarSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.online,
    required this.lastSeenLabel,
    required this.entries,
    required this.actions,
    this.initialSize = 0.24,
    this.minSize = 0.16,
    this.maxSize = 0.78,
    this.statusLabel,
  });

  final String title;
  final String subtitle;
  final bool online;
  final String lastSeenLabel;
  final List<RTTelemetryEntry> entries;
  final List<RTCollarSheetAction> actions;
  final double initialSize;
  final double minSize;
  final double maxSize;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: RTColors.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(RTRadius.r5),
            ),
            boxShadow: RTElevation.sh3,
            border: Border(
              top: BorderSide(color: RTColors.hair),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _grabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RTSpacing.x4,
                  0,
                  RTSpacing.x4,
                  RTSpacing.x4,
                ),
                child: _header(),
              ),
              if (entries.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RTSpacing.x4,
                    0,
                    RTSpacing.x4,
                    RTSpacing.x3,
                  ),
                  child: RTTelemetryGrid(
                    title: 'Telemetria',
                    entries: entries,
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    RTSpacing.x4,
                    0,
                    RTSpacing.x4,
                    RTSpacing.x6,
                  ),
                  child: _actionsRow(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _grabber() {
    return Column(
      children: [
        const SizedBox(height: RTSpacing.x2),
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: RTColors.hair,
            borderRadius: BorderRadius.circular(RTRadius.rFull),
          ),
        ),
        const SizedBox(height: RTSpacing.x3),
      ],
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: RTColors.primarySoft,
            borderRadius: BorderRadius.circular(RTRadius.r2),
          ),
          child: Icon(Icons.pets_outlined, color: RTColors.primary),
        ),
        const SizedBox(width: RTSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: RTTypography.h3.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  RTBadge(
                    label: statusLabel ?? (online ? 'ONLINE' : 'OFFLINE'),
                    tone: online ? RTTone.ok : RTTone.neutral,
                    dot: true,
                    mono: true,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: RTTypography.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                lastSeenLabel,
                style: RTTypography.monoSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionsRow() {
    return Wrap(
      spacing: RTSpacing.x2,
      runSpacing: RTSpacing.x2,
      children: [
        for (final a in actions)
          RTButton(
            label: a.label,
            icon: a.icon,
            variant: a.variant,
            onPressed: a.onTap,
          ),
      ],
    );
  }
}

/// Helper para exibir como modal bottom sheet.
Future<void> showRTCollarSheet(
  BuildContext context, {
  required RTCollarSheet sheet,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
}
