import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../epub/chapter_html.dart';
import '../epub/epub.dart';
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
    if (index < 0 || index >= widget.document.chapters.length) return;
    if (_loading) return;
    _loading = true;
    final chapter = widget.document.chapters[index];
    final ChapterContent content;
    try {
      content = await widget.document.loadChapterContent(chapter);
    } catch (e) {
      _loading = false;
      widget.callbacks.onError?.call('Could not load this chapter: $e');
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
    });
    widget.callbacks.onChapterChanged?.call(index);
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        _restoring = false;
        _loading = false;
        return;
      }
      _scroll.jumpTo(0);
      if (progress > 0) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent * progress);
      }
      if (element != null) {
        // The Flutter fallback cannot jump to an anchor by id; progress is the
        // fallback. The WebView path handles element-level restoration.
      }
      _restoring = false;
      _loading = false;
      _report(force: true);
      if (widget.settings.scrollAutoStart) startAutoScroll();
    });
    setState(() {
      _content = content;
    });
  }

  ChapterContent? _content;

  void _onScroll() {
    if (_restoring || !_scroll.hasClients) return;
    _report();
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
    final nextChapter = _chapterIndex + 1;
    if (_chapterIndex < widget.document.chapters.length - 1 &&
        _scroll.position.pixels >=
            _scroll.position.maxScrollExtent - viewport * 0.2) {
      _load(nextChapter);
    }
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
      if (_chapterIndex + 1 < widget.document.chapters.length) {
        await _load(_chapterIndex + 1);
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
      if (_chapterIndex > 0) {
        await _load(_chapterIndex - 1, progress: 1);
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
    _scroll.jumpTo(
      (_scroll.position.maxScrollExtent * progress.clamp(0.0, 1.0)),
    );
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

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.symmetric(
          horizontal: widget.settings.marginHorizontal,
          vertical: 8,
        ),
        child: Html(
          data: content.bodyHtml,
          style: {
            'body': Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              textAlign: widget.settings.textAlign,
            ).merge(Style.fromTextStyle(bodyStyle)),
            'p': Style(margin: Margins.only(bottom: 10)),
          },
          onLinkTap: (url, attributes, element) {
            if (url == null) return;
            final uri = Uri.tryParse(url);
            if (uri == null || uri.scheme != 'file') return;
            final chapter = widget.document.chapters
                .where((c) => p.equals(c.path, uri.toFilePath()))
                .firstOrNull;
            if (chapter != null) {
              _load(
                chapter.index,
                element: uri.fragment.isEmpty ? null : uri.fragment,
              );
            }
          },
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
    );
  }
}
