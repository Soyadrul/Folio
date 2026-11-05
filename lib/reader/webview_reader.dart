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
  });

  final void Function(ReaderProgressEvent event)? onProgress;
  final void Function(int page, int pages)? onPage;
  final void Function(int chapterIndex)? onChapterChanged;
  final VoidCallback? onToggleChrome;
  final void Function(bool running, int speed)? onAutoScroll;
  final void Function(int direction)? onBoundary;
  final VoidCallback? onReady;
  final void Function(String message)? onError;
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
  bool _autoScrollRunning = false;
  int _autoScrollSpeed = 40;

  final Map<int, ChapterContent> _chapterCache = {};
  static const _cacheLimit = 4;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
    _currentChapter = widget.initialChapter;
    _requestedChapter = widget.initialChapter;
    _lastProgress = widget.initialProgress;
    _lastElement = widget.initialElement;
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
    final modeChanged =
        oldWidget.settings.readerMode != widget.settings.readerMode;
    final typographyChanged =
        oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.fontFamily != widget.settings.fontFamily ||
        oldWidget.settings.textAlign != widget.settings.textAlign ||
        oldWidget.settings.hyphenation != widget.settings.hyphenation ||
        oldWidget.settings.marginHorizontal !=
            widget.settings.marginHorizontal ||
        oldWidget.settings.readingMode != widget.settings.readingMode;

    if (modeChanged || typographyChanged) {
      unawaited(_applySettingsAndRestore(modeChanged));
    } else if (oldWidget.settings.autoScrollSpeed !=
        widget.settings.autoScrollSpeed) {
      setAutoScrollSpeed(widget.settings.autoScrollSpeed.round());
    }
  }

  Future<void> _applySettingsAndRestore(bool modeChanged) async {
    await _ensureFontFaces();
    await _applySettingsToPage();
    if (modeChanged) {
      // Multi-column and scrolling layouts need a fresh chapter document.
      await _loadChapter(
        _currentChapter,
        progress: _lastProgress,
        element: _lastElement,
      );
    } else {
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
    await controller.evaluateJavascript(
      source: 'folio.init(${jsonEncode(_settingsJson())});',
    );
    widget.callbacks.onReady?.call();
    final chapter = int.tryParse(_requestedChapter.toString()) ?? 0;
    await _loadChapter(chapter, progress: _lastProgress, element: _lastElement);
  }

  Map<String, dynamic> _settingsJson() {
    final settings = widget.settings;
    final brightness = MediaQuery.of(context).platformBrightness;
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
    final css = await readerFontFaceCss(family);
    if (!mounted || widget.settings.fontFamily != family) return;
    _fontFacesFamily = family;
    final controller = _controller;
    if (controller == null || !_shellReady) return;
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
    if (index < 0 || index >= widget.document.chapters.length) return null;
    final cached = _chapterCache[index];
    if (cached != null) return cached;
    final chapter = widget.document.chapters[index];
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
      'head': content.headHtml,
      'bodyClass': content.bodyClass,
      'bodyStyle': content.bodyStyle,
      'language': content.language,
      'hasPrev': index > 0,
      'hasNext': index < widget.document.chapters.length - 1,
      'progress': progress,
      'element': element,
    };
  }

  Future<void> _loadChapter(
    int index, {
    double progress = 0,
    String? element,
  }) async {
    if (index < 0 || index >= widget.document.chapters.length) return;
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
      // `chapterReady` below is the authoritative notification: the chapter is
      // only usable once JavaScript has installed and restored it.
      if (!_shellReady || _controller == null) return;

      final payload = _payload(
        index,
        content,
        progress: progress,
        element: element,
      );
      await _controller!.evaluateJavascript(
        source: 'folio.setChapter(${jsonEncode(payload)});',
      );

      // Warm the next chapter without blocking the current one.
      unawaited(_contentFor(index + 1));
    } finally {
      _loadingChapter = false;
      final pending = _pendingChapter;
      if (pending != null) {
        _pendingChapter = null;
        final pendingProgress = _pendingProgress;
        final pendingElement = _pendingElement;
        _pendingProgress = 0;
        _pendingElement = null;
        unawaited(
          _loadChapter(
            pending,
            progress: pendingProgress,
            element: pendingElement,
          ),
        );
      }
    }
  }

  Future<void> _appendOrPrepend(int direction) async {
    final target = _currentChapter + direction;
    if (target < 0 || target >= widget.document.chapters.length) return;
    final content = await _contentFor(target);
    if (content == null || _controller == null) return;
    final payload = _payload(target, content);
    final source = direction > 0
        ? 'folio.appendChapter(${jsonEncode(payload)});'
        : 'folio.prependChapter(${jsonEncode(payload)});';
    await _controller!.evaluateJavascript(source: source);
  }

  Future<void> _handleLink(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      debugPrint('Folio: ignoring external link $href');
      return;
    }
    final link = parseFileLink(href);
    if (link == null) return;
    final chapter = widget.document.chapters
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
        final event = ReaderProgressEvent(
          chapterIndex: (message['chapterIndex'] as num?)?.toInt() ?? 0,
          progress: (message['progress'] as num?)?.toDouble() ?? 0,
          page: (message['page'] as num?)?.toInt() ?? 1,
          pages: (message['pages'] as num?)?.toInt() ?? 1,
          element: message['element'] as String?,
        );
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
          (message['page'] as num?)?.toInt() ?? 1,
          (message['pages'] as num?)?.toInt() ?? 1,
        );
        break;
      case 'atEnd':
        if (_currentChapter + 1 >= widget.document.chapters.length) {
          widget.callbacks.onBoundary?.call(1);
        } else {
          await _loadChapter(_currentChapter + 1, progress: 0);
        }
        break;
      case 'atStart':
        if (_currentChapter - 1 < 0) {
          widget.callbacks.onBoundary?.call(-1);
        } else {
          await _loadChapter(_currentChapter - 1, progress: 1);
        }
        break;
      case 'needChapter':
        await _appendOrPrepend(
          (message['direction'] as num?)?.toInt() == -1 ? -1 : 1,
        );
        break;
      case 'link':
        final href = message['href'] as String?;
        if (href != null) await _handleLink(href);
        break;
      case 'toggleChrome':
      case 'tapZone':
        widget.callbacks.onToggleChrome?.call();
        break;
      case 'autoScroll':
        _autoScrollRunning = message['running'] == true;
        _autoScrollSpeed =
            (message['speed'] as num?)?.toInt() ?? _autoScrollSpeed;
        widget.callbacks.onAutoScroll?.call(
          _autoScrollRunning,
          _autoScrollSpeed,
        );
        break;
      case 'missingImage':
        debugPrint('Folio: image failed to load: ${message['src']}');
        break;
      case 'chapterReady':
        final index = (message['chapterIndex'] as num?)?.toInt();
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
    final shell = _shellHtml;
    if (shell == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InAppWebView(
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
            // Handler callbacks may return a value to JS; ours are fire-and-forget.
            _handleMessage(args);
            return null;
          },
        );
      },
      onLoadStop: (controller, _) => _onLoadStop(controller),
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

/// Local `unawaited` so the reader does not depend on `dart:async` extensions.
void unawaited(Future<void> future) {
  future.catchError((Object error) {
    debugPrint('Folio: background task failed: $error');
  });
}
