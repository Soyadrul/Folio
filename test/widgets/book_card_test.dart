import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/library/cover_service.dart';
import 'package:folio/models/book.dart';
import 'package:folio/utils/theme_utils.dart';
import 'package:folio/widgets/book_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previousHttpOverrides;

  setUp(() {
    // BookCard asks google_fonts for Lato and Playfair Display. Keep the
    // requests pending so the test does not depend on the network.
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  testWidgets('a slow cover cannot paint on the card of another book', (
    tester,
  ) async {
    final service = _PendingCoverService();
    const first = Book(path: '/books/first.epub', title: 'First', author: 'A');
    const second = Book(
      path: '/books/second.epub',
      title: 'Second',
      author: 'B',
    );

    await tester.pumpWidget(_app(first, service));
    await tester.pump();

    // The grid reuses this card's State for another book, e.g. after a filter.
    await tester.pumpWidget(_app(second, service));
    await tester.pump();

    service.complete(first.path, '/covers/first.jpg');
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    service.complete(second.path, '/covers/second.jpg');
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    final fileImage = provider is ResizeImage
        ? provider.imageProvider as FileImage
        : provider as FileImage;
    expect(fileImage.file.path, '/covers/second.jpg');
  });

  testWidgets('the progress strip shows overall book progress', (tester) async {
    final service = _PendingCoverService();
    const book = Book(
      path: '/books/progress.epub',
      title: 'Progress',
      author: 'A',
      lastProgress: 0.1,
      overallProgress: 0.6,
    );

    await tester.pumpWidget(_app(book, service));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.6);
  });
}

Widget _app(Book book, CoverService service) {
  return ProviderScope(
    overrides: [coverServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 280,
          child: BookCard(book: book, onTap: () {}),
        ),
      ),
    ),
  );
}

class _PendingCoverService extends CoverService {
  final Map<String, Completer<String?>> _pending = {};

  @override
  Future<String?> thumbnailFor(Book book) {
    return _pending.putIfAbsent(book.path, Completer<String?>.new).future;
  }

  void complete(String path, String? thumbnail) {
    _pending[path]?.complete(thumbnail);
  }
}

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
