import 'dart:convert';
import 'package:flutter/material.dart';

/// The four display modes available in the reader.
enum ReadingMode { auto, light, dark, sepia }

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
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
        fontFamily: json['fontFamily'] as String? ?? 'Merriweather',
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.65,
        textAlign: TextAlign
            .values[json['textAlign'] as int? ?? TextAlign.justify.index],
        hyphenation: json['hyphenation'] as bool? ?? true,
        hyphenationLanguage: json['hyphenationLanguage'] as String? ?? 'en_us',
        marginHorizontal:
            (json['marginHorizontal'] as num?)?.toDouble() ?? 20.0,
        readingMode: ReadingMode
            .values[json['readingMode'] as int? ?? ReadingMode.auto.index],
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        showProgressBar: json['showProgressBar'] as bool? ?? true,
      );

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String s) =>
      AppSettings.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
