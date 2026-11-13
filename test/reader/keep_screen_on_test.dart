import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/keep_screen_on.dart';

void main() {
  setUp(KeepScreenOn.resetForTest);
  tearDown(KeepScreenOn.resetForTest);

  test('the topmost owner decides whether the screen stays on', () {
    final first = Object();
    final second = Object();

    KeepScreenOn.acquire(first, enabled: true);
    expect(KeepScreenOn.debugWanted, isTrue);

    KeepScreenOn.acquire(second, enabled: true);
    expect(KeepScreenOn.debugWanted, isTrue);

    KeepScreenOn.release(second);
    expect(
      KeepScreenOn.debugWanted,
      isTrue,
      reason: 'the reader below still wants the screen on',
    );

    KeepScreenOn.release(first);
    expect(KeepScreenOn.debugWanted, isFalse);
  });

  test(
    'a reader that turns the setting off does not disable the one below',
    () {
      final first = Object();
      final second = Object();

      KeepScreenOn.acquire(first, enabled: true);
      KeepScreenOn.acquire(second, enabled: false);
      expect(KeepScreenOn.debugWanted, isFalse);

      KeepScreenOn.release(second);
      expect(KeepScreenOn.debugWanted, isTrue);
    },
  );

  test('update for an unregistered owner is ignored', () {
    KeepScreenOn.update(Object(), true);
    expect(KeepScreenOn.debugWanted, isFalse);
  });
}
