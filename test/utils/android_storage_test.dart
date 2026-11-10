import 'package:flutter_test/flutter_test.dart';
import 'package:folio/utils/android_storage.dart';

void main() {
  group('storageAccessSufficient', () {
    test('API 29 accepts READ_EXTERNAL_STORAGE', () {
      expect(
        storageAccessSufficient(
          sdk: 29,
          manageGranted: false,
          storageGranted: true,
        ),
        isTrue,
      );
    });

    test('API 30 ignores READ_EXTERNAL_STORAGE', () {
      expect(
        storageAccessSufficient(
          sdk: 30,
          manageGranted: false,
          storageGranted: true,
        ),
        isFalse,
      );
    });

    test('API 33 requires all-files access', () {
      expect(
        storageAccessSufficient(
          sdk: 33,
          manageGranted: true,
          storageGranted: false,
        ),
        isTrue,
      );
      expect(
        storageAccessSufficient(
          sdk: 33,
          manageGranted: false,
          storageGranted: false,
        ),
        isFalse,
      );
    });
  });
}
