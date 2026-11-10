import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../epub/chapter_html.dart';
import '../epub/epub.dart';
import '../epub/href_resolver.dart';
import '../models/app_settings.dart';
import '../utils/theme_utils.dart';
import 'reader_content_controller.dart';
import 'webview_reader.dart' show ReaderCallbacks, ReaderProgressEvent;

/// Scroll-only fallback used on platforms without a WebView implementation
/// (Linux desktop). It keeps the same reader chrome and progress contract.
class FlutterReader extends ConsumerStatefulWidget {
  const FlutterReader({
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
  ConsumerState<FlutterReader> createState() => FlutterReaderState();
}

class FlutterReaderState extends ConsumerState<FlutterReader>
    with SingleTickerProviderStateMixin
    implements ReaderViewBackend {
  final ScrollController _scroll = ScrollController();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _autoRunning = false;
  int _autoSpeed = 40;
  double _autoPosition = 0;
  bool _restoring = false;
  bool _loading = false;
  int _chapterIndex = 0;
  int? _pendingChapter;
  double _pendingProgress = 0;
  String? _pendingElement;
  double _lastScrollPixels = 0;
  int _lastLoadFinishedAt = 0;

  /// The `Html` widget's anchor key. It is replaced on every chapter load so
  /// anchors from the previous chapter cannot be reused.
  GlobalKey _anchorKey = GlobalKey();

  final List<_ReaderHistoryEntry> _history = [];

  /// A chapter swap moves the scroll position programmatically. Ignore edge
  /// crossings for a moment afterwards so a restored end-of-chapter position
  /// does not immediately turn the page again (the "bounce forward" bug).
  static const _boundaryGuard = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
    _chapterIndex = widget.initialChapter;
    _autoSpeed = widget.settings.autoScrollSpeed.round();
    _ticker = createTicker(_onTick);
    _scroll.addListener(_onScroll);
    _load(
      widget.initialChapter,
      progress: widget.initialProgress,
      element: widget.initialElement,
    );
  }

  @override
  void didUpdateWidget(covariant FlutterReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.fontFamily != widget.settings.fontFamily ||
        oldWidget.settings.textAlign != widget.settings.textAlign ||
        oldWidget.settings.hyphenation != widget.settings.hyphenation ||
        oldWidget.settings.marginHorizontal !=
            widget.settings.marginHorizontal ||
        oldWidget.settings.readingMode != widget.settings.readingMode;
    if (!changed || !_scroll.hasClients) return;

    // A new text style changes the scroll extent. Remember the relative
    // position before the rebuild and restore it once the new layout exists.
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final progress = (_scroll.position.pixels / max).clamp(0.0, 1.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = (_scroll.position.maxScrollExtent * progress).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
      _autoPosition = target;
      _report(force: true);
    });
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(int index, {double progress = 0, String? element}) async {
    final chapter = widget.document.documentAt(index);
    if (chapter == null) return;
    if (_loading) {
      // Fast page turns, volume keys and scroll events must not be dropped:
      // keep the newest request and run it once the current chapter is in.
      _pendingChapter = index;
      _pendingProgress = progress;
      _pendingElement = element;
      return;
    }
    _loading = true;
    final ChapterContent content;
    try {
      content = await widget.document.loadChapterContent(chapter);
    } catch (e) {
      widget.callbacks.onError?.call('Could not load this chapter: $e');
      _finishLoad();
      return;
    }
    if (!mounted) {
      _loading = false;
      return;
    }
    for (final missing in content.missingResources) {
      debugPrint('Folio: missing resource in ${chapter.href}: $missing');
    }
    setState(() {
      _chapterIndex = index;
      _content = content;
      _anchorKey = GlobalKey();
    });
    widget.callbacks.onChapterChanged?.call(index);
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        _restoring = false;
        _finishLoad();
        return;
      }
      _scroll.jumpTo(0);
      if (!_jumpToAnchor(element) && progress > 0) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent * progress);
      }
      _lastScrollPixels = _scroll.position.pixels;
      _autoPosition = _scroll.position.pixels;
      _restoring = false;
      _finishLoad();
      _report(force: true);
      if (widget.settings.scrollAutoStart) startAutoScroll();
    });
  }

  /// Handles a tapped link from either flutter_html callback.
  ///
  /// flutter_html only calls [onLinkTap] when no [onAnchorTap] is supplied,
  /// and its anchor callback is invoked for every `<a href>`, not just
  /// `#fragment` links. Both entry points therefore route through here so
  /// encoded anchors are decoded and cross-chapter links still resolve.
  void _openLink(String? url) {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      widget.callbacks.onError?.call('External links are not opened by Folio.');
      return;
    }
    if (url.startsWith('#')) {
      final id = Uri.decodeComponent(url.substring(1));
      _pushHistory();
      _jumpToAnchor(id);
      _report(force: true);
      return;
    }
    // `Uri.toFilePath()` throws when the URI still carries a fragment, so
    // split the link the same way the WebView reader does.
    final link = parseFileLink(url);
    if (link == null) {
      widget.callbacks.onError?.call('This link is not opened by Folio.');
      return;
    }
    final chapter = widget.document.allDocuments
        .where((c) => p.equals(c.path, link.path))
        .firstOrNull;
    if (chapter == null) {
      widget.callbacks.onError?.call('This link points outside the book.');
      return;
    }
    _pushHistory();
    _load(chapter.index, element: link.fragment);
  }

  /// Scrolls to [id] inside the chapter that is currently rendered.
  bool _jumpToAnchor(String? id) {
    if (id == null || id.isEmpty) return false;
    final target = AnchorKey.forId(_anchorKey, id)?.currentContext;
    if (target == null) return false;
    Scrollable.ensureVisible(target, alignment: 0, duration: Duration.zero);
    return true;
  }

  /// Ends the current load and starts a request that arrived while it ran.
  void _finishLoad() {
    _loading = false;
    _lastLoadFinishedAt = DateTime.now().millisecondsSinceEpoch;
    final pending = _pendingChapter;
    if (pending == null) return;
    final progress = _pendingProgress;
    final element = _pendingElement;
    _pendingChapter = null;
    _pendingProgress = 0;
    _pendingElement = null;
    if (mounted) _load(pending, progress: progress, element: element);
  }

  ChapterContent? _content;

  void _onScroll() {
    if (_restoring || !_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;
    final direction = pixels > _lastScrollPixels
        ? 1
        : (pixels < _lastScrollPixels ? -1 : 0);
    _lastScrollPixels = pixels;
    _report();
    _maybeCrossChapter(direction);
  }

  /// Turns the page only after the reader has actually reached an edge.
  ///
  /// A chapter shorter than the viewport has `maxScrollExtent == 0`; it must
  /// stay on screen instead of immediately loading the next chapter.
  void _maybeCrossChapter(int direction) {
    if (direction == 0 || _loading || _restoring) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLoadFinishedAt < _boundaryGuard.inMilliseconds) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    if (direction > 0 && max > 0 && position.pixels >= max - 1) {
      final next = widget.document.nextReadingIndex(_chapterIndex);
      if (next != null) _load(next);
    } else if (direction < 0 && position.pixels <= 1) {
      final previous = widget.document.previousReadingIndex(_chapterIndex);
      if (previous != null) _load(previous, progress: 1);
    }
  }

  void _report({bool force = false}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    final progress = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    final viewport = position.viewportDimension;
    final pages = ((max + viewport) / viewport).ceil().clamp(1, 100000);
    final page = (position.pixels / viewport).floor() + 1;
    widget.callbacks.onPage?.call(page.clamp(1, pages), pages);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastReport < 120) return;
    _lastReport = now;
    widget.callbacks.onProgress?.call(
      ReaderProgressEvent(
        chapterIndex: _chapterIndex,
        progress: progress,
        page: page.clamp(1, pages),
        pages: pages,
      ),
    );
  }

  int _lastReport = 0;

  void _onTick(Duration elapsed) {
    if (!_autoRunning || !_scroll.hasClients) return;
    final delta = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    if (delta <= 0) return;
    final max = _scroll.position.maxScrollExtent;
    _autoPosition += _autoSpeed * delta;
    if (_autoPosition >= max) _autoPosition = max;
    _scroll.jumpTo(_autoPosition);
  }

  @override
  Future<void> loadChapter(
    int index, {
    double progress = 0,
    String? element,
  }) async {
    await _load(index, progress: progress, element: element);
  }

  @override
  Future<void> nextPage() async {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 1) {
      final next = widget.document.nextReadingIndex(_chapterIndex);
      if (next != null) {
        await _load(next);
      } else {
        widget.callbacks.onBoundary?.call(1);
      }
      return;
    }
    final viewport = position.viewportDimension;
    final target = (position.pixels + viewport * 0.92).clamp(
      0.0,
      position.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Future<void> prevPage() async {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= 1) {
      final previous = widget.document.previousReadingIndex(_chapterIndex);
      if (previous != null) {
        await _load(previous, progress: 1);
      } else {
        widget.callbacks.onBoundary?.call(-1);
      }
      return;
    }
    final viewport = position.viewportDimension;
    final target = (position.pixels - viewport * 0.92).clamp(
      0.0,
      position.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Future<void> goToProgress(double progress, {String? element}) async {
    if (!_scroll.hasClients) return;
    if (_jumpToAnchor(element)) return;
    _scroll.jumpTo(
      (_scroll.position.maxScrollExtent * progress.clamp(0.0, 1.0)),
    );
  }

  double get _currentProgress {
    if (!_scroll.hasClients) return 0;
    final max = _scroll.position.maxScrollExtent;
    return max <= 0 ? 0 : (_scroll.position.pixels / max).clamp(0.0, 1.0);
  }

  void _pushHistory() {
    if (_content == null) return;
    _history.add(
      _ReaderHistoryEntry(
        chapterIndex: _chapterIndex,
        progress: _currentProgress,
      ),
    );
    if (_history.length > 50) _history.removeAt(0);
    widget.callbacks.onHistoryChanged?.call(true);
  }

  @override
  Future<void> goBack() async {
    if (_history.isEmpty) return;
    final entry = _history.removeLast();
    widget.callbacks.onHistoryChanged?.call(_history.isNotEmpty);
    await _load(entry.chapterIndex, progress: entry.progress);
  }

  @override
  Future<void> toggleAutoScroll() async {
    if (_autoRunning) {
      await pauseAutoScroll();
    } else {
      await startAutoScroll();
    }
  }

  @override
  Future<void> startAutoScroll() async {
    if (_autoRunning || !_scroll.hasClients) return;
    _autoRunning = true;
    _autoPosition = _scroll.position.pixels;
    _lastTick = Duration.zero;
    _ticker.start();
    setState(() {});
  }

  @override
  Future<void> pauseAutoScroll() async {
    if (!_autoRunning) return;
    _autoRunning = false;
    _ticker.stop();
    setState(() {});
  }

  @override
  Future<void> setAutoScrollSpeed(int speed) async {
    _autoSpeed = speed.clamp(5, 300);
    setState(() {});
  }

  @override
  bool get autoScrollRunning => _autoRunning;

  @override
  int get currentChapter => _chapterIndex;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final content = _content;
    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final bodyStyle = readerBodyTextStyle(
      settings: widget.settings,
      systemBrightness: brightness,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: _onTapUp,
      onLongPress: () => widget.callbacks.onToggleChrome?.call(),
      onHorizontalDragEnd: (details) {
        if (!widget.settings.swipeToTurnPage ||
            widget.settings.readerMode != ReaderMode.book) {
          return;
        }
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          nextPage();
        } else if (velocity > 200) {
          prevPage();
        }
      },
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          // Leave room for the chrome: on Linux it floats over the content
          // instead of taking part in the Scaffold layout.
          padding: EdgeInsets.fromLTRB(
            widget.settings.marginHorizontal,
            56,
            widget.settings.marginHorizontal,
            80,
          ),
          child: Html(
            anchorKey: _anchorKey,
            data: '${content.bookStyleHtml}${content.bodyHtml}',
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                textAlign: widget.settings.textAlign,
                backgroundColor: Colors.transparent,
              ).merge(Style.fromTextStyle(bodyStyle)),
              'html': Style(backgroundColor: Colors.transparent),
              'p': Style(margin: Margins.only(bottom: 10)),
            },
            onLinkTap: (url, attributes, element) => _openLink(url),
            // flutter_html hands every `<a href>` tap to its anchor callback
            // when one is supplied, so both callbacks share [_openLink]. This
            // also replaces the library's anchor lookup, which would search
            // for the raw, still-encoded fragment (`note%201`).
            onAnchorTap: (url, attributes, element) => _openLink(url),
            extensions: [
              TagExtension(
                tagsToExtend: {'img'},
                builder: (imageContext) {
                  final src = imageContext.attributes['src'];
                  final uri = src == null ? null : Uri.tryParse(src);
                  if (uri == null || uri.scheme != 'file') {
                    return const SizedBox.shrink();
                  }
                  final file = File(uri.toFilePath());
                  if (!file.existsSync()) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapUp(TapUpDetails details) {
    final width = context.size?.width ?? 0;
    if (widget.settings.readerMode == ReaderMode.book &&
        widget.settings.tapZones &&
        width > 0) {
      final zone = (widget.settings.tapZoneWidth / 100).clamp(0.15, 0.45);
      final x = details.localPosition.dx / width;
      if (x < zone) {
        prevPage();
        return;
      }
      if (x > 1 - zone) {
        nextPage();
        return;
      }
      widget.callbacks.onToggleChrome?.call();
      return;
    }
    if (widget.settings.readerMode == ReaderMode.scroll &&
        widget.settings.tapToStartStop) {
      toggleAutoScroll();
      return;
    }
    widget.callbacks.onToggleChrome?.call();
  }
}

/// One position the Linux reader can return to after following a link.
class _ReaderHistoryEntry {
  const _ReaderHistoryEntry({
    required this.chapterIndex,
    required this.progress,
  });

  final int chapterIndex;
  final double progress;
}
