import 'dart:async';

import 'package:flutter/material.dart';

enum AppFeedbackType { error, warning, success }

class _AppFeedbackMessage {
  const _AppFeedbackMessage({
    required this.id,
    required this.text,
    required this.type,
  });

  final int id;
  final String text;
  final AppFeedbackType type;
}

class _AppFeedbackController extends ChangeNotifier {
  _AppFeedbackMessage? _current;
  Timer? _dismissTimer;
  int _nextId = 0;

  _AppFeedbackMessage? get current => _current;

  void show(
    String message, {
    required AppFeedbackType type,
    Duration duration = const Duration(seconds: 5),
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    _dismissTimer?.cancel();
    _current = _AppFeedbackMessage(
      id: ++_nextId,
      text: normalized,
      type: type,
    );
    notifyListeners();
    _dismissTimer = Timer(duration, clear);
  }

  void clear() {
    if (_current == null) return;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _current = null;
    notifyListeners();
  }
}

final _AppFeedbackController _appFeedbackController = _AppFeedbackController();

class AppFeedback {
  static void error(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    _appFeedbackController.show(
      message,
      type: AppFeedbackType.error,
      duration: duration,
    );
  }

  static void warning(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    _appFeedbackController.show(
      message,
      type: AppFeedbackType.warning,
      duration: duration,
    );
  }

  static void success(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _appFeedbackController.show(
      message,
      type: AppFeedbackType.success,
      duration: duration,
    );
  }

  static void show(
    String message, {
    AppFeedbackType? type,
    Duration? duration,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final resolvedType = type ?? _inferType(normalized);
    switch (resolvedType) {
      case AppFeedbackType.error:
        error(normalized, duration: duration ?? const Duration(seconds: 5));
        break;
      case AppFeedbackType.warning:
        warning(normalized, duration: duration ?? const Duration(seconds: 5));
        break;
      case AppFeedbackType.success:
        success(normalized, duration: duration ?? const Duration(seconds: 4));
        break;
    }
  }

  static AppFeedbackType _inferType(String message) {
    final lower = message.toLowerCase();
    final successHints = <String>[
      'sucesso',
      'salv',
      'publicad',
      'importad',
      'atualiz',
      'concluid',
    ];
    for (final hint in successHints) {
      if (lower.contains(hint)) return AppFeedbackType.success;
    }

    final errorHints = <String>[
      'erro',
      'falha',
      'inval',
      'nao foi possivel',
      'obrigator',
      'indispon',
      'negad',
      'timeout',
      'tempo limite',
    ];
    for (final hint in errorHints) {
      if (lower.contains(hint)) return AppFeedbackType.error;
    }
    return AppFeedbackType.warning;
  }
}

class AppFeedbackHost extends StatefulWidget {
  const AppFeedbackHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppFeedbackHost> createState() => _AppFeedbackHostState();
}

class _AppFeedbackHostState extends State<AppFeedbackHost> {
  @override
  void initState() {
    super.initState();
    _appFeedbackController.addListener(_onFeedbackChanged);
  }

  @override
  void dispose() {
    _appFeedbackController.removeListener(_onFeedbackChanged);
    super.dispose();
  }

  void _onFeedbackChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final current = _appFeedbackController.current;
    final topInset = MediaQuery.of(context).viewPadding.top + 8;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (current != null)
          Positioned(
            top: topInset,
            left: 12,
            right: 12,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _TopFeedbackBanner(
                key: ValueKey<int>(current.id),
                message: current,
              ),
            ),
          ),
      ],
    );
  }
}

class _TopFeedbackBanner extends StatelessWidget {
  const _TopFeedbackBanner({
    super.key,
    required this.message,
  });

  final _AppFeedbackMessage message;

  Color _backgroundForType(AppFeedbackType type) {
    switch (type) {
      case AppFeedbackType.error:
        return const Color(0xFFC62828);
      case AppFeedbackType.warning:
        return const Color(0xFFF9A825);
      case AppFeedbackType.success:
        return const Color(0xFF2E7D32);
    }
  }

  IconData _iconForType(AppFeedbackType type) {
    switch (type) {
      case AppFeedbackType.error:
        return Icons.error_outline;
      case AppFeedbackType.warning:
        return Icons.warning_amber_outlined;
      case AppFeedbackType.success:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backgroundForType(message.type);
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(_iconForType(message.type), color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: _appFeedbackController.clear,
                color: Colors.white,
                splashRadius: 18,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
