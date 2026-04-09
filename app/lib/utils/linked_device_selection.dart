import 'package:flutter/foundation.dart';

String normalizeLinkedDeviceId(dynamic value) {
  if (value == null) return '';
  final raw = value.toString().trim();
  if (raw.isEmpty) return '';
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) return '';
  return parsed.toString();
}

List<String> normalizeLinkedDeviceIds(dynamic raw) {
  if (raw is! Iterable) return const <String>[];
  final ids = raw
      .map(normalizeLinkedDeviceId)
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return ids;
}

class LinkedDeviceSelectionController extends ChangeNotifier {
  LinkedDeviceSelectionController({
    Iterable<dynamic> initialDeviceIds = const <dynamic>[],
  }) : _selectedDeviceIds = normalizeLinkedDeviceIds(initialDeviceIds).toSet();

  final Set<String> _selectedDeviceIds;

  List<String> get selectedDeviceIds {
    final ids = _selectedDeviceIds.toList()..sort();
    return ids;
  }

  int get selectedCount => _selectedDeviceIds.length;

  bool isSelected(dynamic deviceId) {
    final normalized = normalizeLinkedDeviceId(deviceId);
    return normalized.isNotEmpty && _selectedDeviceIds.contains(normalized);
  }

  void toggle(dynamic deviceId) {
    final normalized = normalizeLinkedDeviceId(deviceId);
    if (normalized.isEmpty) return;
    if (_selectedDeviceIds.contains(normalized)) {
      _selectedDeviceIds.remove(normalized);
    } else {
      _selectedDeviceIds.add(normalized);
    }
    notifyListeners();
  }

  void replaceAll(Iterable<dynamic> deviceIds) {
    final nextIds = normalizeLinkedDeviceIds(deviceIds).toSet();
    if (setEquals(_selectedDeviceIds, nextIds)) return;
    _selectedDeviceIds
      ..clear()
      ..addAll(nextIds);
    notifyListeners();
  }

  void clear() => replaceAll(const <dynamic>[]);
}
