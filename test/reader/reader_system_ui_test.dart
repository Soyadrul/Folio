import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/reader_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> modes;

  setUp(() {
    modes = <String>[];
    ReaderSystemUi.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    ReaderSystemUi.resetForTest();
  });

  test(
    'the first reader enters immersive mode and the last one restores it',
    () {
      ReaderSystemUi.enter();
      expect(ReaderSystemUi.debugReaders, 1);
      expect(modes, ['SystemUiMode.immersiveSticky']);

      ReaderSystemUi.enter();
      expect(ReaderSystemUi.debugReaders, 2);
      expect(modes, hasLength(1), reason: 'already immersive');

      ReaderSystemUi.leave();
      expect(ReaderSystemUi.debugReaders, 1);
      expect(modes, hasLength(1), reason: 'one reader is still open');

      ReaderSystemUi.leave();
      expect(ReaderSystemUi.debugReaders, 0);
      expect(modes, [
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);
    },
  );

  test('leaving without entering does nothing', () {
    ReaderSystemUi.leave();
    expect(ReaderSystemUi.debugReaders, 0);
    expect(modes, isEmpty);
  });
}
