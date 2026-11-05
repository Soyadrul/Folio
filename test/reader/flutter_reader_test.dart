import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/chapter_html.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/epub/href_resolver.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/reader/flutter_reader.dart';
import 'package:folio/reader/reader_content_controller.dart';
import 'package:folio/reader/webview_reader.dart' show ReaderCallbacks;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpOverrides? previousHttpOverrides;

  setUp(() {
    // The reader body style asks google_fonts for a font. Keep any request
    // pending instead of failing after the test has finished.
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
  });

  testWidgets('a chapter shorter than the screen is not skipped', (
    tester,
  ) async {
    final document = _FakeDocument([
      '<p>Short dedication.</p>',
      _longBody(),
      _longBody(),
    ]);
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(document: document, controller: controller, changes: changes),
    );
    // Extra frames would expose the old cascade where the post-load report
    // immediately loaded chapter 1.
    await _pumpFrames(tester, 3);

    expect(changes, [0]);
    expect(controller.currentChapter, 0);
  });

  testWidgets('prevPage moves back a chapter without bouncing forward', (
    tester,
  ) async {
    final document = _FakeDocument([_longBody(), _longBody()]);
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: controller,
        changes: changes,
        initialChapter: 1,
      ),
    );
    expect(changes, [1]);

    await controller.prevPage();
    await _pumpFrames(tester, 3);

    // The old code restored the previous chapter at its end and immediately
    // treated that as "read to the bottom" -> loaded chapter 1 again.
    expect(controller.currentChapter, 0);
    expect(changes, [1, 0]);
  });

  testWidgets('a load requested while another runs is queued, not dropped', (
    tester,
  ) async {
    final gate = Completer<void>();
    final document = _FakeDocument(
      [_longBody(), _longBody(), _longBody()],
      gates: {1: gate},
    );
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(document: document, controller: controller, changes: changes),
    );

    final first = controller.loadChapter(1);
    final second = controller.loadChapter(2);
    await tester.pump();
    gate.complete();
    await first;
    await second;
    await _pumpFrames(tester, 4);

    expect(controller.currentChapter, 2);
    expect(changes, [0, 1, 2]);
  });
}

Widget _readerApp({
  required EpubDocument document,
  required ReaderContentController controller,
  required List<int> changes,
  int initialChapter = 0,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: FlutterReader(
            document: document,
            settings: const AppSettings(),
            callbacks: ReaderCallbacks(onChapterChanged: changes.add),
            controller: controller,
            initialChapter: initialChapter,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpReader(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  // One frame installs the first chapter, the next runs its post-frame
  // restore/report callback.
  await _pumpFrames(tester, 3);
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump();
  }
}

String _longBody() => List.generate(
  60,
  (index) =>
      '<p>Paragraph $index with enough words to fill an ordinary page of '
      'reading text in the fallback reader.</p>',
).join();

/// An [EpubDocument] whose chapters are handed out directly, so the widget
/// tests never depend on real file IO timing.
class _FakeDocument extends EpubDocument {
  _FakeDocument._(this.bodies, {this.gates})
    : super(
        filePath: 'fake.epub',
        cacheDir: '.',
        opfPath: 'content.opf',
        title: 'Test Book',
        author: 'Author',
        chapters: [
          for (var index = 0; index < bodies.length; index++)
            EpubChapter(
              index: index,
              href: 'text/ch${index + 1}.xhtml',
              relPath: 'text/ch${index + 1}.xhtml',
              path: 'text/ch${index + 1}.xhtml',
              title: 'Chapter ${index + 1}',
              byteSize: bodies[index].length,
              mediaType: 'application/xhtml+xml',
            ),
        ],
        toc: const [],
        coverImagePath: null,
        resolver: HrefResolver(const []),
        totalChapterBytes: bodies.fold(0, (sum, body) => sum + body.length),
      );

  factory _FakeDocument(
    List<String> bodies, {
    Map<int, Completer<void>>? gates,
  }) => _FakeDocument._(bodies, gates: gates);

  final List<String> bodies;
  final Map<int, Completer<void>>? gates;

  @override
  Future<ChapterContent> loadChapterContent(EpubChapter chapter) async {
    final gate = gates?[chapter.index];
    if (gate != null) await gate.future;
    return ChapterContent(
      bodyHtml: bodies[chapter.index],
      headHtml: '',
      missingResources: const [],
    );
  }
}

/// Keeps google_fonts downloads pending for the duration of the test.
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
