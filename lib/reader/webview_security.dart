import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView settings for the reader shell.
///
/// The shell is loaded from a `file://` base so it can show the book's local
/// images and stylesheets. Only that read access is granted: untrusted book
/// content must not be able to read other local files, call `content://`
/// providers, or reach the network from a `file://` origin.
InAppWebViewSettings readerWebViewSettings({bool inspectable = false}) {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    transparentBackground: true,
    allowFileAccess: true,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    supportZoom: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: false,
    disableHorizontalScroll: false,
    mediaPlaybackRequiresUserGesture: true,
    isInspectable: inspectable,
  );
}

/// Content-Security-Policy for the reader shell.
///
/// Everything is denied by default. Images, styles, fonts and media may only
/// come from the extracted book (`file:`) or inline data. The shell is the
/// only script allowed, identified by the SHA-256 hash of [shellScript], so
/// book markup cannot inject another script even if the HTML sanitiser misses
/// a construct.
String readerContentSecurityPolicy(String shellScript) {
  final digest = sha256.convert(utf8.encode(shellScript));
  final hash = base64.encode(digest.bytes);
  return "default-src 'none'; "
      "img-src file: data:; "
      "style-src file: 'unsafe-inline'; "
      "font-src file: data:; "
      "media-src file: data:; "
      "script-src 'sha256-$hash'; "
      "frame-src 'none'; "
      "object-src 'none'; "
      "connect-src 'none'; "
      "base-uri 'none'; "
      "form-action 'none'";
}

/// Whether the WebView may navigate to [url].
///
/// Only the very first document (the in-memory shell) is allowed. After that,
/// every navigation is a book link that must be handled by Dart; letting the
/// WebView follow it would replace the reader shell or leave the book.
bool readerAllowsNavigation({required bool shellLoaded, WebUri? url}) {
  if (!shellLoaded) return true;
  return false;
}
