import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/chapter_html.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/epub/href_resolver.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/reader/flutter_reader.dart';
import 'package:folio/reader/reader_content_controller.dart';
import 'package:folio/reader/webview_reader.dart'
    show ReaderCallbacks, ReaderProgressEvent;
import 'package:path/path.dart' as p;

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

  testWidgets('tapping a link with a fragment decodes the anchor', (
    tester,
  ) async {
    final document = _FakeDocument([
      '<p><a href="file:///book/text/ch2.xhtml#note%201">note</a></p>',
      '<aside id="note 1">The note.</aside>',
    ]);
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(document: document, controller: controller, changes: changes),
    );

    await tester.tapOnText(find.textRange.ofSubstring('note'));
    await _pumpFrames(tester, 3);

    expect(tester.takeException(), isNull);
    expect(changes, [0, 1]);
    expect(controller.currentChapter, 1);
  });

  testWidgets('an in-chapter fragment link jumps to the decoded anchor', (
    tester,
  ) async {
    final document = _FakeDocument([
      '<p><a href="#note%201">jump</a></p>'
          '${_longBody()}<aside id="note 1">The note.</aside>',
    ]);
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(document: document, controller: controller, changes: changes),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);

    await tester.tapOnText(find.textRange.ofSubstring('jump'));
    await _pumpFrames(tester, 3);

    expect(tester.takeException(), isNull);
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('a malformed in-chapter fragment does not throw', (tester) async {
    final document = _FakeDocument([
      '<p><a href="#100%">broken</a></p>${_longBody()}',
    ]);
    final changes = <int>[];
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(document: document, controller: controller, changes: changes),
    );
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);

    await tester.tapOnText(find.textRange.ofSubstring('broken'));
    await _pumpFrames(tester, 3);

    // Decoding falls back to the raw id, which matches nothing here.
    expect(tester.takeException(), isNull);
    expect(scrollable.position.pixels, 0);
  });

  testWidgets('a settings slider change updates the Linux scroll speed', (
    tester,
  ) async {
    final document = _FakeDocument([_longBody()]);
    final controller = ReaderContentController();

    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: controller,
        changes: [],
        settings: const AppSettings(autoScrollSpeed: 40),
      ),
    );
    final state = tester.state<FlutterReaderState>(find.byType(FlutterReader));
    expect(state.autoScrollSpeed, 40);

    await tester.pumpWidget(
      _readerApp(
        document: document,
        controller: controller,
        changes: [],
        settings: const AppSettings(autoScrollSpeed: 120),
      ),
    );

    expect(state.autoScrollSpeed, 120);
  });

  testWidgets('SVG images render in the Linux reader', (tester) async {
    final directory = Directory.systemTemp.createTempSync('folio_svg_');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final svg = File(p.join(directory.path, 'picture.svg'))
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">'
        '<rect width="40" height="40" fill="#bd8c3c"/></svg>',
      );

    final document = _FakeDocument([
      '<p>Before</p><p><img src="${Uri.file(svg.path)}" alt="drawing"/></p>',
    ]);
    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: ReaderContentController(),
        changes: [],
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('an SVG image with a fragment renders without throwing', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('folio_svg_frag_');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final svg = File(p.join(directory.path, 'fragment.svg'))
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">'
        '<rect id="box" width="40" height="40" fill="#bd8c3c"/></svg>',
      );

    final document = _FakeDocument([
      '<p><img src="${Uri.file(svg.path)}#box" alt="drawing"/></p>',
    ]);
    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: ReaderContentController(),
        changes: [],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('progress carries the first visible anchor', (tester) async {
    final events = <ReaderProgressEvent>[];
    final controller = ReaderContentController();
    final document = _FakeDocument([_anchoredBody()]);

    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: controller,
        changes: [],
        callbacks: ReaderCallbacks(
          onChapterChanged: (_) {},
          onProgress: events.add,
        ),
      ),
    );

    events.clear();
    await controller.goToProgress(0.5);
    await tester.pump(const Duration(milliseconds: 130));
    await _pumpFrames(tester, 2);

    expect(events, isNotEmpty);
    expect(events.last.element, isNotNull);
  });

  testWidgets('scroll notifications are coalesced into one report', (
    tester,
  ) async {
    var pages = 0;
    final document = _FakeDocument([_longBody(), _longBody()]);

    await _pumpReader(
      tester,
      _readerApp(
        document: document,
        controller: ReaderContentController(),
        changes: [],
        callbacks: ReaderCallbacks(
          onChapterChanged: (_) {},
          onPage: (_, _) => pages++,
        ),
      ),
    );

    pages = 0;
    await tester.drag(find.byType(FlutterReader), const Offset(0, -200));
    await tester.pump();
    expect(pages, 0, reason: 'the first notification only schedules a report');

    await tester.pump(const Duration(milliseconds: 121));
    expect(pages, 1, reason: 'the pending notifications collapse into one');
  });
}

Widget _readerApp({
  required EpubDocument document,
  required ReaderContentController controller,
  required List<int> changes,
  ReaderCallbacks? callbacks,
  int initialChapter = 0,
  AppSettings settings = const AppSettings(),
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: FlutterReader(
            document: document,
            settings: settings,
            callbacks:
                callbacks ?? ReaderCallbacks(onChapterChanged: changes.add),
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

String _anchoredBody() => List.generate(
  80,
  (index) =>
      '<p id="anchor-$index">Paragraph $index with enough words to fill an '
      'ordinary page of reading text in the fallback reader.</p>',
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
              // [EpubChapter.path] is the absolute path on disk.
              path: '/book/text/ch${index + 1}.xhtml',
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
