import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../epub/chapter_html.dart';
import '../epub/epub.dart';
import '../epub/href_resolver.dart';
import '../models/app_settings.dart';
import '../utils/theme_utils.dart';
import 'chapter_transfer_queue.dart';
import 'reader_content_controller.dart';
import 'reader_fonts.dart';
import 'webview_security.dart';

/// Event reported by the WebView while the reader moves through a book.
class ReaderProgressEvent {
  const ReaderProgressEvent({
    required this.chapterIndex,
    required this.progress,
    required this.page,
    required this.pages,
    this.element,
  });

  final int chapterIndex;
  final double progress;
  final int page;
  final int pages;
  final String? element;
}

/// Reads a numeric bridge field without throwing on malformed payloads.
num? _num(Object? value) => value is num ? value : null;

/// Reads a string bridge field without throwing on malformed payloads.
String? _string(Object? value) => value is String ? value : null;

/// Parses a `progress` bridge message, rejecting the shell's pre-chapter
/// placeholder (`chapterIndex: -1`) and malformed payloads.
ReaderProgressEvent? progressEventFromMessage(Map<String, dynamic> message) {
  if (message['type'] != 'progress') return null;
  final chapter = _num(message['chapterIndex'])?.toInt() ?? -1;
  if (chapter < 0) return null;
  final rawProgress = _num(message['progress'])?.toDouble() ?? 0;
  final progress = rawProgress.isFinite
      ? rawProgress.clamp(0.0, 1.0).toDouble()
      : 0.0;
  final page = _num(message['page'])?.toInt() ?? 1;
  final pages = _num(message['pages'])?.toInt() ?? 1;
  final element = _string(message['element']);
  return ReaderProgressEvent(
    chapterIndex: chapter,
    progress: progress,
    page: page < 1 ? 1 : page,
    pages: pages < 1 ? 1 : pages,
    element: element != null && element.isNotEmpty ? element : null,
  );
}

class ReaderCallbacks {
  const ReaderCallbacks({
    this.onProgress,
    this.onPage,
    this.onChapterChanged,
    this.onToggleChrome,
    this.onAutoScroll,
    this.onBoundary,
    this.onReady,
    this.onError,
    this.onHistoryChanged,
  });

  final void Function(ReaderProgressEvent event)? onProgress;
  final void Function(int page, int pages)? onPage;
  final void Function(int chapterIndex)? onChapterChanged;
  final VoidCallback? onToggleChrome;
  final void Function(bool running, int speed)? onAutoScroll;
  final void Function(int direction)? onBoundary;
  final VoidCallback? onReady;
  final void Function(String message)? onError;

  /// Whether the reader can jump back to a position it visited by following a
  /// link or a table-of-contents entry.
  final void Function(bool canGoBack)? onHistoryChanged;
}

/// The Android reader: one WebView shell that receives chapter HTML from Dart.
///
/// Chapters are swapped inside the document instead of navigating, so moving
/// between chapters never reloads or flashes the WebView.
class WebViewReader extends ConsumerStatefulWidget {
  const WebViewReader({
    super.key,
    required this.document,
    required this.settings,
    required this.callbacks,
    required this.controller,
    this.initialChapter = 0,
    this.initialProgress = 0,
    this.initialElement,
  });

  final EpubDocument document;
  final AppSettings settings;
  final ReaderCallbacks callbacks;
  final ReaderContentController controller;
  final int initialChapter;
  final double initialProgress;
  final String? initialElement;

  @override
  ConsumerState<WebViewReader> createState() => WebViewReaderState();
}

