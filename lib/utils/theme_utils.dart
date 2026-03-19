import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';

// ── Colour palettes ────────────────────────────────────────────────────────

/// Returns the background colour for a given [ReadingMode] and system
/// [brightness].
Color readerBackground(ReadingMode mode, Brightness systemBrightness) {
  switch (mode) {
    case ReadingMode.light:
      return const Color(0xFFFAF8F4);
    case ReadingMode.dark:
      return const Color(0xFF1C1C24);
    case ReadingMode.sepia:
      return const Color(0xFFF4ECD8);
    case ReadingMode.auto:
      return systemBrightness == Brightness.dark
          ? const Color(0xFF1C1C24)
          : const Color(0xFFFAF8F4);
  }
}

/// Returns the text colour for a given [ReadingMode] and system [brightness].
Color readerTextColor(ReadingMode mode, Brightness systemBrightness) {
  switch (mode) {
    case ReadingMode.light:
      return const Color(0xFF1A1A2E);
    case ReadingMode.dark:
      return const Color(0xFFE2DDD5);
    case ReadingMode.sepia:
      return const Color(0xFF3B2F20);
    case ReadingMode.auto:
      return systemBrightness == Brightness.dark
          ? const Color(0xFFE2DDD5)
          : const Color(0xFF1A1A2E);
  }
}

// ── Font helpers ───────────────────────────────────────────────────────────

/// All font families available for selection in the Settings screen.
const List<String> kAvailableFonts = [
  'Merriweather',
  'Lora',
  'Playfair Display',
  'Crimson Text',
  'EB Garamond',
  'PT Serif',
  'Source Serif 4',
  'Libre Baskerville',
  'Roboto',
  'Open Sans',
  'Lato',
  'Noto Sans',
];

/// Builds a [TextStyle] for the book body text using [GoogleFonts].
TextStyle readerBodyTextStyle({
  required AppSettings settings,
  required Brightness systemBrightness,
}) {
  final color = readerTextColor(settings.readingMode, systemBrightness);
  try {
    return GoogleFonts.getFont(
      settings.fontFamily,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: color,
    );
  } catch (_) {
    // If the font name is invalid fall back gracefully.
    return TextStyle(
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: color,
    );
  }
}

// ── App-wide theme ─────────────────────────────────────────────────────────

/// Warm amber accent used throughout the app.
const kAccentColor = Color(0xFFBD8C3C);
const kAccentColorLight = Color(0xFFD4A85A);

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccentColor,
      brightness: Brightness.light,
    ).copyWith(
      primary: kAccentColor,
      secondary: kAccentColorLight,
      surface: const Color(0xFFFAF8F4),
    ),
    scaffoldBackgroundColor: const Color(0xFFF2EFE8),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1A1A2E),
      foregroundColor: const Color(0xFFF2EFE8),
      elevation: 0,
      titleTextStyle: GoogleFonts.playfairDisplay(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFF2EFE8),
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFAF8F4),
      elevation: 2,
      shadowColor: const Color(0x22000000),
    ),
    textTheme: GoogleFonts.latoTextTheme().copyWith(
      headlineLarge: GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A1A2E),
      ),
      titleMedium: GoogleFonts.lato(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1A1A2E),
      ),
      bodyMedium: GoogleFonts.lato(
        fontSize: 14,
        color: const Color(0xFF4A4A5E),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccentColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: kAccentColorLight,
      secondary: kAccentColor,
      surface: const Color(0xFF13131A),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F16),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF13131A),
      foregroundColor: const Color(0xFFE2DDD5),
      elevation: 0,
      titleTextStyle: GoogleFonts.playfairDisplay(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFE2DDD5),
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1C28),
      elevation: 2,
      shadowColor: const Color(0x44000000),
    ),
    textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme).copyWith(
      headlineLarge: GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFE2DDD5),
      ),
      titleMedium: GoogleFonts.lato(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFE2DDD5),
      ),
      bodyMedium: GoogleFonts.lato(
        fontSize: 14,
        color: const Color(0xFFAAAAAC),
      ),
    ),
  );
}
