import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The immersive system UI owned by mounted readers.
///
/// A second reader can be pushed on top of the first (an EPUB opened from
/// another app). Entering is counted so closing the top reader does not bring
/// the status bar back while another reader is still open.
class ReaderSystemUi {
  static int _readers = 0;

  static void enter() {
    if (_readers++ > 0) return;
    _applyImmersive();
  }

  /// Puts the bars back after something outside the reader made them visible:
  /// a resumed app, a screen pushed over the reader, or an IME change.
  ///
  /// Android's "sticky" immersive mode normally re-hides them by itself, but
  /// not on every vendor/OS combination, and the flash is visible either way.
  static void reapply() {
    if (_readers == 0) return;
    _applyImmersive();
  }

  static void _applyImmersive() {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  static void leave() {
    if (_readers == 0) return;
    if (--_readers > 0) return;
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  @visibleForTesting
  static int get debugReaders => _readers;

  @visibleForTesting
  static void resetForTest() => _readers = 0;
}
