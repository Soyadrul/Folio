import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/models/book.dart';
import 'package:folio/providers/library_provider.dart';
import 'package:folio/providers/settings_provider.dart';
import 'package:folio/reader/keep_screen_on.dart';
import 'package:folio/reader/reader_system_ui.dart';
import 'package:folio/reader/reading_position.dart';
import 'package:folio/reader/volume_keys.dart';
import 'package:folio/reader/webview_reader.dart';
import 'package:folio/screens/reader_screen.dart';
import 'package:folio/screens/settings_screen.dart';
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
    VolumeKeys.clearHandlersForTest();
    KeepScreenOn.resetForTest();
    ReaderSystemUi.resetForTest();
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

  testWidgets('pausing the app flushes pending settings immediately', (
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReaderScreen)),
    );
    await tester.runAsync(() async {
      await container
          .read(settingsNotifierProvider.notifier)
          .update((s) => s.copyWith(fontSize: 19));
    });

    final prefs = await SharedPreferences.getInstance();
    // Still inside the notifier's 250 ms debounce window: nothing on disk yet.
    expect(prefs.getString('folio_app_settings'), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.fontSize, 19);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('volume keys are released while Settings is open', (
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
    expect(VolumeKeys.debugEnabled, isTrue);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(VolumeKeys.debugEnabled, isFalse);

    // A setting changed inside Settings fires the same listener that would
    // normally re-enable the keys on the hidden reader.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.runAsync(() async {
      await container
          .read(settingsNotifierProvider.notifier)
          .update((s) => s.copyWith(keepScreenOn: false));
    });
    await tester.pump();
    expect(VolumeKeys.debugEnabled, isFalse);

    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(VolumeKeys.debugEnabled, isTrue);
  });

  testWidgets('closing a stacked reader keeps the one below working', (
    tester,
  ) async {
    late File secondEpub;
    await tester.runAsync(() async {
      secondEpub = await EpubFixture.write(
        tmp,
        epub2Entries(),
        name: 'second.epub',
      );
    });
    final first = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final second = Book(
      path: secondEpub.path,
      title: 'Second Book',
      author: 'Jane Doe',
    );
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildLightTheme(),
            home: ReaderScreen(book: first, loader: loader),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    expect(VolumeKeys.debugEnabled, isTrue);
    expect(ReaderSystemUi.debugReaders, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(book: second, loader: loader),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    expect(ReaderSystemUi.debugReaders, 2);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(ReaderSystemUi.debugReaders, 1);
    expect(
      VolumeKeys.debugEnabled,
      isTrue,
      reason: 'the first reader must get its keys back',
    );
    expect(
      KeepScreenOn.debugWanted,
      isTrue,
      reason: 'the first reader still wants the screen awake',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(ReaderSystemUi.debugReaders, 0);
    expect(VolumeKeys.debugEnabled, isFalse);
    expect(KeepScreenOn.debugWanted, isFalse);
  });

  testWidgets('the last position reaches the library after the reader closes', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));
    final container = ProviderContainer(
      overrides: [libraryProvider.overrideWith(() => _SeededLibrary(book))],
    );
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
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

    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    final callbacks = state.createCallbacks();
    // The first event saves synchronously. The second arrives inside the
    // 500 ms throttle window, so only the forced save in `dispose` writes it:
    // the assertions below then prove the deferred write really lands.
    callbacks.onProgress!(
      const ReaderProgressEvent(
        chapterIndex: 1,
        progress: 0.75,
        page: 2,
        pages: 3,
        element: 'sec',
      ),
    );
    callbacks.onProgress!(
      const ReaderProgressEvent(
        chapterIndex: 2,
        progress: 0.9,
        page: 9,
        pages: 9,
        element: 'end',
      ),
    );

    // Close the reader the same way the library does: swap the screen out while
    // the provider container lives on.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const _LibraryHome(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final saved = container.read(libraryProvider).books.single;
    expect(saved.lastChapterIndex, 2);
    expect(saved.lastProgress, closeTo(0.9, 0.0001));
  });

  testWidgets('closing the reader before the book loads does not throw', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: ReaderScreen(book: book, loader: _PendingLoader()),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('system back returns to the previous location before leaving', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));
    await _pushReader(tester, book: book, loader: loader);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('One'), findsOneWidget);

    // A contents jump records the old location, which is what the undo icon
    // and the system Back gesture should both use.
    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Two'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(ReaderScreen),
      findsOneWidget,
      reason: 'Back must not close the book while in-book history exists',
    );
    expect(
      find.byIcon(Icons.undo_rounded),
      findsNothing,
      reason: 'Back must consume the recorded history entry',
    );
  });

  testWidgets('system back closes the table of contents before the book', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));
    await _pushReader(tester, book: book, loader: loader);

    await tester.tap(find.byIcon(Icons.format_list_bulleted_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Contents'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Contents'), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('system back leaves the book when there is no history', (
    tester,
  ) async {
    final book = Book(path: epub.path, title: 'Old Book', author: 'Jane Doe');
    final loader = EpubLoader(cacheRoot: Directory(p.join(tmp.path, 'cache')));
    await _pushReader(tester, book: book, loader: loader);
    expect(find.byIcon(Icons.undo_rounded), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.text('books: 0'), findsOneWidget);
  });
}

/// Pushes a reader on top of a stand-in home screen, so a Back gesture has a
/// route to leave, and waits for the book to load.
///
/// The document is parsed with real file IO first and then handed to the
/// reader through a loader that returns an already-completed future: the route
/// is pushed in the fake-async zone, where pending file IO would never finish.
Future<void> _pushReader(
  WidgetTester tester, {
  required Book book,
  required EpubLoader loader,
}) async {
  late EpubDocument document;
  await tester.runAsync(() async {
    document = await loader.load(book.path);
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(theme: buildLightTheme(), home: const _LibraryHome()),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  unawaited(
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(book: book, loader: _LoadedLoader(document)),
      ),
    ),
  );
  await tester.pump();
  // Two real-time rounds: the first lets the EPUB load and mount the content
  // view, the second lets that view read the first chapter from disk. The
  // continuations land in the fake-async zone, so a pump follows each round.
  for (var i = 0; i < 2; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Serves an [EpubDocument] that was parsed before the widget test started.
class _LoadedLoader extends EpubLoader {
  _LoadedLoader(this.document);

  final EpubDocument document;

  @override
  Future<EpubDocument> load(String filePath) async => document;
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

/// A library notifier that already contains [book], so the reader's position
/// update is visible without running a folder scan.
class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(this.book);

  final Book book;

  @override
  LibraryState build() => LibraryState(books: [book]);
}

/// A stand-in for the home screen: only the library book count is needed.
class _LibraryHome extends ConsumerWidget {
  const _LibraryHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).books;
    return Scaffold(
      body: Text('books: ${books.length}', textDirection: TextDirection.ltr),
    );
  }
}

/// Never finishes loading, so the reader can be closed mid-load.
class _PendingLoader extends EpubLoader {
  @override
  Future<EpubDocument> load(String filePath) =>
      Completer<EpubDocument>().future;
}
