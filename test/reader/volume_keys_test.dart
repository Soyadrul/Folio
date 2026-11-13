import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/volume_keys.dart';

void main() {
  group('volumeKeyTurnsForward', () {
    test('default mapping turns forward on volume down', () {
      expect(volumeKeyTurnsForward(key: VolumeKey.down, invert: false), isTrue);
      expect(volumeKeyTurnsForward(key: VolumeKey.up, invert: false), isFalse);
    });

    test('invert swaps the mapping', () {
      expect(volumeKeyTurnsForward(key: VolumeKey.up, invert: true), isTrue);
      expect(volumeKeyTurnsForward(key: VolumeKey.down, invert: true), isFalse);
    });
  });

  group('scrollSpeedAfterVolumeKey', () {
    test('volume up adds 5 and volume down subtracts 5', () {
      expect(scrollSpeedAfterVolumeKey(40, VolumeKey.up), 45);
      expect(scrollSpeedAfterVolumeKey(40, VolumeKey.down), 35);
    });

    test('never leaves the supported 5-300 range', () {
      expect(scrollSpeedAfterVolumeKey(5, VolumeKey.down), 5);
      expect(scrollSpeedAfterVolumeKey(295, VolumeKey.up), 300);
      expect(scrollSpeedAfterVolumeKey(300, VolumeKey.up), 300);
    });
  });

  test('the newest handler wins and popping restores the previous one', () {
    VolumeKeys.clearHandlersForTest();
    final received = <String>[];

    void first(VolumeKey key) => received.add('first:${key.name}');
    void second(VolumeKey key) => received.add('second:${key.name}');

    VolumeKeys.pushHandler(first);
    VolumeKeys.pushHandler(second);
    expect(VolumeKeys.debugHandlers, [first, second]);

    VolumeKeys.dispatchForTest(VolumeKey.down);
    expect(received, ['second:down']);

    VolumeKeys.removeHandler(second);
    VolumeKeys.dispatchForTest(VolumeKey.down);
    expect(received, ['second:down', 'first:down']);

    VolumeKeys.removeHandler(first);
    expect(VolumeKeys.debugHandlers, isEmpty);
    VolumeKeys.dispatchForTest(VolumeKey.down);
    expect(received.length, 2);
  });

  group('ownership', () {
    setUp(VolumeKeys.clearHandlersForTest);
    tearDown(VolumeKeys.clearHandlersForTest);

    test('the topmost handler decides whether the keys are enabled', () {
      void first(VolumeKey _) {}
      void second(VolumeKey _) {}

      VolumeKeys.pushHandler(first);
      VolumeKeys.setDesired(first, true);
      expect(VolumeKeys.debugEnabled, isTrue);

      VolumeKeys.pushHandler(second);
      VolumeKeys.setDesired(second, true);
      expect(VolumeKeys.debugEnabled, isTrue);

      VolumeKeys.removeHandler(second);
      expect(
        VolumeKeys.debugEnabled,
        isTrue,
        reason: 'the reader below still wants the keys',
      );

      VolumeKeys.removeHandler(first);
      expect(VolumeKeys.debugEnabled, isFalse);
    });

    test('a disabled top handler hides the one below until it closes', () {
      void first(VolumeKey _) {}
      void second(VolumeKey _) {}

      VolumeKeys.pushHandler(first);
      VolumeKeys.setDesired(first, true);
      VolumeKeys.pushHandler(second);

      VolumeKeys.setDesired(second, false);
      expect(VolumeKeys.debugEnabled, isFalse);

      VolumeKeys.removeHandler(second);
      expect(VolumeKeys.debugEnabled, isTrue);
    });

    test('setDesired for an unregistered handler is ignored', () {
      VolumeKeys.setDesired((_) {}, true);
      expect(VolumeKeys.debugEnabled, isFalse);
      expect(VolumeKeys.debugWanted, isFalse);
    });

    test('dispatch with no handler does not throw', () {
      expect(VolumeKeys.debugHandlers, isEmpty);
      VolumeKeys.dispatchForTest(VolumeKey.down);
      expect(VolumeKeys.debugEnabled, isFalse);
    });
  });
}
