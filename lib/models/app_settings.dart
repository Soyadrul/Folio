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
  // ── Typography ────────────────────────────────────────────────────────────

  /// Font size in logical pixels for the book body text.
  final double fontSize;

  /// Font family name recognised by [GoogleFonts] (e.g. 'Merriweather').
  final String fontFamily;

  /// Line height multiplier (1.0 = tight, 2.0 = very airy).
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
    this.lineHeight = 1.65,
    this.textAlign = TextAlign.justify,
    this.hyphenation = true,
    this.hyphenationLanguage = 'en_us',
    this.marginHorizontal = 20.0,
    this.readingMode = ReadingMode.auto,
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
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
    fontFamily: json['fontFamily'] as String? ?? 'Merriweather',
    lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.65,
    textAlign:
        TextAlign.values[json['textAlign'] as int? ?? TextAlign.justify.index],
    hyphenation: json['hyphenation'] as bool? ?? true,
    hyphenationLanguage: json['hyphenationLanguage'] as String? ?? 'en_us',
    marginHorizontal: (json['marginHorizontal'] as num?)?.toDouble() ?? 20.0,
    readingMode: ReadingMode
        .values[json['readingMode'] as int? ?? ReadingMode.auto.index],
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    showProgressBar: json['showProgressBar'] as bool? ?? true,
    readerMode:
        ReaderMode.values[json['readerMode'] as int? ?? ReaderMode.book.index],
    volumeButtonsTurnPages: json['volumeButtonsTurnPages'] as bool? ?? true,
    invertVolumeButtons: json['invertVolumeButtons'] as bool? ?? false,
    tapZones: json['tapZones'] as bool? ?? true,
    tapZoneWidth: (json['tapZoneWidth'] as num?)?.toDouble() ?? 30.0,
    swipeToTurnPage: json['swipeToTurnPage'] as bool? ?? true,
    pageAnimation: json['pageAnimation'] as bool? ?? true,
    autoScrollSpeed: (json['autoScrollSpeed'] as num?)?.toDouble() ?? 40.0,
    tapToStartStop: json['tapToStartStop'] as bool? ?? true,
    volumeButtonsChangeSpeed: json['volumeButtonsChangeSpeed'] as bool? ?? true,
    scrollAutoStart: json['scrollAutoStart'] as bool? ?? false,
  );

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
