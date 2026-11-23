import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/utils/error_reporting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterExceptionHandler? previousFlutterError;
  late bool Function(Object, StackTrace)? previousPlatformError;

  setUp(() {
    previousFlutterError = FlutterError.onError;
    previousPlatformError = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = previousFlutterError;
    PlatformDispatcher.instance.onError = previousPlatformError;
  });

  test('framework errors reach the Folio log', () {
    final entries = <String>[];
    installErrorReporting(
      logger: (message, error, stack) =>
          entries.add('$message|$error|${stack != null}'),
    );

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.current,
        library: 'test',
      ),
    );

    expect(entries, hasLength(1));
    expect(entries.single, contains('boom'));
    expect(entries.single, endsWith('|true'));
  });

  test('platform errors are logged and swallowed', () {
    final entries = <String>[];
    installErrorReporting(
      logger: (message, error, stack) =>
          entries.add('$message|$error|${stack != null}'),
    );

    final handled = PlatformDispatcher.instance.onError!(
      StateError('async boom'),
      StackTrace.current,
    );

    expect(handled, isTrue, reason: 'an error must not crash the app');
    expect(entries, hasLength(1));
    expect(entries.single, contains('async boom'));
  });
}