class WebViewReaderState extends ConsumerState<WebViewReader>
    implements ReaderViewBackend {
  InAppWebViewController? _controller;
  String? _shellHtml;
  String? _fontFacesFamily;
  bool _shellReady = false;
  bool _shellLoaded = false;
  bool _loadingChapter = false;
  int _currentChapter = 0;
  int _requestedChapter = -1;
  int? _pendingChapter;
  double _pendingProgress = 0;
  String? _pendingElement;
  double _lastProgress = 0;
  String? _lastElement;

  /// Values used by `_onLoadStop` to restore the reader after the shell
  /// reloads. Only chapter loads and real progress events update them; the
  /// shell's pre-chapter placeholder never reaches them.
  double _restoreProgress = 0;
  String? _restoreElement;
  bool _autoScrollRunning = false;
  int _autoScrollSpeed = 40;

  /// Brightness captured during the last build. `_onLoadStop` can complete
  /// after the reader closed, when reading `MediaQuery` would throw.
  Brightness _brightness = Brightness.light;

  /// Incremented after the WebView renderer dies so a fresh platform view is
  /// created instead of leaving the reader on a blank page.
  int _webViewGeneration = 0;

  /// Keeps each `evaluateJavascript` call small. A single-file book can have
  /// chapters several megabytes long, and handing all of that to the
  /// JavaScript bridge at once can exhaust it.
  static const _maxScriptChunk = 128 * 1024;

  final Map<int, ChapterContent> _chapterCache = {};
  static const _cacheLimit = 4;

  /// Serialises chapter transfers: JavaScript has a single chapter buffer, so
  /// two in-flight sends would interleave their chunks.
  final ChapterTransferQueue _transfers = ChapterTransferQueue();

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
    _currentChapter = widget.initialChapter;
    _requestedChapter = widget.initialChapter;
    _lastProgress = widget.initialProgress;
    _lastElement = widget.initialElement;
    _restoreProgress = widget.initialProgress;
    _restoreElement = widget.initialElement;
    _loadShell();
  }

  @override
  void didUpdateWidget(covariant WebViewReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.filePath != widget.document.filePath) {
      _chapterCache.clear();
      _loadChapter(
        widget.initialChapter,
        progress: widget.initialProgress,
        element: widget.initialElement,
      );
      return;
    }
    if (oldWidget.settings == widget.settings) return;

    final modeChanged =
        oldWidget.settings.readerMode != widget.settings.readerMode;
    final typographyChanged =
        oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.fontFamily != widget.settings.fontFamily ||
        oldWidget.settings.textAlign != widget.settings.textAlign ||
        oldWidget.settings.hyphenation != widget.settings.hyphenation ||
        oldWidget.settings.readingMode != widget.settings.readingMode;
    final marginChanged =
        oldWidget.settings.marginHorizontal != widget.settings.marginHorizontal;

    _background(
      _applySettingsAndRestore(
        modeChanged: modeChanged,
        reflow: typographyChanged || marginChanged,
        marginChanged: marginChanged,
      ),
    );
  }

  Future<void> _applySettingsAndRestore({
    required bool modeChanged,
    required bool reflow,
    required bool marginChanged,
  }) async {
    await _ensureFontFaces();
    // Every setting lives in the same object, so pushing the whole settings
    // object also applies tap zones, swipe, page animation and auto-scroll
    // options without reopening the book.
    await _applySettingsToPage();
    if (modeChanged) {
      // Multi-column and scrolling layouts need a fresh chapter document.
      await _loadChapter(
        _currentChapter,
        progress: _lastProgress,
        element: _lastElement,
      );
      return;
    }
    if (!reflow) return;
    await _goToProgress(_lastProgress, _lastElement);
    if (marginChanged) {
      // Margins are Flutter padding, so the platform view receives its new
      // width only after the next frame. Restore the position once more when
      // the WebView has actually resized, otherwise the page count is stale.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      await _goToProgress(_lastProgress, _lastElement);
    }
  }

  Future<void> _loadShell() async {
    try {
      final css = await rootBundle.loadString('assets/reader/reader.css');
      final js = await rootBundle.loadString('assets/reader/reader.js');
      var family = widget.settings.fontFamily;
      var fonts = await readerFontFaceCss(family);
      if (!mounted) return;
      // The setting may have changed while the assets decoded.
      if (family != widget.settings.fontFamily) {
        family = widget.settings.fontFamily;
        fonts = await readerFontFaceCss(family);
        if (!mounted) return;
      }
      setState(() {
        _fontFacesFamily = family;
        _shellHtml =
            '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="${readerContentSecurityPolicy(js)}">
<style id="folio-font-faces">$fonts</style>
<style>$css</style>
</head>
<body>
<div id="folio-viewport">
  <div id="folio-scroll"><div id="folio-content"></div></div>
</div>
<div id="folio-head" style="display:none"></div>
<script>$js</script>
</body>
</html>''';
      });
    } catch (e) {
      widget.callbacks.onError?.call('Could not load the reader engine: $e');
    }
  }

  Future<void> _onLoadStop(InAppWebViewController controller) async {
    _shellLoaded = true;
    _shellReady = true;
    // A settings change during shell construction may have selected another
    // family; make sure the shell has the matching bytes before it is used.
    await _ensureFontFaces();
    if (!mounted) return;
    await controller.evaluateJavascript(
      source: 'folio.init(${jsonEncode(_settingsJson())});',
    );
    if (!mounted) return;
    widget.callbacks.onReady?.call();
    await _loadChapter(
      _requestedChapter < 0 ? 0 : _requestedChapter,
      progress: _restoreProgress,
      element: _restoreElement,
    );
  }

  Map<String, dynamic> _settingsJson() {
    final settings = widget.settings;
    // `_onLoadStop` can complete after the reader closed. Reading MediaQuery
    // here used to throw; `_brightness` was captured during the last build.
    final brightness = _brightness;
    return {
      'mode': settings.readerMode == ReaderMode.book ? 'book' : 'scroll',
      'fontSize': settings.fontSize,
      'lineHeight': settings.lineHeight,
      'fontFamily': readerFontStack(settings.fontFamily),
      'textAlign': settings.textAlign == TextAlign.justify
          ? 'justify'
          : settings.textAlign == TextAlign.center
          ? 'center'
          : settings.textAlign == TextAlign.right
          ? 'right'
          : 'left',
      'hyphenation': settings.hyphenation,
      'foreground':
          '#${readerTextColor(settings.readingMode, brightness).toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
      'pageAnimation': settings.pageAnimation,
      'tapZones': settings.tapZones,
      'tapZoneWidth': settings.tapZoneWidth,
      'swipe': settings.swipeToTurnPage,
      'tapToStartStop': settings.tapToStartStop,
      'scrollSpeed': settings.autoScrollSpeed,
      'autoStart': settings.scrollAutoStart,
    };
  }

  /// Swaps the embedded `@font-face` rules when the reader font changes.
  ///
  /// Bundled fonts are only ever injected for a family we ship, never for a
  /// name coming from the book.
  Future<void> _ensureFontFaces() async {
    final family = widget.settings.fontFamily;
    if (_fontFacesFamily == family) return;
    final controller = _controller;
    // Do not record the family yet: the shell may already have been built with
    // the previous one and has not loaded, so `_onLoadStop` must still inject
    // the new rules once it is ready.
    if (controller == null || !_shellReady) return;
    final css = await readerFontFaceCss(family);
    if (!mounted || widget.settings.fontFamily != family) return;
    _fontFacesFamily = family;
    await controller.evaluateJavascript(
      source: 'folio.setFontFaces(${jsonEncode(css)});',
    );
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    super.dispose();
  }

  Future<void> _applySettingsToPage() async {
    final controller = _controller;
    if (controller == null || !_shellReady) return;
    await controller.evaluateJavascript(
      source: 'folio.setSettings(${jsonEncode(_settingsJson())});',
    );
  }

  Future<ChapterContent?> _contentFor(int index) async {
    final chapter = widget.document.documentAt(index);
    if (chapter == null) return null;
    final cached = _chapterCache[index];
    if (cached != null) return cached;
    final content = await widget.document.loadChapterContent(chapter);
    _chapterCache[index] = content;
    while (_chapterCache.length > _cacheLimit) {
      _chapterCache.remove(_chapterCache.keys.first);
    }
    for (final missing in content.missingResources) {
      debugPrint('Folio: missing resource in ${chapter.href}: $missing');
    }
    return content;
  }

  Map<String, dynamic> _payload(
    int index,
    ChapterContent content, {
    double progress = 0,
    String? element,
  }) {
    return {
      'index': index,
      'html': content.bodyHtml,
      'head': content.webStyleHtml,
      'bodyClass': content.bodyClass,
      'bodyStyle': content.bodyStyle,
      'language': content.language,
      'hasPrev': widget.document.previousReadingIndex(index) != null,
      'hasNext': widget.document.nextReadingIndex(index) != null,
      'progress': progress,
      'element': element,
    };
  }

  Future<void> _loadChapter(
    int index, {
    double progress = 0,
    String? element,
  }) async {
    if (widget.document.documentAt(index) == null) return;
    if (_loadingChapter) {
      // A fast page-turn or volume press arrived while the previous chapter
      // was still loading; run it as soon as the current one is installed.
      _pendingChapter = index;
      _pendingProgress = progress;
      _pendingElement = element;
      return;
    }
    _loadingChapter = true;
    _requestedChapter = index;
    try {
      final ChapterContent? content;
      try {
        content = await _contentFor(index);
      } catch (e) {
        widget.callbacks.onError?.call('Could not load this chapter: $e');
        return;
      }
      if (content == null) return;
      _currentChapter = index;
      _lastProgress = progress;
      _lastElement = element;
      _restoreProgress = progress;
      _restoreElement = element;
      // `chapterReady` below is the authoritative notification: the chapter is
      // only usable once JavaScript has installed and restored it.
      if (!_shellReady || _controller == null) return;

      final payload = _payload(
        index,
        content,
        progress: progress,
        element: element,
      );
      final bodyHtml = content.bodyHtml;
      await _transfers.enqueue(
        (transferId) => _sendChapter(
          payload: payload,
          html: bodyHtml,
          transferId: transferId,
        ),
      );

      // Warm the next chapter without blocking the current one.
      final next = widget.document.nextReadingIndex(index);
      if (next != null) _background(_contentFor(next));
    } finally {
      _loadingChapter = false;
      final pending = _pendingChapter;
      if (pending != null) {
        _pendingChapter = null;
        final pendingProgress = _pendingProgress;
        final pendingElement = _pendingElement;
        _pendingProgress = 0;
        _pendingElement = null;
        _background(
          _loadChapter(
            pending,
            progress: pendingProgress,
            element: pendingElement,
          ),
        );
      }
    }
  }

  /// Sends a chapter in small pieces so the JavaScript bridge never has to
  /// carry a multi-megabyte script string. [transferId] tags every piece so
  /// the shell can drop chunks that belong to an older transfer.
  Future<void> _sendChapter({
    required Map<String, dynamic> payload,
    required String html,
    required int transferId,
  }) async {
    final controller = _controller;
    if (controller == null || !_shellReady) return;
    payload.remove('html');
    payload['transferId'] = transferId;
    await controller.evaluateJavascript(
      source: 'folio.startChapter(${jsonEncode(payload)});',
    );
    for (var start = 0; start < html.length; start += _maxScriptChunk) {
      final end = (start + _maxScriptChunk).clamp(0, html.length);
      await controller.evaluateJavascript(
        source:
            'folio.appendChapterHtml(${jsonEncode(html.substring(start, end))}, '
            '$transferId);',
      );
    }
    await controller.evaluateJavascript(
      source: 'folio.endChapter($transferId);',
    );
  }

  Future<void> _appendOrPrepend(int target, {required bool after}) async {
    final content = await _contentFor(target);
    if (content == null || _controller == null) return;
    final payload = _payload(target, content)
      ..['target'] = after ? 'append' : 'prepend';
    await _transfers.enqueue(
      (transferId) => _sendChapter(
        payload: payload,
        html: content.bodyHtml,
        transferId: transferId,
      ),
    );
  }

  Future<void> _handleLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      widget.callbacks.onError?.call('External links are not opened by Folio.');
      return;
    }
    final link = parseFileLink(href);
    if (link == null) return;
    final chapter = widget.document.allDocuments
        .where((c) => p.equals(c.path, link.path))
        .firstOrNull;
    if (chapter == null) {
      widget.callbacks.onError?.call('This link points outside the book.');
      return;
    }
    await loadChapter(chapter.index, progress: 0, element: link.fragment);
  }

  Future<void> _handleMessage(List<dynamic> arguments) async {
    if (arguments.isEmpty) return;
    final raw = arguments.first;
    if (raw is! Map) return;
    final message = Map<String, dynamic>.from(raw);
    switch (message['type']) {
      case 'progress':
        final event = progressEventFromMessage(message);
        if (event == null) break;
        _restoreProgress = event.progress;
        _restoreElement = event.element;
        _lastProgress = event.progress;
        _lastElement = event.element;
        // In scroll mode chapters are appended in place, so the visible
        // chapter is only known from the JS progress event. Keeping this in
        // sync lets the next `needChapter` request ask for the right chapter.
        _currentChapter = event.chapterIndex;
        widget.callbacks.onProgress?.call(event);
        break;
      case 'pages':
        widget.callbacks.onPage?.call(
          _num(message['page'])?.toInt() ?? 1,
          _num(message['pages'])?.toInt() ?? 1,
        );
        break;
      case 'atEnd':
        final next = widget.document.nextReadingIndex(_currentChapter);
        if (next == null) {
          widget.callbacks.onBoundary?.call(1);
        } else {
          await _loadChapter(next, progress: 0);
        }
        break;
      case 'atStart':
        final previous = widget.document.previousReadingIndex(_currentChapter);
        if (previous == null) {
          widget.callbacks.onBoundary?.call(-1);
        } else {
          await _loadChapter(previous, progress: 1);
        }
        break;
      case 'needChapter':
        // Use the chapter the scroll event actually came from. `_currentChapter`
        // can still point at the previous chapter while a load is in flight,
        // which appended the wrong neighbour.
        final direction = _num(message['direction'])?.toInt() == -1 ? -1 : 1;
        final from = _num(message['chapterIndex'])?.toInt() ?? _currentChapter;
        final target = direction > 0
            ? widget.document.nextReadingIndex(from)
            : widget.document.previousReadingIndex(from);
        if (target != null) {
          await _appendOrPrepend(target, after: direction > 0);
        }
        break;
      case 'link':
        final href = _string(message['href']);
        if (href != null && href.isNotEmpty) await _handleLink(href);
        break;
      case 'history':
        widget.callbacks.onHistoryChanged?.call(message['canGoBack'] == true);
        break;
      case 'restore':
        final index = _num(message['chapterIndex'])?.toInt();
        if (index == null) break;
        await _loadChapter(
          index,
          progress: _num(message['progress'])?.toDouble() ?? 0,
          element: _string(message['element']),
        );
        break;
      case 'toggleChrome':
      case 'tapZone':
        widget.callbacks.onToggleChrome?.call();
        break;
      case 'autoScroll':
        _autoScrollRunning = message['running'] == true;
        _autoScrollSpeed = _num(message['speed'])?.toInt() ?? _autoScrollSpeed;
        widget.callbacks.onAutoScroll?.call(
          _autoScrollRunning,
          _autoScrollSpeed,
        );
        break;
      case 'missingImage':
        debugPrint('Folio: image failed to load: ${message['src']}');
        break;
      case 'chapterReady':
        final index = _num(message['chapterIndex'])?.toInt();
        if (index != null) widget.callbacks.onChapterChanged?.call(index);
        break;
    }
  }

  Future<void> _goToProgress(double progress, String? element) async {
    final controller = _controller;
    if (controller == null || !_shellReady) return;
    await controller.evaluateJavascript(
      source:
          'folio.goToProgress(${jsonEncode(progress)}, ${jsonEncode(element)});',
    );
  }

  // ── Public API used by the reader screen and volume buttons ──────────────

  @override
  Future<void> nextPage() async {
    await _controller?.evaluateJavascript(source: 'folio.nextPage();');
  }

  @override
  Future<void> prevPage() async {
    await _controller?.evaluateJavascript(source: 'folio.prevPage();');
  }

  @override
  Future<void> goBack() async {
    await _controller?.evaluateJavascript(source: 'folio.goBack();');
  }

  @override
  Future<void> pushHistory() async {
    await _controller?.evaluateJavascript(source: 'folio.pushHistory();');
  }

  @override
  Future<void> loadChapter(
    int index, {
    double progress = 0,
    String? element,
  }) async {
    await _loadChapter(index, progress: progress, element: element);
  }

  @override
  Future<void> goToProgress(double progress, {String? element}) async {
    await _goToProgress(progress, element);
  }

  @override
  Future<void> toggleAutoScroll() async {
    await _controller?.evaluateJavascript(source: 'folio.toggleAutoScroll();');
  }

  @override
  Future<void> pauseAutoScroll() async {
    await _controller?.evaluateJavascript(source: 'folio.pauseAutoScroll();');
  }

  @override
  Future<void> startAutoScroll() async {
    await _controller?.evaluateJavascript(source: 'folio.startAutoScroll();');
  }

  @override
  Future<void> setAutoScrollSpeed(int speed) async {
    await _controller?.evaluateJavascript(
      source: 'folio.setAutoScrollSpeed($speed);',
    );
  }

  @override
  bool get autoScrollRunning => _autoScrollRunning;
  int get autoScrollSpeed => _autoScrollSpeed;
  @override
  int get currentChapter => _currentChapter;
  double get lastProgress => _lastProgress;

  @override
  Widget build(BuildContext context) {
    _brightness = MediaQuery.of(context).platformBrightness;
    final shell = _shellHtml;
    if (shell == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InAppWebView(
      key: ValueKey(_webViewGeneration),
      initialData: InAppWebViewInitialData(
        data: shell,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri(Uri.directory(widget.document.rootDir).toString()),
      ),
      initialSettings: readerWebViewSettings(inspectable: kDebugMode),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'folio',
          callback: (args) {
            // A malformed payload or a closed reader must never surface as an
            // unhandled async error.
            _background(_handleMessage(args));
            return null;
          },
        );
      },
      onLoadStop: (controller, _) => _onLoadStop(controller),
      onRenderProcessGone: (controller, detail) {
        if (!mounted) return;
        // The platform WebView cannot be reused after its renderer dies. Drop
        // the controller and rebuild with a new key; `_onLoadStop` then reloads
        // the chapter at the saved position.
        _shellReady = false;
        _shellLoaded = false;
        _controller = null;
        _loadingChapter = false;
        _pendingChapter = null;
        _pendingProgress = 0;
        _pendingElement = null;
        _restoreProgress = _lastProgress;
        _restoreElement = _lastElement;
        _requestedChapter = _currentChapter;
        widget.callbacks.onError?.call(
          detail.didCrash
              ? 'The reader engine crashed. Reloading the chapter…'
              : 'The reader engine was closed. Reloading the chapter…',
        );
        setState(() {
          _webViewGeneration++;
        });
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final allowed = readerAllowsNavigation(
          shellLoaded: _shellLoaded,
          url: action.request.url,
        );
        return allowed
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onReceivedError: (controller, request, error) {
        // The shell is the only document navigated by the WebView; chapter
        // images report their own failures through JS.
        if (request.isForMainFrame ?? true) {
          widget.callbacks.onError?.call(error.description);
        }
      },
    );
  }
}

/// Runs a background task and logs failures instead of letting them become
/// unhandled async errors.
void _background(Future<void> future) {
  unawaited(
    future.catchError((Object error, StackTrace stack) {
      debugPrint('Folio: background task failed: $error');
    }),
  );
}
