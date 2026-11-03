import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../epub/epub.dart';
import '../models/app_settings.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../reader/flutter_reader.dart';
import '../reader/reader_content_controller.dart';
import '../reader/webview_reader.dart';
import '../utils/theme_utils.dart';
import 'settings_screen.dart';

/// The reading screen. It owns the book chrome (title, TOC, progress) and
/// mounts either the Android WebView or the Flutter fallback.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ReaderContentController _content = ReaderContentController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  EpubDocument? _document;
  String? _error;
  String? _runtimeError;

  int _chapterIndex = 0;
  double _chapterProgress = 0;
  String? _element;
  int _page = 1;
  int _pages = 1;
  int _totalChapters = 0;

  bool _uiVisible = true;
  late final AnimationController _fade;
  late final Animation<double> _fadeAnimation;

  bool _autoRunning = false;
  int _autoSpeed = 40;

  Timer? _saveTimer;
  int _lastSavedMs = 0;

  bool get _usesWebView => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapterIndex = widget.book.lastChapterIndex;
    _chapterProgress = widget.book.lastProgress;
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(parent: _fade, curve: Curves.easeOut);
    _fade.value = 1;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _openBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _persistPosition(force: true);
    _fade.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _content.pauseAutoScroll();
    } else if (_uiVisible) {
      _fade.forward();
    }
  }

  Future<void> _openBook() async {
    try {
      final document = await EpubLoader().load(widget.book.path);
      if (!mounted) return;
      final index = _chapterIndex.clamp(0, document.chapters.length - 1);
      setState(() {
        _document = document;
        _chapterIndex = index;
        _totalChapters = document.chapters.length;
      });
    } on EpubException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'This book could not be opened: $e');
    }
  }

  // ── Chrome ────────────────────────────────────────────────────────────────

  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  void _openSettings() {
    _content.pauseAutoScroll();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _onProgress(ReaderProgressEvent event) {
    if (!mounted) return;
    setState(() {
      _chapterIndex = event.chapterIndex;
      _chapterProgress = event.progress;
      _element = event.element;
      _page = event.page;
      _pages = event.pages;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSavedMs < 500) {
      _saveTimer?.cancel();
      _saveTimer = Timer(
        Duration(milliseconds: 500 - (now - _lastSavedMs)),
        () => _persistPosition(),
      );
      return;
    }
    _persistPosition();
  }

  void _persistPosition({bool force = false}) {
    if (!force && _document == null) return;
    _lastSavedMs = DateTime.now().millisecondsSinceEpoch;
    ref
        .read(libraryProvider.notifier)
        .updateReadingProgress(
          widget.book.path,
          _chapterIndex,
          _chapterProgress,
        );
  }

  double get _overallProgress {
    final document = _document;
    if (document == null || document.totalChapterBytes == 0) {
      return 0;
    }
    var before = 0;
    for (var i = 0; i < _chapterIndex && i < document.chapters.length; i++) {
      before += document.chapters[i].byteSize;
    }
    final current = _chapterIndex < document.chapters.length
        ? document.chapters[_chapterIndex].byteSize
        : 0;
    return ((before + current * _chapterProgress) / document.totalChapterBytes)
        .clamp(0.0, 1.0);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final background = readerBackground(settings.readingMode, brightness);
    final foreground = readerTextColor(settings.readingMode, brightness);
    _autoSpeed = settings.autoScrollSpeed.round();

    if (_error != null) {
      return _buildError(settings, background, foreground);
    }

    final document = _document;
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness:
            ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccentColor,
          brightness:
              ThemeData.estimateBrightnessForColor(background) ==
                  Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: background,
        drawer: document == null ? null : _buildToc(document, foreground),
        body: document == null
            ? _buildLoading(background, foreground)
            : Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: settings.marginHorizontal,
                      ),
                      child: _buildContent(document, settings),
                    ),
                  ),
                  if (_runtimeError != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 72,
                      child: Material(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _runtimeError!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: IgnorePointer(
                        ignoring: !_uiVisible,
                        child: _buildTopBar(settings, foreground, background),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: IgnorePointer(
                        ignoring: !_uiVisible,
                        child: _buildBottomBar(
                          settings,
                          foreground,
                          background,
                        ),
                      ),
                    ),
                  ),
                  if (_autoRunning && !_uiVisible)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '▶ $_autoSpeed px/s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildContent(EpubDocument document, AppSettings settings) {
    final callbacks = ReaderCallbacks(
      onProgress: _onProgress,
      onPage: (page, pages) {
        if (!mounted) return;
        setState(() {
          _page = page;
          _pages = pages;
        });
      },
      onChapterChanged: (index) {
        if (!mounted) return;
        setState(() {
          _chapterIndex = index;
          _chapterProgress = 0;
          _page = 1;
        });
      },
      onToggleChrome: _toggleUI,
      onAutoScroll: (running, speed) {
        if (!mounted) return;
        setState(() {
          _autoRunning = running;
          _autoSpeed = speed;
        });
      },
      onBoundary: (direction) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                direction > 0 ? 'End of the book.' : 'Start of the book.',
              ),
              duration: const Duration(milliseconds: 900),
            ),
          );
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _runtimeError = message);
      },
    );

    if (_usesWebView) {
      return WebViewReader(
        document: document,
        settings: settings,
        callbacks: callbacks,
        controller: _content,
        initialChapter: _chapterIndex,
        initialProgress: _chapterProgress,
        initialElement: _element,
      );
    }
    return FlutterReader(
      document: document,
      settings: settings,
      callbacks: callbacks,
      controller: _content,
      initialChapter: _chapterIndex,
      initialProgress: _chapterProgress,
      initialElement: _element,
    );
  }

  Widget _buildLoading(Color background, Color foreground) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: kAccentColor,
              backgroundColor: foreground.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 14,
              color: foreground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(AppSettings settings, Color background, Color foreground) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        title: Text(
          widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 56,
                color: kAccentColor.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              Text(
                'This book cannot be opened',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to library'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar(
    AppSettings settings,
    Color foreground,
    Color background,
  ) {
    final document = _document;
    final title = document != null && _chapterIndex < document.chapters.length
        ? document.chapters[_chapterIndex].title
        : widget.book.title;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            background.withValues(alpha: 0.98),
            background.withValues(alpha: 0.0),
          ],
          stops: const [0.55, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: foreground),
              tooltip: 'Back to library',
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: foreground.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontSize: 11,
                      color: foreground.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (settings.readerMode == ReaderMode.scroll)
              IconButton(
                icon: Icon(
                  _autoRunning
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  color: foreground,
                ),
                tooltip: _autoRunning ? 'Pause scrolling' : 'Start scrolling',
                onPressed: () => _content.toggleAutoScroll(),
              ),
            IconButton(
              icon: Icon(Icons.format_list_bulleted_rounded, color: foreground),
              tooltip: 'Table of contents',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            IconButton(
              icon: Icon(Icons.settings_outlined, color: foreground),
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────────

  Widget _buildBottomBar(
    AppSettings settings,
    Color foreground,
    Color background,
  ) {
    final percent = (_overallProgress * 100).toStringAsFixed(0);
    final chapterLabel = _totalChapters > 0
        ? 'Ch. ${_chapterIndex + 1} / $_totalChapters'
        : '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            background.withValues(alpha: 0.98),
            background.withValues(alpha: 0.0),
          ],
          stops: const [0.5, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.showProgressBar)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _overallProgress,
                    minHeight: 2,
                    backgroundColor: foreground.withValues(alpha: 0.14),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      kAccentColor,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left_rounded, color: foreground),
                    tooltip: 'Previous page',
                    onPressed: () => _content.prevPage(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Page $_page of $_pages',
                          style: GoogleFonts.lato(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: foreground.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$chapterLabel   ·   $percent%',
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            color: foreground.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right_rounded, color: foreground),
                    tooltip: 'Next page',
                    onPressed: () => _content.nextPage(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── TOC drawer ───────────────────────────────────────────────────────────

  Widget _buildToc(EpubDocument document, Color foreground) {
    final entries = document.toc.isNotEmpty
        ? document.toc
        : document.chapters
              .map(
                (chapter) => EpubTocEntry(
                  title: chapter.title,
                  chapterIndex: chapter.index,
                ),
              )
              .toList();
    return Drawer(
      backgroundColor: readerBackground(
        ref.read(settingsNotifierProvider).readingMode,
        MediaQuery.of(context).platformBrightness,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contents',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                        Text(
                          document.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: foreground.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: foreground),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: foreground.withValues(alpha: 0.12)),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = entry.chapterIndex == _chapterIndex;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(
                      left: 20.0 + entry.level * 14,
                      right: 16,
                    ),
                    title: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: selected
                            ? kAccentColor
                            : foreground.withValues(alpha: 0.85),
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _content.loadChapter(
                        entry.chapterIndex,
                        progress: 0,
                        element: entry.fragment,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
