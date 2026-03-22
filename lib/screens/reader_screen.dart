import 'dart:io';

import 'package:epub_view/epub_view.dart' hide Image;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/hyphenation_utils.dart';
import '../utils/theme_utils.dart';

/// Extension type for accessing EpubChapterViewValue properties.
/// EpubChapterViewValue is not publicly exported by epub_view, so we use
/// an extension type to provide type-safe access to its properties.
extension type EpubChapterViewValue._(dynamic value) {
  // ignore: avoid_dynamic_calls
  int get chapterNumber => value.chapterNumber as int;
  // ignore: avoid_dynamic_calls
  double get progress => value.progress as double;
}

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin {
  late EpubController _epubController;

  // ── UI overlay visibility ──────────────────────────────────────────────
  bool _uiVisible = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // ── Reading progress ───────────────────────────────────────────────────
  double _progress = 0.0;
  int _currentChapter = 0;
  int _totalChapters = 0;

  @override
  void initState() {
    super.initState();

    // Pre-initialize hyphenator for the selected language.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsNotifierProvider);
      getHyphenator(settings.hyphenationLanguage);
    });

    // Open the epub at the last saved chapter, or from the beginning.
    _epubController = EpubController(
      document: EpubDocument.openFile(File(widget.book.path)),
    );

    // Listen for book loaded event and restore chapter position.
    _epubController.isBookLoaded.addListener(() {
      if (_epubController.isBookLoaded.value) {
        // Wait for the scrollable list to be laid out.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final savedChapter = widget.book.lastChapterIndex;
          if (savedChapter > 0) {
            _epubController.scrollTo(index: savedChapter);
          }
        });
      }
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Enter immersive full-screen mode.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _epubController.dispose();
    _fadeController.dispose();
    // Restore system UI when leaving the reader.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── UI toggle ──────────────────────────────────────────────────────────

  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }
  }

  void _hideUI() {
    if (_uiVisible) {
      setState(() => _uiVisible = false);
      _fadeController.reverse();
    }
  }

  // ── Progress / chapter update ──────────────────────────────────────────

  void _onValueChanged(dynamic value) {
    if (value == null) return;

    // Wrap dynamic value in extension type for type-safe property access.
    final chapterValue = EpubChapterViewValue._(value);
    final chapterNumber = chapterValue.chapterNumber;
    final progress = chapterValue.progress;

    setState(() {
      _progress = progress.clamp(0.0, 1.0);
      _currentChapter = chapterNumber;
    });

    // Persist reading progress to the library state.
    ref.read(libraryProvider.notifier).updateReadingProgress(
          widget.book.path,
          chapterNumber,
          _progress,
        );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final bgColor = readerBackground(settings.readingMode, brightness);
    final textColor = readerTextColor(settings.readingMode, brightness);
    final isDarkBg = ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;

    return Theme(
      // Apply a local theme that matches the chosen reading mode.
      data: isDarkBg ? buildDarkTheme() : buildLightTheme(),
      child: Scaffold(
        backgroundColor: bgColor,
        // Tapping the side areas toggles the overlay; the TOC opens via
        // the app bar icon.
        drawer: _buildTocDrawer(textColor, bgColor),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleUI,
          child: Stack(
            children: [
              // ── EPUB content ────────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: settings.marginHorizontal,
                ),
                child: _buildEpubView(settings, brightness),
              ),

              // ── Top overlay (title + controls) ──────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildTopBar(textColor, bgColor, settings),
                ),
              ),

              // ── Bottom overlay (progress + chapter info) ────────────
              if (settings.showProgressBar)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: _buildBottomBar(textColor, bgColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── EPUB View ──────────────────────────────────────────────────────────

  Widget _buildEpubView(AppSettings settings, Brightness brightness) {
    final textStyle = readerBodyTextStyle(
      settings: settings,
      systemBrightness: brightness,
    );
    final textColor = readerTextColor(settings.readingMode, brightness);
    
    final shouldHyphenate =
      settings.hyphenation && settings.textAlign == TextAlign.justify;

    return EpubView(
      key: ValueKey(settings.toJsonString()),
      controller: _epubController,
      onDocumentLoaded: (document) {
        setState(() {
          _totalChapters = document.Chapters?.length ?? 0;
        });
      },
      onChapterChanged: _onValueChanged,
      builders: EpubViewBuilders<DefaultBuilderOptions>(
        options: DefaultBuilderOptions(
          textStyle: textStyle,
          paragraphPadding: EdgeInsets.zero,
        ),
        chapterDividerBuilder: (_) => Divider(
          height: 48,
          color: textColor.withValues(alpha: 0.15),
        ),
        chapterBuilder: (
          context,
          builders,
          document,
          chapters,
          paragraphs,
          index,
          chapterIndex,
          paragraphIndex,
          onExternalLinkPressed,
        ) {
          if (paragraphs.isEmpty) return Container();

          final options = builders.options as DefaultBuilderOptions;
          final element = paragraphs[index].element;

          // epub_view gives us a <section> container. Walk its children so we
          // can hyphenate each <p>, <h1>, etc. individually.
          const textTags = {
            'p', 'div', 'li', 'blockquote',
            'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
          };

          final paraStyle = readerBodyTextStyle(
            settings: settings,
            systemBrightness: brightness,
          );
          final edgePadding = options.paragraphPadding is EdgeInsets
              ? options.paragraphPadding as EdgeInsets
              : EdgeInsets.zero;

          // Build one widget per child element inside the section.
          final children = element.children.map<Widget>((child) {
            final tag = child.localName?.toLowerCase() ?? '';
            final text = child.text.trim();

            if (shouldHyphenate && textTags.contains(tag) && text.isNotEmpty) {
              return HyphenatedParagraph(
                text: text,
                style: paraStyle,
                textAlign: settings.textAlign,
                languageCode: settings.hyphenationLanguage,
                padding: edgePadding,
              );
            }

            // Non-text child or hyphenation off → flutter_html as before.
            return Html(
              data: child.outerHtml,
              onLinkTap: (href, _, __) => onExternalLinkPressed(href!),
              style: {
                'html': Style(
                  padding: HtmlPaddings.only(
                    top: edgePadding.top,
                    right: edgePadding.right,
                    bottom: edgePadding.bottom,
                    left: edgePadding.left,
                  ),
                  textAlign: settings.textAlign,
                ).merge(Style.fromTextStyle(options.textStyle)),
              },
              extensions: [
                TagExtension(
                  tagsToExtend: {'img'},
                  builder: (imageContext) {
                    final url =
                        imageContext.attributes['src']!.replaceAll('../', '');
                    final content =
                        document.Content!.Images![url]!.Content!;
                    return Image(
                      image: MemoryImage(Uint8List.fromList(content)),
                    );
                  },
                ),
              ],
            );
          }).toList();

          // If the section had no children at all, fall back to rendering the
          // whole element via flutter_html (handles edge-case EPUBs).
          if (children.isEmpty) {
            return Html(
              data: element.outerHtml,
              onLinkTap: (href, _, __) => onExternalLinkPressed(href!),
              style: {
                'html': Style(
                  textAlign: settings.textAlign,
                ).merge(Style.fromTextStyle(options.textStyle)),
              },
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chapterIndex >= 0 && paragraphIndex == 0)
                builders.chapterDividerBuilder(chapters[chapterIndex]),
              ...children,
            ],
          );
        },
      ),
    );
  }

  // ── Top overlay ────────────────────────────────────────────────────────

  Widget _buildTopBar(Color textColor, Color bgColor, AppSettings settings) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bgColor.withValues(alpha: 0.98),
            bgColor.withValues(alpha: 0.0),
          ],
          stops: const [0.6, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
            // Book title (truncated)
            Expanded(
              child: Text(
                widget.book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.85),
                ),
              ),
            ),
            // Table of contents
            Builder(builder: (ctx) {
              return IconButton(
                icon: Icon(Icons.format_list_bulleted_rounded,
                    color: textColor),
                tooltip: 'Table of contents',
                onPressed: () {
                  _hideUI();
                  Scaffold.of(ctx).openDrawer();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Bottom overlay (progress) ──────────────────────────────────────────

  Widget _buildBottomBar(Color textColor, Color bgColor) {
    final percent = (_progress * 100).toStringAsFixed(0);
    final chapterLabel = _totalChapters > 0
        ? 'Ch. ${_currentChapter + 1} / $_totalChapters'
        : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            bgColor.withValues(alpha: 0.98),
            bgColor.withValues(alpha: 0.0),
          ],
          stops: const [0.55, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thin progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  backgroundColor:
                      textColor.withValues(alpha: 0.15),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(kAccentColor),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    chapterLabel,
                    style: GoogleFonts.lato(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: GoogleFonts.lato(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── TOC Drawer ─────────────────────────────────────────────────────────

  Widget _buildTocDrawer(Color textColor, Color bgColor) {
    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
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
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: textColor.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: textColor.withValues(alpha: 0.12)),

            // Chapter list
            Expanded(
              child: EpubViewTableOfContents(controller: _epubController),
            ),
          ],
        ),
      ),
    );
  }
}
