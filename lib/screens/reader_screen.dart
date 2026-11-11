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
import '../reader/keep_screen_on.dart';
import '../reader/reader_content_controller.dart';
import '../reader/reading_position.dart';
import '../reader/volume_keys.dart';
import '../reader/webview_reader.dart';
import '../utils/theme_utils.dart';
import 'settings_screen.dart';

/// The reading screen. It owns the book chrome (title, TOC, progress) and
/// mounts either the Android WebView or the Flutter fallback.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book, this.loader});

  final Book book;

  /// Optional loader override; tests use it to keep the EPUB cache inside a
  /// temporary directory.
  final EpubLoader? loader;

  @override
  ConsumerState<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ReaderContentController _content = ReaderContentController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReadingPositionStore _positions = const ReadingPositionStore();

  EpubDocument? _document;
  String? _error;
  String? _runtimeError;
  late final EpubLoader _loader;

  /// Captured while the widget is alive so the last save in [dispose] does not
  /// have to read `ref`, which Riverpod forbids once unmounting starts.
  late final LibraryNotifier _library;
  late final SettingsNotifier _settingsNotifier;

  int _chapterIndex = 0;
  double _chapterProgress = 0;
  String? _element;
  int _page = 1;
  int _pages = 1;
  int _totalChapters = 0;
  bool _canGoBack = false;
  double _lastOverallProgress = 0;

  bool _uiVisible = true;
  late final AnimationController _fade;
  late final Animation<double> _fadeAnimation;

  bool _autoRunning = false;
  int _autoSpeed = 40;
  bool _volumeKeysEnabled = false;

  Timer? _saveTimer;
  Timer? _runtimeErrorTimer;
  int _lastSavedMs = 0;

  bool get _usesWebView => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loader = widget.loader ?? EpubLoader();
    _library = ref.read(libraryProvider.notifier);
    _settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    _chapterIndex = widget.book.lastChapterIndex;
    _chapterProgress = widget.book.lastProgress;
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(parent: _fade, curve: Curves.easeOut);
    _fade.value = 1;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    VolumeKeys.setHandler(_onVolumeKey);
    final settings = ref.read(settingsNotifierProvider);
    _syncVolumeKeys(settings);
    KeepScreenOn.setEnabled(settings.keepScreenOn);
    _openBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _runtimeErrorTimer?.cancel();
    // The process can be killed right after the reader closes; do not lose a
    // settings change made within the notifier's debounce window.
    unawaited(_settingsNotifier.flush());
    _persistPosition(force: true);
    VolumeKeys.setHandler(null);
    if (_volumeKeysEnabled) VolumeKeys.setEnabled(false);
    KeepScreenOn.setEnabled(false);
    _fade.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _content.pauseAutoScroll();
      // A settings change may still be waiting in the notifier's debounce
      // window. The process can be killed in the background, so flush it before
      // saving the position.
      unawaited(_settingsNotifier.flush());
      _persistPosition(force: true);
    } else if (_uiVisible) {
      _fade.forward();
    }
  }

  // ── Hardware volume keys ──────────────────────────────────────────────────

  void _syncVolumeKeys(AppSettings settings) {
    final wanted =
        _document != null &&
        (settings.readerMode == ReaderMode.book
            ? settings.volumeButtonsTurnPages
            : settings.volumeButtonsChangeSpeed);
    if (wanted == _volumeKeysEnabled) return;
    _volumeKeysEnabled = wanted;
    VolumeKeys.setEnabled(wanted);
  }

  void _onVolumeKey(VolumeKey key) {
    final settings = ref.read(settingsNotifierProvider);
    if (settings.readerMode == ReaderMode.book) {
      if (!settings.volumeButtonsTurnPages) return;
      // Volume up is "previous" by default; invert swaps the two.
      if (volumeKeyTurnsForward(
        key: key,
        invert: settings.invertVolumeButtons,
      )) {
        _content.nextPage();
      } else {
        _content.prevPage();
      }
      return;
    }

    if (!settings.volumeButtonsChangeSpeed) return;
    final nextSpeed = scrollSpeedAfterVolumeKey(settings.autoScrollSpeed, key);
    if (nextSpeed == settings.autoScrollSpeed) return;
    ref
        .read(settingsNotifierProvider.notifier)
        .update((s) => s.copyWith(autoScrollSpeed: nextSpeed));
    _content.setAutoScrollSpeed(nextSpeed.round());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Scroll speed ${nextSpeed.round()} px/s'),
          duration: const Duration(milliseconds: 700),
        ),
      );
  }

  Future<void> _openBook() async {
    try {
      final document = await _loader.load(widget.book.path);
      ReadingPosition? saved;
      try {
        saved = await _positions.load(widget.book.path);
      } catch (error) {
        debugPrint('Folio: could not read the saved position: $error');
      }
      if (!mounted) return;
      final chapter = saved?.chapterIndex ?? _chapterIndex;
      final progress = saved?.progress ?? _chapterProgress;
      final index = chapter.clamp(0, document.documentCount - 1);
      setState(() {
        _document = document;
        _chapterIndex = index;
        _chapterProgress = progress;
        _element = saved?.element;
        _totalChapters = document.chapters.length;
        // Following a footnote can leave the saved position on an auxiliary
        // page, which has no progress of its own. Keep the last whole-book
        // progress instead of resetting the library card to zero.
        _lastOverallProgress =
            _computeOverallProgress(document, index, progress) ??
            saved?.overallProgress ??
            0;
      });
      _syncVolumeKeys(ref.read(settingsNotifierProvider));
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

  Future<void> _openSettings() async {
    _content.pauseAutoScroll();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) _syncVolumeKeys(ref.read(settingsNotifierProvider));
  }

  void _onProgress(ReaderProgressEvent event) {
    if (!mounted) return;
    // The shell can emit a placeholder while its layout is empty; never let it
    // overwrite the chapter the reader restored.
    if (event.chapterIndex < 0) return;
    // A progress event means the last navigation worked, so any transient
    // error from the previous one is no longer relevant.
    _clearRuntimeError();
    final document = _document;
    if (document != null) {
      final overall = _computeOverallProgress(
        document,
        event.chapterIndex,
        event.progress,
      );
      if (overall != null) _lastOverallProgress = overall;
    }
    setState(() {
      _chapterIndex = event.chapterIndex;
      _chapterProgress = event.progress;
      _element = event.element;
      _page = event.page;
      _pages = event.pages;
    });
    _scheduleSave();
  }

  /// Shows a transient error message and clears it automatically.
  void _showRuntimeError(String message) {
    _runtimeErrorTimer?.cancel();
    setState(() => _runtimeError = message);
    _runtimeErrorTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_runtimeError == message) {
        setState(() => _runtimeError = null);
      }
    });
  }

  void _clearRuntimeError() {
    _runtimeErrorTimer?.cancel();
    _runtimeErrorTimer = null;
    if (_runtimeError == null) return;
    setState(() => _runtimeError = null);
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
    if (_document == null) return;
    final chapter = _chapterIndex < 0 ? 0 : _chapterIndex;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastSavedMs < 500) return;
    _lastSavedMs = now;
    final overall = _overallProgress;
    _library.updateReadingProgress(
      widget.book.path,
      chapter,
      _chapterProgress,
      overallProgress: overall,
    );
    unawaited(
      _positions
          .save(
            widget.book.path,
            ReadingPosition(
              chapterIndex: chapter,
              progress: _chapterProgress,
              element: _element,
              overallProgress: overall,
            ),
          )
          .catchError((Object error) {
            debugPrint('Folio: could not save the reading position: $error');
          }),
    );
  }

  double get _overallProgress => _lastOverallProgress;

  /// Book-wide progress for [index], or null when [index] is an auxiliary page
  /// that is not part of the reading flow (footnotes, colophon, ...).
  double? _computeOverallProgress(
    EpubDocument document,
    int index,
    double progress,
  ) {
    if (document.totalChapterBytes == 0) return null;
    final position = document.chapters.indexWhere((c) => c.index == index);
    if (position < 0) return null;
    var before = 0;
    for (var i = 0; i < position; i++) {
      before += document.chapters[i].byteSize;
    }
    final current = document.chapters[position].byteSize;
    return ((before + current * progress) / document.totalChapterBytes).clamp(
      0.0,
      1.0,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    ref.listen<AppSettings>(settingsNotifierProvider, (_, next) {
      _syncVolumeKeys(next);
      KeepScreenOn.setEnabled(next.keepScreenOn);
    });
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

  /// The callbacks handed to the mounted reader view.
  @visibleForTesting
  ReaderCallbacks createCallbacks() {
    return ReaderCallbacks(
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
          // The position belongs to the chapter that reported it. Never zero
          // it here: this callback also arrives after a chapter has restored
          // its saved position, and resetting would throw that away.
          if (_chapterIndex != index) _element = null;
          _chapterIndex = index;
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
        _showRuntimeError(message);
      },
      onHistoryChanged: (canGoBack) {
        if (!mounted || _canGoBack == canGoBack) return;
        setState(() => _canGoBack = canGoBack);
      },
    );
  }

  Widget _buildContent(EpubDocument document, AppSettings settings) {
    final callbacks = createCallbacks();

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
    final currentChapter = document?.documentAt(_chapterIndex);
    final title = currentChapter?.title ?? widget.book.title;
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
            if (_canGoBack)
              IconButton(
                icon: Icon(Icons.undo_rounded, color: foreground),
                tooltip: 'Back to previous location',
                onPressed: () => _content.goBack(),
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
    final position = _document?.readingOrderPosition(_chapterIndex);
    final chapterLabel = position != null && _totalChapters > 0
        ? 'Ch. $position / $_totalChapters'
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
    final selectedEntry = entries.indexWhere(
      (entry) => entry.chapterIndex == _chapterIndex,
    );
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
                  final selected = index == selectedEntry;
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
                      _content.openChapter(
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
