import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Receives one message per uncaught error.
typedef ErrorLogger =
    void Function(String message, Object error, StackTrace? stackTrace);

/// Makes Dart errors visible in `logcat` on release builds.
///
/// `debugPrint` is compiled down to a no-op sink in release mode, so without
/// these handlers a report of "the app misbehaved" leaves no trail at all.
/// [developer.log] goes to the platform log in every build mode and shows up
/// under the `Folio` tag.
void installErrorReporting({ErrorLogger? logger}) {
  final log = logger ?? _logToDeveloper;

  FlutterError.onError = (details) {
    // Keep the default console output in debug builds.
    FlutterError.presentError(details);
    log(
      'Flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log('Uncaught error: $error', error, stackTrace);
    // The error is reported; do not take the process down with it.
    return true;
  };
}

void _logToDeveloper(String message, Object error, StackTrace? stackTrace) {
  developer.log(message, name: 'Folio', error: error, stackTrace: stackTrace);
}
