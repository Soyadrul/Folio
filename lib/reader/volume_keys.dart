import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';

enum VolumeKey { up, down }

/// Default mapping: volume down goes forward, volume up goes back.
bool volumeKeyTurnsForward({required VolumeKey key, required bool invert}) =>
    invert ? key == VolumeKey.up : key == VolumeKey.down;

/// Volume up makes automatic scrolling faster, within the supported range.
double scrollSpeedAfterVolumeKey(double current, VolumeKey key) {
  final next = current + (key == VolumeKey.up ? 10 : -10);
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

  /// Installs (or clears, with null) the callback for key presses.
  static void setHandler(void Function(VolumeKey key)? handler) {
    if (!supported) return;
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
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
}
