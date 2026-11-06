import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/utils/open_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('folio/intents-test');
  late OpenFileService service;
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    service = OpenFileService(channel: channel);
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDown(() async {
    await service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('emits files that were queued before Dart was ready', () async {
    final received = <String>[];
    service.files.listen(received.add);

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'ready');
      return <String>['/cache/first.epub'];
    });

    await service.start();
    await Future<void>.delayed(Duration.zero);

    expect(received, ['/cache/first.epub']);
  });

  test('emits a file delivered while the app is running', () async {
    final received = <String>[];
    service.files.listen(received.add);

    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    await service.start();

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openFile', '/cache/new.epub'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, ['/cache/new.epub']);
  });

  test('ignores an empty or non-string file path', () async {
    final received = <String>[];
    service.files.listen(received.add);

    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    await service.start();

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openFile', ''),
      ),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('openFile', 7),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
  });

  test('ignores a platform without the native channel', () async {
    expect(service.start(), completes);
  });

  test('starting twice does not register the channel twice', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return <String>[];
    });

    await service.start();
    await service.start();

    expect(calls, 1);
  });
}
