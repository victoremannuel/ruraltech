List<Map<String, dynamic>> extractPendingNotifications(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  if (raw is Map) {
    final notifications = raw['notifications'];
    if (notifications is List) {
      return notifications
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
  }

  return const <Map<String, dynamic>>[];
}
