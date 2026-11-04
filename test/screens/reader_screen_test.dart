import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/models/book.dart';
import 'package:folio/screens/reader_screen.dart';
import 'package:folio/utils/theme_utils.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/epub_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File epub;

  late HttpOverrides? previousHttpOverrides;

  setUp(() async {
    // The reader chrome asks google_fonts for Lato, and this machine has no
    // network. Let the font request never finish instead of failing after the
    // test is over; the font itself is irrelevant here.
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('folio_reader_screen_test_');
    epub = await EpubFixture.write(tmp, epubEntries());
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // Closing the reader used to throw "Using ref when a widget is about to or
  // has been unmounted is unsafe", because the last save read the library
  // provider from dispose. The app then logged lifecycle assertions while it
  // shut down instead of exiting cleanly.
  testWidgets('closing the reader saves the position without touching ref', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

    // The EPUB is read with real file IO, so the reader is built while real
    // time passes; pumping alone would leave the load pending forever.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ReaderScreen(book: book, loader: loader),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();

    expect(find.text('One'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount the reader the same way closing the screen does.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((key) => key.startsWith('folio_reading_position:')),
      isNotEmpty,
    );
  });
}

/// Answers every HTTP request with a future that never completes, so font
/// downloads stay pending for the duration of the test.
class _PendingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PendingHttpClient();
}

class _PendingHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getUrl || invocation.memberName == #openUrl) {
      return Completer<HttpClientRequest>().future;
    }
    throw UnimplementedError('${invocation.memberName}');
  }
}

/// A minimal bookmark-sized chapter list without a cover, so the reader has
/// nothing to download and no image decoding to wait for.
Map<String, Object> epubEntries() => {
  'META-INF/container.xml': containerXml,
  'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0"
    unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Old Book</dc:title>
    <dc:creator>Jane Doe</dc:creator>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''',
  'OEBPS/toc.ncx': '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1">
      <navLabel><text>One</text></navLabel>
      <content src="text/ch1.xhtml"/>
    </navPoint>
    <navPoint id="n2" playOrder="2">
      <navLabel><text>Two</text></navLabel>
      <content src="text/ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
''',
  'OEBPS/text/ch1.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>One</title></head>
<body><h1 id="start">Chapter One</h1><p>Hello world.</p></body></html>
''',
  'OEBPS/text/ch2.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Two</title></head>
<body><h1 id="sec">Chapter Two</h1><p>Second chapter.</p></body></html>
''',
};
