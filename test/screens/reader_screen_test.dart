import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/models/book.dart';
import 'package:folio/reader/reading_position.dart';
import 'package:folio/reader/webview_reader.dart';
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

  testWidgets('chapter-ready does not erase the restored progress', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

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

    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    final callbacks = state.createCallbacks();
    callbacks.onProgress!(
      const ReaderProgressEvent(
        chapterIndex: 0,
        progress: 0.42,
        page: 3,
        pages: 9,
        element: 'start',
      ),
    );
    // This arrives after JavaScript has restored the position.
    callbacks.onChapterChanged!(0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('folio_reading_position:${epub.path}');
    expect(raw, isNotNull);
    final saved = ReadingPosition.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw!)),
    );
    expect(saved.progress, closeTo(0.42, 0.0001));
    expect(saved.element, 'start');
    expect(saved.overallProgress, greaterThan(0));
  });

  testWidgets('reopening on an auxiliary page keeps the saved book progress', (
    tester,
  ) async {
    late File auxiliaryEpub;
    late SharedPreferences prefs;
    // File IO and prefs must run outside the fake-async zone of testWidgets.
    await tester.runAsync(() async {
      auxiliaryEpub = await EpubFixture.write(
        tmp,
        epubEntries(withAuxiliary: true),
        name: 'auxiliary.epub',
      );
      prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'folio_reading_position:${auxiliaryEpub.path}',
        jsonEncode({
          'chapterIndex': 2,
          'progress': 0.0,
          'overallProgress': 0.5,
        }),
      );
    });
    final book = Book(
      path: auxiliaryEpub.path,
      title: 'Old Book',
      author: 'Jane Doe',
    );
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    final raw = prefs.getString('folio_reading_position:${auxiliaryEpub.path}');
    expect(raw, isNotNull);
    final saved = ReadingPosition.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw!)),
    );
    expect(saved.chapterIndex, 2);
    expect(saved.overallProgress, closeTo(0.5, 0.0001));
  });

  testWidgets('a runtime error banner disappears by itself', (tester) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

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

    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    state.createCallbacks().onError!('This link points outside the book.');
    await tester.pump();

    expect(find.text('This link points outside the book.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('This link points outside the book.'), findsNothing);
  });

  testWidgets('a negative chapter index never reaches the saved position', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

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

    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    final callbacks = state.createCallbacks();
    callbacks.onProgress!(
      const ReaderProgressEvent(
        chapterIndex: -1,
        progress: 0,
        page: 1,
        pages: 1,
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('folio_reading_position:${epub.path}');
    expect(raw, isNotNull);
    final stored = jsonDecode(raw!) as Map<String, dynamic>;
    // `ReadingPosition.fromJson` clamps a negative index, so check the stored
    // value too: the placeholder must never be what the reader writes down.
    expect(stored['chapterIndex'], greaterThanOrEqualTo(0));
    final saved = ReadingPosition.fromJson(stored);
    expect(saved.chapterIndex, greaterThanOrEqualTo(0));
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
///
/// With [withAuxiliary] the spine also contains a non-linear document, the way
/// books keep footnote or endnote pages out of the reading flow.
Map<String, Object> epubEntries({bool withAuxiliary = false}) {
  final entries = <String, Object>{
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
  if (withAuxiliary) {
    entries['OEBPS/content.opf'] = (entries['OEBPS/content.opf']! as String)
        .replaceFirst(
          '<item id="ch2" href="text/ch2.xhtml" '
              'media-type="application/xhtml+xml"/>',
          '<item id="ch2" href="text/ch2.xhtml" '
              'media-type="application/xhtml+xml"/>\n'
              '    <item id="ch3" href="text/ch3.xhtml" '
              'media-type="application/xhtml+xml"/>',
        )
        .replaceFirst(
          '<itemref idref="ch2"/>',
          '<itemref idref="ch2"/>\n    <itemref idref="ch3" linear="no"/>',
        );
    entries['OEBPS/text/ch3.xhtml'] = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Note</title></head>
<body><p id="note">An endnote.</p></body></html>
''';
  }
  return entries;
}
