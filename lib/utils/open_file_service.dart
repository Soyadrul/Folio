import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives EPUB files opened from other Android apps.
///
/// The native side copies `content://` URIs into the app cache first, so the
/// stream always emits a readable file path. Files are delivered either from
/// the queue that existed before Dart was ready or as `openFile` events while
/// the app is running.
class OpenFileService {
  OpenFileService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('folio/intents');

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();
  bool _started = false;

  /// File paths, in the order the intents arrived.
  Stream<String> get files => _controller.stream;

  /// Starts listening and returns the files that arrived before Dart was ready.
  ///
  /// Calling this more than once is harmless. On platforms without the native
  /// channel the missing plugin is ignored.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_handleCall);
    try {
      final files = await _channel.invokeMethod<List<dynamic>>('ready');
      if (files == null) return;
      for (final path in files) {
        if (path is String && path.isNotEmpty) _controller.add(path);
      }
    } on MissingPluginException {
      // Linux, tests and any platform without the Android intent handler.
    } on PlatformException catch (error) {
      debugPrint('Folio: could not receive the opened file: $error');
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'openFile') return;
    final path = call.arguments;
    if (path is String && path.isNotEmpty) _controller.add(path);
  }

  Future<void> dispose() => _controller.close();
}
