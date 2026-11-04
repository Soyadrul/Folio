import 'dart:convert';
import 'package:flutter/material.dart';

/// The four display modes available in the reader.
enum ReadingMode { auto, light, dark, sepia }

/// How the text moves through the screen.
enum ReaderMode { book, scroll }

/// All user-configurable settings for the app.
///
/// Serialised to / from JSON and stored in [SharedPreferences].
class AppSettings {
  // ── Supported ranges (section 8 of the specification) ────────────────────
  static const double minFontSize = 10;
  static const double maxFontSize = 40;
  static const double minLineHeight = 1.0;
  static const double maxLineHeight = 2.2;
  static const double minMargin = 0;
  static const double maxMargin = 48;
  static const double minTapZoneWidth = 15;
  static const double maxTapZoneWidth = 45;
  static const double minScrollSpeed = 5;
  static const double maxScrollSpeed = 300;

  // ── Typography ────────────────────────────────────────────────────────────

  /// Font size in logical pixels for the book body text.
  final double fontSize;

  /// Font family name recognised by [GoogleFonts] (e.g. 'Merriweather').
  final String fontFamily;

  /// Line height multiplier (1.0 = tight, 2.2 = very airy).
  final double lineHeight;

  /// Text alignment for the book body text.
  final TextAlign textAlign;

  /// Whether hyphenation is enabled for the book text.
  final bool hyphenation;

  /// Language code for hyphenation (e.g., 'en_us', 'it', 'de_1996').
  /// Defaults to 'en_us' for English US.
  final String hyphenationLanguage;

  // ── Layout ────────────────────────────────────────────────────────────────

  /// Horizontal padding (left + right) applied around the book text.
  final double marginHorizontal;

  // ── Appearance ────────────────────────────────────────────────────────────

  /// Controls the background / text colour scheme for the reader.
  final ReadingMode readingMode;

  // ── Behaviour ─────────────────────────────────────────────────────────────

  /// Whether to keep the screen on while reading.
  final bool keepScreenOn;

  /// Whether to show the reading progress bar at the bottom of the reader.
  final bool showProgressBar;

  // ── Reading mode ──────────────────────────────────────────────────────────

  /// Book (paginated) or Scroll (continuous strip).
  final ReaderMode readerMode;

  // ── Book mode ─────────────────────────────────────────────────────────────

  /// Hardware volume keys turn pages while a book is open.
  final bool volumeButtonsTurnPages;

  /// Swap volume up/down for page back/forward.
  final bool invertVolumeButtons;

  /// Tap the left/right edge of the screen to turn pages.
  final bool tapZones;

  /// Width of each tap zone as a percentage of the screen (15–45).
  final double tapZoneWidth;

  /// Horizontal swipe turns pages.
  final bool swipeToTurnPage;

  /// Slide animation when a page turns.
  final bool pageAnimation;

  // ── Scroll mode ───────────────────────────────────────────────────────────

  /// Automatic scrolling speed in pixels per second (5–300).
  final double autoScrollSpeed;

  /// A tap starts and pauses automatic scrolling.
  final bool tapToStartStop;

  /// Volume keys change the automatic scrolling speed.
  final bool volumeButtonsChangeSpeed;

  /// Start automatic scrolling as soon as a book opens.
  final bool scrollAutoStart;

  const AppSettings({
    this.fontSize = 18.0,
    this.fontFamily = 'Merriweather',
    this.lineHeight = 1.5,
    this.textAlign = TextAlign.justify,
    this.hyphenation = true,
    this.hyphenationLanguage = 'en_us',
    this.marginHorizontal = 16.0,
    this.readingMode = ReadingMode.light,
    this.keepScreenOn = true,
    this.showProgressBar = true,
    this.readerMode = ReaderMode.book,
    this.volumeButtonsTurnPages = true,
    this.invertVolumeButtons = false,
    this.tapZones = true,
    this.tapZoneWidth = 30,
    this.swipeToTurnPage = true,
    this.pageAnimation = true,
    this.autoScrollSpeed = 40,
    this.tapToStartStop = true,
    this.volumeButtonsChangeSpeed = true,
    this.scrollAutoStart = false,
  });

  AppSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    TextAlign? textAlign,
    bool? hyphenation,
    String? hyphenationLanguage,
    double? marginHorizontal,
    ReadingMode? readingMode,
    bool? keepScreenOn,
    bool? showProgressBar,
    ReaderMode? readerMode,
    bool? volumeButtonsTurnPages,
    bool? invertVolumeButtons,
    bool? tapZones,
    double? tapZoneWidth,
    bool? swipeToTurnPage,
    bool? pageAnimation,
    double? autoScrollSpeed,
    bool? tapToStartStop,
    bool? volumeButtonsChangeSpeed,
    bool? scrollAutoStart,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlign: textAlign ?? this.textAlign,
      hyphenation: hyphenation ?? this.hyphenation,
      hyphenationLanguage: hyphenationLanguage ?? this.hyphenationLanguage,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      readingMode: readingMode ?? this.readingMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showProgressBar: showProgressBar ?? this.showProgressBar,
      readerMode: readerMode ?? this.readerMode,
      volumeButtonsTurnPages:
          volumeButtonsTurnPages ?? this.volumeButtonsTurnPages,
      invertVolumeButtons: invertVolumeButtons ?? this.invertVolumeButtons,
      tapZones: tapZones ?? this.tapZones,
      tapZoneWidth: tapZoneWidth ?? this.tapZoneWidth,
      swipeToTurnPage: swipeToTurnPage ?? this.swipeToTurnPage,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
      tapToStartStop: tapToStartStop ?? this.tapToStartStop,
      volumeButtonsChangeSpeed:
          volumeButtonsChangeSpeed ?? this.volumeButtonsChangeSpeed,
      scrollAutoStart: scrollAutoStart ?? this.scrollAutoStart,
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'lineHeight': lineHeight,
    'textAlign': textAlign.index,
    'hyphenation': hyphenation,
    'hyphenationLanguage': hyphenationLanguage,
    'marginHorizontal': marginHorizontal,
    'readingMode': readingMode.index,
    'keepScreenOn': keepScreenOn,
    'showProgressBar': showProgressBar,
    'readerMode': readerMode.index,
    'volumeButtonsTurnPages': volumeButtonsTurnPages,
    'invertVolumeButtons': invertVolumeButtons,
    'tapZones': tapZones,
    'tapZoneWidth': tapZoneWidth,
    'swipeToTurnPage': swipeToTurnPage,
    'pageAnimation': pageAnimation,
    'autoScrollSpeed': autoScrollSpeed,
    'tapToStartStop': tapToStartStop,
    'volumeButtonsChangeSpeed': volumeButtonsChangeSpeed,
    'scrollAutoStart': scrollAutoStart,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    fontSize: _number(json['fontSize'], 18.0, minFontSize, maxFontSize),
    fontFamily: json['fontFamily'] as String? ?? 'Merriweather',
    lineHeight: _number(json['lineHeight'], 1.5, minLineHeight, maxLineHeight),
    textAlign: _enumValue(
      TextAlign.values,
      json['textAlign'],
      TextAlign.justify,
    ),
    hyphenation: json['hyphenation'] as bool? ?? true,
    hyphenationLanguage: json['hyphenationLanguage'] as String? ?? 'en_us',
    marginHorizontal: _number(
      json['marginHorizontal'],
      16.0,
      minMargin,
      maxMargin,
    ),
    // `auto` is kept in the enum only so old saved indexes still decode; the
    // Settings page now offers just Light, Sepia and Dark.
    readingMode: _readingMode(json['readingMode']),
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    showProgressBar: json['showProgressBar'] as bool? ?? true,
    readerMode: _enumValue(
      ReaderMode.values,
      json['readerMode'],
      ReaderMode.book,
    ),
    volumeButtonsTurnPages: json['volumeButtonsTurnPages'] as bool? ?? true,
    invertVolumeButtons: json['invertVolumeButtons'] as bool? ?? false,
    tapZones: json['tapZones'] as bool? ?? true,
    tapZoneWidth: _number(
      json['tapZoneWidth'],
      30.0,
      minTapZoneWidth,
      maxTapZoneWidth,
    ),
    swipeToTurnPage: json['swipeToTurnPage'] as bool? ?? true,
    pageAnimation: json['pageAnimation'] as bool? ?? true,
    autoScrollSpeed: _number(
      json['autoScrollSpeed'],
      40.0,
      minScrollSpeed,
      maxScrollSpeed,
    ),
    tapToStartStop: json['tapToStartStop'] as bool? ?? true,
    volumeButtonsChangeSpeed: json['volumeButtonsChangeSpeed'] as bool? ?? true,
    scrollAutoStart: json['scrollAutoStart'] as bool? ?? false,
  );

  /// Reads a numeric setting, falling back to [fallback] for bad data and
  /// clamping old or hand-edited values to the supported range.
  static double _number(Object? raw, double fallback, double min, double max) {
    final value = raw is num ? raw.toDouble() : fallback;
    if (value.isNaN || value.isInfinite) return fallback;
    return value.clamp(min, max).toDouble();
  }

  static T _enumValue<T>(List<T> values, Object? raw, T fallback) {
    if (raw is int && raw >= 0 && raw < values.length) return values[raw];
    return fallback;
  }

  static ReadingMode _readingMode(Object? raw) {
    if (raw is int && raw >= 0 && raw < ReadingMode.values.length) {
      final mode = ReadingMode.values[raw];
      if (mode != ReadingMode.auto) return mode;
    }
    return ReadingMode.light;
  }

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
