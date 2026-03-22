import 'package:hyphenatorx/hyphenatorx.dart';
import 'package:hyphenatorx/languages/language_de_1996.dart';
import 'package:hyphenatorx/languages/language_en_us.dart';
import 'package:hyphenatorx/languages/language_es.dart';
import 'package:hyphenatorx/languages/language_fr.dart';
import 'package:hyphenatorx/languages/language_it.dart';
import 'package:hyphenatorx/languages/language_pt.dart';

/// Cache for hyphenator instances by language code.
final Map<String, Hyphenator> _hyphenators = {};

/// Returns a cached [Hyphenator] instance for the given language code.
///
/// Uses regular hyphen character (-) for syllable marks.
/// Note: Flutter's text rendering engine doesn't properly display soft hyphens
/// (U+00AD) at line breaks, so we use regular hyphens which are always visible.
/// This matches traditional print typography where hyphenation marks are shown.
///
/// Supported language codes: en_us, it, de_1996, fr, es, pt
Hyphenator getHyphenator([String languageCode = 'en_us']) {
  if (_hyphenators.containsKey(languageCode)) {
    return _hyphenators[languageCode]!;
  }

  // Create hyphenator based on language code
  final hyphenator = switch (languageCode.toLowerCase()) {
    'it' => Hyphenator(Language_it(), symbol: '-'),
    'de_1996' || 'de' => Hyphenator(Language_de_1996(), symbol: '-'),
    'fr' => Hyphenator(Language_fr(), symbol: '-'),
    'es' => Hyphenator(Language_es(), symbol: '-'),
    'pt' => Hyphenator(Language_pt(), symbol: '-'),
    _ => Hyphenator(Language_en_us(), symbol: '-'),
  };

  _hyphenators[languageCode] = hyphenator;
  return hyphenator;
}

/// Checks if the hyphenator is ready for synchronous use.
bool isHyphenatorReady() => _hyphenators.isNotEmpty;

/// Processes HTML content and inserts soft hyphens into text nodes.
///
/// This function parses the HTML, finds text content within tags,
/// and hyphenates words while preserving HTML structure.
String hyphenateHtmlContent(String html, [String languageCode = 'en_us']) {
  final hyphenator = getHyphenator(languageCode);
  return _processHtmlNodes(html, hyphenator);
}

/// Processes HTML content synchronously (requires hyphenator to be loaded).
///
/// Returns the original HTML if hyphenator is not ready.
String hyphenateHtmlContentSync(String html, [String languageCode = 'en_us']) {
  if (!_hyphenators.containsKey(languageCode)) {
    return html;
  }
  return _processHtmlNodes(html, _hyphenators[languageCode]!);
}

/// Recursively processes HTML content to hyphenate text nodes.
String _processHtmlNodes(String html, Hyphenator hyphenator) {
  // Simple approach: find text between tags and hyphenate it
  // This regex matches text content (not tags)
  final buffer = StringBuffer();
  int pos = 0;

  while (pos < html.length) {
    // Find the next tag
    final tagStart = html.indexOf('<', pos);
    if (tagStart == -1) {
      // No more tags, hyphenate the rest
      final text = html.substring(pos);
      buffer.write(_hyphenateText(text, hyphenator));
      break;
    }

    // Add hyphenated text before the tag
    if (tagStart > pos) {
      final text = html.substring(pos, tagStart);
      buffer.write(_hyphenateText(text, hyphenator));
    }

    // Find the end of the tag
    final tagEnd = html.indexOf('>', tagStart);
    if (tagEnd == -1) {
      // Malformed HTML, add the rest as-is
      buffer.write(html.substring(tagStart));
      break;
    }

    // Add the tag as-is
    final tag = html.substring(tagStart, tagEnd + 1);
    buffer.write(tag);
    pos = tagEnd + 1;
  }

  return buffer.toString();
}

/// Hyphenates plain text, preserving whitespace and special characters.
///
/// The hyphenatorx library handles spaces internally, so we can pass
/// the entire text block directly.
String _hyphenateText(String text, Hyphenator hyphenator) {
  // Don't process if it contains HTML entities or looks like a tag
  if (text.contains('<') || text.contains('&')) {
    return text;
  }

  // Skip if no actual text content
  if (text.trim().isEmpty) {
    return text;
  }

  // hyphenatorx.hyphenateText handles spaces internally
  return hyphenator.hyphenateText(text);
}

