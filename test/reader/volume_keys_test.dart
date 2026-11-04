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
    test('volume up adds 10 and volume down subtracts 10', () {
      expect(scrollSpeedAfterVolumeKey(40, VolumeKey.up), 50);
      expect(scrollSpeedAfterVolumeKey(40, VolumeKey.down), 30);
    });

    test('never leaves the supported 5-300 range', () {
      expect(scrollSpeedAfterVolumeKey(5, VolumeKey.down), 5);
      expect(scrollSpeedAfterVolumeKey(295, VolumeKey.up), 300);
      expect(scrollSpeedAfterVolumeKey(300, VolumeKey.up), 300);
    });
  });
}
