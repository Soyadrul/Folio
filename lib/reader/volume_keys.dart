import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../models/app_settings.dart';

enum VolumeKey { up, down }

/// Default mapping: volume down goes forward, volume up goes back.
bool volumeKeyTurnsForward({required VolumeKey key, required bool invert}) =>
    invert ? key == VolumeKey.up : key == VolumeKey.down;

/// Volume up makes automatic scrolling faster, within the supported range.
///
/// Section 7 of the specification asks for steps of 5 pixels per second.
double scrollSpeedAfterVolumeKey(double current, VolumeKey key) {
  final next = current + (key == VolumeKey.up ? 5 : -5);
  return next
      .clamp(AppSettings.minScrollSpeed, AppSettings.maxScrollSpeed)
      .toDouble();
}

/// Bridge to the Android activity that intercepts the hardware volume keys.
///
/// On other platforms this is a no-op. The activity only consumes the keys
/// while [setEnabled] is true, so they keep their normal system behaviour in
/// the library and in Settings.
class VolumeKeys {
  static const MethodChannel _channel = MethodChannel('folio/volume');

  static bool get supported => Platform.isAndroid;

  static Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // A platform without the channel simply keeps the system behaviour.
    } on MissingPluginException {
      // Running on a platform/build without the native side.
    }
  }

  static final List<void Function(VolumeKey)> _handlers = [];
  static bool _installed = false;

  /// Registers [handler] as the current owner of the volume keys.
  ///
  /// A second reader pushed on top of the first (an EPUB opened from another
  /// app) becomes the owner; removing it restores the reader below instead of
  /// leaving the keys handled by nobody.
  static void pushHandler(void Function(VolumeKey) handler) {
    _handlers.add(handler);
    _install();
  }

  static void removeHandler(void Function(VolumeKey) handler) {
    _handlers.remove(handler);
    if (_handlers.isEmpty) {
      _installed = false;
      if (supported) _channel.setMethodCallHandler(null);
    }
  }

  static void _install() {
    if (!supported || _installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      final handler = _handlers.isEmpty ? null : _handlers.last;
      if (handler == null) return null;
      switch (call.method) {
        case 'volumeUp':
          handler(VolumeKey.up);
          break;
        case 'volumeDown':
          handler(VolumeKey.down);
          break;
      }
      return null;
    });
  }

  @visibleForTesting
  static List<void Function(VolumeKey)> get debugHandlers =>
      List.unmodifiable(_handlers);

  @visibleForTesting
  static void clearHandlersForTest() {
    _handlers.clear();
    _installed = false;
  }

  @visibleForTesting
  static void dispatchForTest(VolumeKey key) {
    if (_handlers.isNotEmpty) _handlers.last(key);
  }
}
