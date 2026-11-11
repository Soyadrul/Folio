import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One bundled face of a selectable reader font.
class ReaderFontFace {
  const ReaderFontFace(
    this.asset, {
    required this.weight,
    this.style = 'normal',
    this.unicodeRange,
  });

  final String asset;

  /// A single weight ("400") or the range covered by a variable font
  /// ("400 700").
  final String weight;

  /// CSS `font-style`: `normal` or `italic`.
  final String style;

  /// CSS `unicode-range` for a subset face. Null means the face covers the
  /// whole font (the old behaviour).
  final String? unicodeRange;
}

/// Unicode ranges reported by Google Fonts for the two subsets in use.
const kLatinRange =
    'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, '
    'U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, '
    'U+2193, U+2212, U+2215, U+FEFF, U+FFFD';
const kLatinExtRange =
    'U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, '
    'U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, '
    'U+20A0-20AB, U+20AD-20C4, U+2113, U+2C60-2C7F, U+A720-A7FF';

/// The font files bundled under `assets/reader/fonts/`.
///
/// The WebView never sees the app's Flutter fonts; without these files every
/// choice in Settings collapsed to the same system serif/sans stack on
/// Android. Variable fonts (where the 400 and 700 files are identical) are
/// declared once with a weight range. Each family carries a latin and a
/// latin-ext subset, selected by `unicode-range`, so accented characters do
/// not force the browser to synthesise a face.
const Map<String, List<ReaderFontFace>> kReaderFontFaces = {
  'Merriweather': [
    ReaderFontFace(
      'assets/reader/fonts/merriweather-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/merriweather-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/merriweather-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/merriweather-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Lora': [
    ReaderFontFace(
      'assets/reader/fonts/lora-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lora-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lora-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lora-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Playfair Display': [
    ReaderFontFace(
      'assets/reader/fonts/playfair-display-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/playfair-display-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/playfair-display-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/playfair-display-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Crimson Text': [
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-normal-400.woff2',
      weight: '400',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-normal-700.woff2',
      weight: '700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-normal-400-latin-ext.woff2',
      weight: '400',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-normal-700-latin-ext.woff2',
      weight: '700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/crimson-text-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'EB Garamond': [
    ReaderFontFace(
      'assets/reader/fonts/eb-garamond-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/eb-garamond-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/eb-garamond-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/eb-garamond-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'PT Serif': [
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-normal-400.woff2',
      weight: '400',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-normal-700.woff2',
      weight: '700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-normal-400-latin-ext.woff2',
      weight: '400',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-normal-700-latin-ext.woff2',
      weight: '700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/pt-serif-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Source Serif 4': [
    ReaderFontFace(
      'assets/reader/fonts/source-serif-4-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/source-serif-4-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/source-serif-4-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/source-serif-4-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Libre Baskerville': [
    ReaderFontFace(
      'assets/reader/fonts/libre-baskerville-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/libre-baskerville-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/libre-baskerville-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/libre-baskerville-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Roboto': [
    ReaderFontFace(
      'assets/reader/fonts/roboto-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/roboto-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/roboto-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/roboto-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Open Sans': [
    ReaderFontFace(
      'assets/reader/fonts/open-sans-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/open-sans-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/open-sans-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/open-sans-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Lato': [
    ReaderFontFace(
      'assets/reader/fonts/lato-normal-400.woff2',
      weight: '400',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lato-normal-700.woff2',
      weight: '700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lato-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lato-normal-400-latin-ext.woff2',
      weight: '400',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lato-normal-700-latin-ext.woff2',
      weight: '700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/lato-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
  'Noto Sans': [
    ReaderFontFace(
      'assets/reader/fonts/noto-sans-normal-400.woff2',
      weight: '400 700',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/noto-sans-italic-400.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/noto-sans-normal-400-latin-ext.woff2',
      weight: '400 700',
      unicodeRange: kLatinExtRange,
    ),
    ReaderFontFace(
      'assets/reader/fonts/noto-sans-italic-400-latin-ext.woff2',
      weight: '400',
      style: 'italic',
      unicodeRange: kLatinExtRange,
    ),
  ],
};

const _serifFallback = 'Georgia, "Noto Serif", "Times New Roman", serif';
const _sansFallback = '"Helvetica Neue", Arial, sans-serif';
const _sansFamilies = {'Roboto', 'Open Sans', 'Lato', 'Noto Sans'};

/// CSS `font-family` value for a reader setting.
///
/// Known families are named exactly and followed by a matching generic stack;
/// unknown names never partially match a bundled font (so "Roboto Slab" does
/// not silently become "Roboto").
String readerFontStack(String family) {
  final fallback = _sansFamilies.contains(family)
      ? _sansFallback
      : _serifFallback;
  if (!kReaderFontFaces.containsKey(family)) return fallback;
  return '"$family", $fallback';
}

/// Builds inline `@font-face` rules for [family] with base64 data URIs.
///
/// The WebView is locked down to local book files and inline data, so the
/// bundled bytes are embedded rather than served from a second origin.
/// Returns an empty string when [family] has no bundled faces.
Future<String> readerFontFaceCss(String family) async {
  final faces = kReaderFontFaces[family];
  if (faces == null) return '';
  final escaped = family.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  final buffer = StringBuffer();
  for (final face in faces) {
    final data = await rootBundle.load(face.asset);
    final encoded = base64Encode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    buffer.writeln(
      "@font-face{font-family:'$escaped';"
      'src:url(data:font/woff2;base64,$encoded) format("woff2");'
      'font-weight:${face.weight};font-style:${face.style};'
      '${face.unicodeRange == null ? '' : 'unicode-range:${face.unicodeRange};'}'
      'font-display:swap;}',
    );
  }
  return buffer.toString();
}
