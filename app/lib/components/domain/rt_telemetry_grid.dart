import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../primitives/rt_card.dart';

class RTTelemetryEntry {
  const RTTelemetryEntry({
    required this.label,
    required this.value,
    this.mono = true,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasis;
}

/// Grid 2-col de telemetria técnica.
///
/// Label em eyebrow uppercase + valor em mono. Usado em Device Details para
/// coordenadas, HDOP, RSSI, bateria, etc.
class RTTelemetryGrid extends StatelessWidget {
  const RTTelemetryGrid({
    super.key,
    required this.title,
    required this.entries,
    this.trailing,
  });

  final String title;
  final List<RTTelemetryEntry> entries;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RTCard(
      padding: const EdgeInsets.all(RTSpacing.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: RTTypography.eyebrow,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: RTSpacing.x3),
          ..._buildRows(entries),
        ],
      ),
    );
  }

  List<Widget> _buildRows(List<RTTelemetryEntry> entries) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      final left = entries[i];
      final right = i + 1 < entries.length ? entries[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : RTSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _entryCell(left)),
            const SizedBox(width: RTSpacing.x3),
            Expanded(
              child: right != null ? _entryCell(right) : const SizedBox(),
            ),
          ],
        ),
      ));
    }
    return rows;
  }

  Widget _entryCell(RTTelemetryEntry entry) {
    final style = entry.mono
        ? RTTypography.mono.copyWith(
            fontSize: entry.emphasis ? 15 : 14,
            color: entry.emphasis ? RTColors.primaryDeep : RTColors.ink,
          )
        : RTTypography.bodyStrong;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.label.toUpperCase(),
          style: RTTypography.monoSmall.copyWith(
            color: RTColors.inkMute,
            fontSize: 10,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(entry.value, style: style),
      ],
    );
  }
}
