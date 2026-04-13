import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/utils/pending_notifications.dart';

void main() {
  group('extractPendingNotifications', () {
    test('supports current function response shape', () {
      final rows = extractPendingNotifications({
        'notifications': [
          {'id': 'n1', 'title': 'A'},
          {'id': 'n2', 'title': 'B'},
        ],
        'count': 2,
      });

      expect(rows, hasLength(2));
      expect(rows.first['id'], 'n1');
      expect(rows.last['id'], 'n2');
    });

    test('supports legacy list payload shape', () {
      final rows = extractPendingNotifications([
        {'id': 'n1', 'title': 'A'},
      ]);

      expect(rows, hasLength(1));
      expect(rows.first['title'], 'A');
    });

    test('returns empty list for invalid payload', () {
      expect(extractPendingNotifications(null), isEmpty);
      expect(extractPendingNotifications({'count': 0}), isEmpty);
      expect(extractPendingNotifications('invalid'), isEmpty);
    });
  });
}
