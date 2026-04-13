import 'package:flutter_test/flutter_test.dart';
import 'package:ruraltech_app/utils/home_session_state.dart';

void main() {
  group('Home session state', () {
    test('blocks only the initial authenticated profile bootstrap', () {
      expect(
        shouldShowBlockingHomeLoader(
          uid: null,
          isProfileLoading: false,
          lastReadyAuthKey: null,
        ),
        isTrue,
      );

      expect(
        shouldShowBlockingHomeLoader(
          uid: 'adm-1',
          isProfileLoading: true,
          lastReadyAuthKey: null,
        ),
        isTrue,
      );

      expect(
        shouldShowBlockingHomeLoader(
          uid: 'adm-1',
          isProfileLoading: true,
          lastReadyAuthKey: 'adm-1-adm',
        ),
        isFalse,
      );
    });

    test('builds auth key with normalized role and uid', () {
      expect(
        resolveHomeAuthKey(uid: ' adm-1 ', role: ' ADM '),
        'adm-1-adm',
      );
      expect(resolveHomeAuthKey(uid: '   ', role: 'user'), isNull);
    });

    test('collects non-blocking dashboard issues', () {
      final issues = collectHomeLoadIssues(
        propertiesError: Exception('props'),
        devicesError: Exception('devices'),
        adminBootstrapError: 'Falha no bootstrap admin.',
      );

      expect(
        issues,
        <String>[
          'Falha ao carregar propriedades.',
          'Falha ao carregar coleiras.',
          'Falha no bootstrap admin.',
        ],
      );
    });
  });
}
