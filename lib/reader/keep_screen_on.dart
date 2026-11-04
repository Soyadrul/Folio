import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the display awake while a book is open.
///
/// Android implements this with the window's KEEP_SCREEN_ON flag through the
/// `folio/screen` channel. Linux has no equivalent here, so the call is a
/// no-op there and the desktop power settings stay in control.
class KeepScreenOn {
  static const MethodChannel _channel = MethodChannel('folio/screen');

  static bool _enabled = false;

  static bool get supported => Platform.isAndroid;

  static Future<void> setEnabled(bool enabled) async {
    if (!supported || enabled == _enabled) return;
    _enabled = enabled;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } catch (error) {
      debugPrint('Folio: could not change keep-screen-on: $error');
    }
  }
}
