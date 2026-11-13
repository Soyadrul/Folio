import 'dart:async';
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

  static final Map<Object, bool> _owners = {};
  static bool _platformEnabled = false;

  static bool get supported => Platform.isAndroid;

  /// Temporary bridge for the code that still toggles the screen directly.
  ///
  /// [ReaderScreen] moves to [acquire] in the next task; until then this keeps
  /// the existing wiring working while the registry is introduced.
  static Future<void> setEnabled(bool enabled) async {
    if (enabled == _platformEnabled) return;
    _platformEnabled = enabled;
    if (!supported) return;
    await _send(enabled);
  }

  /// Registers a reader that wants the screen kept awake and what it wants.
  static void acquire(Object owner, {bool enabled = false}) {
    _owners[owner] = enabled;
    _apply();
  }

  /// Records a settings change for an already registered reader.
  static void update(Object owner, bool enabled) {
    if (!_owners.containsKey(owner)) return;
    if (_owners[owner] == enabled) return;
    _owners[owner] = enabled;
    _apply();
  }

  /// Forgets [owner]; the reader below (if any) takes over again.
  static void release(Object owner) {
    if (_owners.remove(owner) == null) return;
    _apply();
  }

  static void _apply() {
    final wanted = _owners.isEmpty ? false : _owners.values.last;
    if (wanted == _platformEnabled) return;
    _platformEnabled = wanted;
    if (!supported) return;
    unawaited(_send(wanted));
  }

  static Future<void> _send(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } catch (error) {
      debugPrint('Folio: could not change keep-screen-on: $error');
    }
  }

  @visibleForTesting
  static bool get debugWanted => _platformEnabled;

  @visibleForTesting
  static void resetForTest() {
    _owners.clear();
    _platformEnabled = false;
  }
}
