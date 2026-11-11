import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/library/cache_service.dart';
import 'package:folio/library/cover_service.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/providers/settings_provider.dart';
import 'package:folio/screens/settings_screen.dart';
import 'package:folio/utils/theme_utils.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previousHttpOverrides;

  setUp(() {
    // Settings styles use google_fonts, and this machine has no network. Let
    // the font request never finish instead of failing the test when it runs
    // real async work; the font itself is irrelevant here.
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  testWidgets('shows every section from the specification', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MODE'), findsOneWidget);
    expect(find.text('BOTH MODES'), findsOneWidget);
    expect(find.text('Font size'), findsOneWidget);
    expect(find.text('Line spacing'), findsOneWidget);
    expect(find.text('Margins'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('BOOK MODE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BOOK MODE'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('SCROLL MODE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SCROLL MODE'), findsOneWidget);
    expect(find.text('Scroll speed'), findsOneWidget);
    expect(find.text('Start automatically when book opens'), findsOneWidget);
  });

  testWidgets('changing the mode applies and saves immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container.read(settingsNotifierProvider).readerMode,
      ReaderMode.book,
    );

    // The mode chips are near the top, above the lazily built groups.
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsNotifierProvider).readerMode,
      ReaderMode.scroll,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.readerMode, ReaderMode.scroll);
  });

  testWidgets('Reset asks for confirmation before discarding settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Reset settings?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('theme choices are Light, Sepia and Dark only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Sepia'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
  });

  testWidgets('Clear cache asks first and empties the cache directories', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('folio_settings_cache_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final epubRoot = Directory(p.join(tmp.path, 'epub'))..createSync();
    final coversRoot = Directory(p.join(tmp.path, 'covers'))..createSync();
    final bookDir = Directory(p.join(epubRoot.path, 'epub_old'))
      ..createSync(recursive: true);
    File(p.join(bookDir.path, '.folio-cache.json')).writeAsStringSync(
      jsonEncode({'path': p.join(tmp.path, 'gone.epub'), 'size': 1, 'mtime': 1}),
    );
    File(p.join(coversRoot.path, 'thumb.jpg')).writeAsBytesSync([1]);

    final service = CacheService(
      epubLoader: EpubLoader(cacheRoot: epubRoot),
      coverService: CoverService(cacheRoot: coversRoot),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cacheServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('clear-cache')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('clear-cache')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-cache')));
    await tester.pumpAndSettle();
    expect(find.text('Clear cache?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();
    // The handler awaits real file IO. The widget test runs in a fake-async
    // zone, so alternate real time with pumps until the service finishes.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Cache cleared'), findsOneWidget);

    expect(coverList(coversRoot), isEmpty);
    expect(epubRoot.existsSync() && epubRoot.listSync().isNotEmpty, isFalse);
  });
}

List<File> coverList(Directory root) => root.existsSync()
    ? root.listSync().whereType<File>().toList()
    : const <File>[];

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
