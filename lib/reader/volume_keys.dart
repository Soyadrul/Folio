import 'dart:async';
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
/// On other platforms this is a no-op. Readers register in order and the
/// newest registered reader decides whether the activity consumes the keys, so
/// they keep their normal system behaviour in the library and in Settings.
class VolumeKeys {
  static const MethodChannel _channel = MethodChannel('folio/volume');

  static bool get supported => Platform.isAndroid;

  static final Map<void Function(VolumeKey), bool> _handlers = {};
  static bool _installed = false;

  /// What the platform was last told. Tracked on every platform so tests can
  /// assert the decision even where the channel is a no-op.
  static bool _platformEnabled = false;

  /// Registers [handler] as the newest owner of the volume keys.
  ///
  /// A second reader pushed on top of the first (an EPUB opened from another
  /// app) becomes the owner; removing it restores the reader below instead of
  /// leaving the keys handled by nobody.
  static void pushHandler(void Function(VolumeKey) handler) {
    _handlers[handler] = false;
    _install();
    _apply();
  }

  /// Records whether [handler] wants the keys while it is on top.
  ///
  /// Only the newest handler's value reaches the platform, so a reader below a
  /// settings screen or another reader cannot re-enable them.
  static void setDesired(void Function(VolumeKey) handler, bool enabled) {
    if (!_handlers.containsKey(handler)) return;
    if (_handlers[handler] == enabled) return;
    _handlers[handler] = enabled;
    _apply();
  }

  static void removeHandler(void Function(VolumeKey) handler) {
    if (_handlers.remove(handler) == null) return;
    if (_handlers.isEmpty) {
      _installed = false;
      if (supported) _channel.setMethodCallHandler(null);
    }
    _apply();
  }

  static void _apply() {
    final wanted = _handlers.isEmpty ? false : _handlers.values.last;
    if (wanted == _platformEnabled) return;
    _platformEnabled = wanted;
    unawaited(_sendEnabled(wanted));
  }

  static Future<void> _sendEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // A platform without the channel simply keeps the system behaviour.
    } on MissingPluginException {
      // Running on a platform/build without the native side.
    }
  }

  static void _install() {
    if (!supported || _installed) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      final handler = _handlers.isEmpty ? null : _handlers.keys.last;
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
      List.unmodifiable(_handlers.keys);

  @visibleForTesting
  static bool get debugEnabled => _platformEnabled;

  @visibleForTesting
  static bool get debugWanted =>
      _handlers.isEmpty ? false : _handlers.values.last;

  @visibleForTesting
  static void clearHandlersForTest() {
    _handlers.clear();
    _installed = false;
    _platformEnabled = false;
  }

  @visibleForTesting
  static void dispatchForTest(VolumeKey key) {
    if (_handlers.isNotEmpty) _handlers.keys.last(key);
  }
}
