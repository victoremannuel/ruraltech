import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';

class RTFabAction {
  const RTFabAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
    this.actionKey,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;
  final Key? actionKey;
}

/// FAB extendido com speed-dial.
///
/// Estado padrão: botão accent com label "Novo". Ao tocar, expande em coluna
/// de ações secundárias com fundo translúcido escuro.
class RTFab extends StatefulWidget {
  const RTFab({
    super.key,
    required this.label,
    required this.icon,
    required this.actions,
    this.fabKey,
  });

  final String label;
  final IconData icon;
  final List<RTFabAction> actions;
  final Key? fabKey;

  @override
  State<RTFab> createState() => _RTFabState();
}

class _RTFabState extends State<RTFab> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_ctrl.isDismissed) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _handleAction(RTFabAction a) {
    _ctrl.reverse();
    a.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final open = _anim.value > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (open) ..._buildActions(),
            if (open) const SizedBox(height: RTSpacing.x2),
            _mainFab(),
          ],
        );
      },
    );
  }

  List<Widget> _buildActions() {
    final actions = widget.actions;
    return [
      for (var i = 0; i < actions.length; i++)
        Opacity(
          opacity: _anim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _anim.value) * 12),
            child: Padding(
              padding: EdgeInsets.only(bottom: i == 0 ? 0 : RTSpacing.x2),
              child: _ActionPill(
                action: actions[i],
                onTap: () => _handleAction(actions[i]),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _mainFab() {
    final isOpen = _ctrl.isCompleted || _ctrl.isAnimating && _ctrl.value > 0.5;
    return Material(
      key: widget.fabKey,
      color: RTColors.accent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RTRadius.rFull),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggle,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: RTSpacing.x5),
          decoration: BoxDecoration(
            boxShadow: RTElevation.sh3,
            borderRadius: BorderRadius.circular(RTRadius.rFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedRotation(
                turns: isOpen ? 0.125 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(widget.icon, color: RTColors.onAccent, size: 22),
              ),
              const SizedBox(width: RTSpacing.x2),
              Text(
                widget.label,
                style: RTTypography.label.copyWith(
                  color: RTColors.onAccent,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action, required this.onTap});

  final RTFabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: action.actionKey,
      color: RTColors.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RTRadius.rFull),
        side: BorderSide(color: RTColors.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RTSpacing.x4,
            vertical: RTSpacing.x2,
          ),
          decoration: BoxDecoration(
            boxShadow: RTElevation.sh2,
            borderRadius: BorderRadius.circular(RTRadius.rFull),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                color: action.tone ?? RTColors.primary,
                size: 18,
              ),
              const SizedBox(width: RTSpacing.x2),
              Text(
                action.label,
                style: RTTypography.label.copyWith(
                  color: RTColors.ink,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
