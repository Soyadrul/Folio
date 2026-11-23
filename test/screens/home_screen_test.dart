import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/library/cover_service.dart';
import 'package:folio/models/book.dart';
import 'package:folio/providers/library_provider.dart';
import 'package:folio/screens/home_screen.dart';
import 'package:folio/utils/theme_utils.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late HttpOverrides? previousHttpOverrides;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
    tmp = await Directory.systemTemp.createTemp('folio_home_screen_test_');
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('a refresh keeps the books on screen', (tester) async {
    const book = Book(path: '/books/a.epub', title: 'Old Book', author: 'Jane');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith(() => _RefreshingLibrary(book)),
          coverServiceProvider.overrideWithValue(
            CoverService(cacheRoot: Directory(p.join(tmp.path, 'covers'))),
          ),
        ],
        child: MaterialApp(theme: buildLightTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Old Book'), findsWidgets);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'the grid must not be replaced by a full-screen spinner',
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('the first load still shows a full-screen spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith(() => _RefreshingLibrary(null)),
          coverServiceProvider.overrideWithValue(
            CoverService(cacheRoot: Directory(p.join(tmp.path, 'covers'))),
          ),
        ],
        child: MaterialApp(theme: buildLightTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}

/// A library that is refreshing while already holding [book].
class _RefreshingLibrary extends LibraryNotifier {
  _RefreshingLibrary(this.book);

  final Book? book;

  @override
  LibraryState build() =>
      LibraryState(folderPath: '/books', books: [?book], isLoading: true);
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
    return null;
  }
}
