import 'package:flutter/material.dart';
import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_de_1996.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';
import 'package:hyphenatorx/languages/language_es.dart';
import 'package:hyphenatorx/languages/language_fr.dart';
import 'package:hyphenatorx/languages/language_it.dart';
import 'package:hyphenatorx/languages/language_pt.dart';

// ── Hyphenator cache ───────────────────────────────────────────────────────

final Map<String, Hyphenator> _hyphenators = {};

/// Returns a cached [Hyphenator] for [languageCode].
/// Uses U+00AD (soft hyphen) purely as an internal syllable-break marker;
/// it is never passed to Flutter's text engine directly.
Hyphenator getHyphenator([String languageCode = 'en_us']) {
  return _hyphenators.putIfAbsent(languageCode, () {
    return switch (languageCode.toLowerCase()) {
      'it'               => Hyphenator(Language_it(),       symbol: '\u00AD'),
      'de_1996' || 'de'  => Hyphenator(Language_de_1996(),  symbol: '\u00AD'),
      'fr'               => Hyphenator(Language_fr(),        symbol: '\u00AD'),
      'es'               => Hyphenator(Language_es(),        symbol: '\u00AD'),
      'pt'               => Hyphenator(Language_pt(),        symbol: '\u00AD'),
      _                  => Hyphenator(Language_en_us(),     symbol: '\u00AD'),
    };
  });
}

// ── TextPainter measurement helper ─────────────────────────────────────────

/// Measures the rendered width of [text] in a single line using [style].
double _measureWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  final w = painter.width;
  painter.dispose();
  return w;
}

// ── HyphenatedParagraph widget ─────────────────────────────────────────────

/// Renders [text] with a visible '-' inserted only where a line break
/// actually falls at a syllable boundary.
///
/// Algorithm (runs inside [LayoutBuilder], so the available width is known):
///   1. Tokenise the text into alternating word / whitespace tokens.
///   2. Walk tokens left-to-right, tracking [lineWidth] — how many pixels
///      are already consumed on the current visual line.
///   3. For each *word* token:
///        • If it fits on the remaining line space → append as-is.
///        • If it does NOT fit → ask the hyphenator for its syllable
///          segments, then greedily find the last segment boundary where
///          `lineWidth + width(prefix + '-')` still fits.
///          If such a boundary exists, emit `prefix-\u200Bsuffix`.
///          The U+200B (ZERO WIDTH SPACE) is a Unicode line-break
///          opportunity that Flutter's text engine honours: it wraps there
///          and renders nothing, so the '-' appears at the end of the line
///          and 'suffix' starts the next line.
///        • If no syllable fits with the hyphen → fall through to natural
///          word wrap (Flutter wraps at the preceding space).
///   4. Whitespace tokens are appended unchanged; a '\n' resets lineWidth.
class HyphenatedParagraph extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final EdgeInsets padding;
  final String languageCode;

  const HyphenatedParagraph({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.languageCode,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final displayed = _compute(
          text: trimmed,
          style: style,
          maxWidth: constraints.maxWidth - padding.horizontal,
          languageCode: languageCode,
        );
        return Padding(
          padding: padding,
          child: Text(displayed, style: style, textAlign: textAlign),
        );
      },
    );
  }

  // ── Core algorithm ─────────────────────────────────────────────────────

  static String _compute({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required String languageCode,
  }) {
    if (maxWidth <= 0) return text;

    final hyphenator = getHyphenator(languageCode);
    final result = StringBuffer();
    double lineWidth = 0;

    // Tokenise into runs of non-whitespace and runs of whitespace.
    final tokenRe = RegExp(r'\S+|\s+');

    for (final match in tokenRe.allMatches(text)) {
      final token = match.group(0)!;

      // ── Whitespace token ─────────────────────────────────────────────
      if (token.trim().isEmpty) {
        result.write(token);
        if (token.contains('\n')) {
          lineWidth = 0;
        } else {
          lineWidth += _measureWidth(token, style);
        }
        continue;
      }

      // ── Word token ───────────────────────────────────────────────────
      final wordWidth = _measureWidth(token, style);

      if (lineWidth + wordWidth <= maxWidth) {
        // Word fits on the current line — no hyphenation needed.
        result.write(token);
        lineWidth += wordWidth;
        continue;
      }

      // Word does NOT fit. Ask the hyphenator for syllable segments.
      final syllables = hyphenator.hyphenateText(token).split('\u00AD');

      if (syllables.length > 1) {
        // Find the rightmost break where prefix + '-' still fits.
        int bestBreak = -1;

        for (int i = 0; i < syllables.length - 1; i++) {
          final prefix = syllables.sublist(0, i + 1).join('');
          if (lineWidth + _measureWidth('$prefix-', style) <= maxWidth) {
            bestBreak = i;
          } else {
            // Syllables only grow longer; no point checking further.
            break;
          }
        }

        if (bestBreak >= 0) {
          final prefix = syllables.sublist(0, bestBreak + 1).join('');
          final suffix = syllables.sublist(bestBreak + 1).join('');
          // U+200B lets Flutter wrap here; '-' is visible at end of line.
          result.write('$prefix-\u200B$suffix');
          lineWidth = _measureWidth(suffix, style);
          continue;
        }
      }

      // Cannot hyphenate (or first syllable already too wide).
      // Let Flutter handle the natural word wrap at the preceding space.
      result.write(token);
      lineWidth = wordWidth;
    }

    return result.toString();
  }
}
