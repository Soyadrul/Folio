import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:folio/reader/webview_security.dart';

void main() {
  test('disables content access and file-origin privilege escalation', () {
    final settings = readerWebViewSettings();
    expect(settings.javaScriptEnabled, isTrue);
    expect(settings.allowFileAccess, isTrue);
    expect(settings.allowContentAccess, isFalse);
    expect(settings.allowFileAccessFromFileURLs, isFalse);
    expect(settings.allowUniversalAccessFromFileURLs, isFalse);
  });

  test('blocks network loads in the offline release build', () {
    final settings = readerWebViewSettings();
    // Android throws SecurityException from setBlockNetworkLoads(false) when
    // the app has no INTERNET permission, which aborts platform-view creation.
    // `true` is always allowed and local file/data loads still work.
    expect(settings.blockNetworkLoads, isTrue);
  });

  test('CSP allows only local resources and the shell script hash', () {
    const script = 'console.log("folio");';
    final csp = readerContentSecurityPolicy(script);
    final expected = base64.encode(sha256.convert(utf8.encode(script)).bytes);

    expect(csp, contains("script-src 'sha256-$expected'"));
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("img-src file: data:"));
    expect(csp, contains("frame-src 'none'"));
    expect(csp, contains("object-src 'none'"));
    expect(csp, contains('connect-src'));
  });

  test('blocks every navigation after the shell has loaded', () {
    final url = WebUri('https://example.com/tracker');
    expect(readerAllowsNavigation(shellLoaded: false, url: url), isTrue);
    expect(readerAllowsNavigation(shellLoaded: true, url: url), isFalse);
    expect(readerAllowsNavigation(shellLoaded: true, url: null), isFalse);
  });
}
