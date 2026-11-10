import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'href_resolver.dart';

/// One chapter prepared for the WebView shell.
class ChapterContent {
  const ChapterContent({
    required this.bodyHtml,
    required this.headHtml,
    required this.missingResources,
    this.webStyleHtml = '',
    this.bookStyleHtml = '',
    this.bodyClass,
    this.bodyStyle,
    this.language,
  });

  /// Inner HTML of the chapter's `<body>`.
  final String bodyHtml;

  /// Stylesheet links and `<style>` blocks found in the chapter `<head>`.
  final String headHtml;

  /// Book CSS prepared for the WebView shell.
  ///
  /// Linked stylesheets are inlined and every selector is scoped to this
  /// chapter's `<section>`, so a rule from one chapter cannot restyle another
  /// chapter or the reader chrome.
  final String webStyleHtml;

  /// Only the `<style>` elements of the chapter head.
  ///
  /// The Flutter fallback cannot load linked stylesheets, but `flutter_html`
  /// does apply inline `<style>` blocks when they are part of the rendered
  /// HTML.
  final String bookStyleHtml;

  /// Local resources that could not be found (for diagnostics/logging).
  final List<String> missingResources;

  final String? bodyClass;
  final String? bodyStyle;

  /// `lang`/`xml:lang` of the chapter, used for hyphenation.
  final String? language;
}

/// Rewrites a chapter so a WebView can load it from the extraction folder.
///
/// - every local `src`/`href` becomes an absolute, URL-encoded `file://` URI
///   (this also fixes wrong case and `../` in the original book);
/// - scripts and inline event handlers are removed;
/// - missing images lose their `src`, so the surrounding layout survives;
/// - the chapter `<body>` is separated from its `<head>` styles.
ChapterContent rewriteChapterHtml(
  String rawHtml, {
  required String chapterPath,
  required String bookRoot,
  required HrefResolver resolver,
}) {
  final document = html_parser.parse(_expandSelfClosingTags(rawHtml));
  final body = document.body ?? document.createElement('body');
  final head = document.head;

  final missing = <String>[];

  String? rewrite(
    String? raw, {
    bool isLink = false,
    bool isStylesheet = false,
    bool allowData = false,
  }) {
    if (raw == null || raw.trim().isEmpty) return raw;
    final value = raw.trim();
    final lower = value.toLowerCase();
    if (lower.startsWith('javascript:')) return null;
    if (lower.startsWith('data:')) {
      // Data images are safe and used by many books; data links are not.
      return allowData ? value : null;
    }
    if (value.startsWith('#')) {
      // Same-document references must stay fragments for every element:
      // SVG `<use href="#icon">`, `<textPath href="#p">` and footnotes alike.
      // Turning them into `file://...#id` made the SVG stop rendering.
      return value;
    }

    final resolved = resolver.resolve(value, basePath: chapterPath);
    if (resolved.isExternal) {
      // Keep ordinary web links so the reader can report them, but never let
      // a book load remote frames, images, media or stylesheets.
      return isLink && !isStylesheet ? value : null;
    }
    if (resolved.path == null) {
      if (!isLink) missing.add(resolved.normalizedPath ?? value);
      return null;
    }
    if (isLink &&
        !isStylesheet &&
        resolved.path == chapterPath &&
        resolved.fragment != null &&
        resolved.fragment!.isNotEmpty) {
      // The target is in this chapter; keep it as an in-page fragment so the
      // browser can scroll without loading the chapter again.
      return '#${Uri.encodeComponent(resolved.fragment!)}';
    }
    final absolute = p.join(bookRoot, resolved.path!);
    var uri = resolver.fileUri(absolute);
    if (resolved.fragment != null && resolved.fragment!.isNotEmpty) {
      uri = '$uri#${Uri.encodeComponent(resolved.fragment!)}';
    }
    return uri;
  }

  void rewriteSrcset(Element element) {
    final value = element.attributes['srcset'];
    if (value == null) return;
    final kept = <String>[];
    for (final candidate in splitSrcsetCandidates(value)) {
      final parts = candidate.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty || parts.first.isEmpty) continue;
      final rewritten = rewrite(parts.first, allowData: true);
      if (rewritten == null) continue;
      kept.add([rewritten, ...parts.skip(1)].join(' '));
    }
    if (kept.isEmpty) {
      element.attributes.remove('srcset');
    } else {
      element.attributes['srcset'] = kept.join(', ');
    }
  }

  // Elements that can execute code, navigate the WebView, or contact the
  // network. Book content is untrusted input, so they are removed outright
  // instead of being sanitised attribute by attribute.
  const blockedTags = {
    'script',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'applet',
    'meta',
    'base',
    'form',
  };
  const blockedAttributes = {'srcdoc', 'formaction', 'ping'};

  final elements = document.querySelectorAll('*');
  for (final element in elements) {
    final tag = element.localName?.toLowerCase() ?? '';

    if (blockedTags.contains(tag)) {
      element.remove();
      continue;
    }

    if (tag == 'svg') {
      // Without this, a book's `<image>` may be stretched when the SVG box is
      // scaled down to the page.
      var hasViewBox = false;
      var hasPreserveAspectRatio = false;
      for (final key in element.attributes.keys) {
        final name = _attributeName(key).toLowerCase();
        if (name == 'viewbox') hasViewBox = true;
        if (name == 'preserveaspectratio') hasPreserveAspectRatio = true;
      }
      if (hasViewBox && !hasPreserveAspectRatio) {
        element.attributes['preserveAspectRatio'] = 'xMidYMid meet';
      }
    }

    // Book scripts, inline handlers and form/ping targets must not run inside
    // the reader shell.
    for (final name in element.attributes.keys.toList()) {
      final lower = name.toString().toLowerCase();
      if (lower.startsWith('on') || blockedAttributes.contains(lower)) {
        element.attributes.remove(name);
      }
    }

    if (tag == 'link') {
      // A chapter may only bring in local stylesheets; preloads, icons and
      // remote styles are dropped.
      final rel = (element.attributes['rel'] ?? '').toLowerCase().split(
        RegExp(r'\s+'),
      );
      if (!rel.contains('stylesheet')) {
        element.remove();
        continue;
      }
      final rewritten = rewrite(element.attributes['href'], isStylesheet: true);
      if (rewritten == null) {
        element.remove();
      } else {
        element.attributes['href'] = rewritten;
      }
      continue;
    }

    final isLink = tag == 'a' || tag == 'area';
    final allowData = const {
      'img',
      'image',
      'source',
      'video',
      'audio',
      'track',
      'input',
    }.contains(tag);

    const urlAttributes = {
      'src',
      'href',
      'xlink:href',
      'poster',
      'data',
      'background',
    };
    for (final key in element.attributes.keys.toList()) {
      final attribute = _attributeName(key);
      if (!urlAttributes.contains(attribute.toLowerCase())) continue;
      final rewritten = rewrite(
        element.attributes[key],
        isLink: isLink,
        allowData: allowData,
      );
      if (rewritten == null) {
        element.attributes.remove(key);
        if (tag == 'img' || tag == 'image') {
          element.attributes['data-folio-missing-image'] = '';
        }
      } else {
        element.attributes[key] = rewritten;
      }
    }

    rewriteSrcset(element);

    final style = element.attributes['style'];
    if (style != null && style.contains('url(')) {
      element.attributes['style'] = _rewriteCssUrls(
        style,
        chapterPath: chapterPath,
        bookRoot: bookRoot,
        resolver: resolver,
        missing: missing,
      );
    }
  }

  for (final styleElement in document.querySelectorAll('style')) {
    final css = _stripRemoteImports(styleElement.text);
    styleElement.text = css.contains('url(')
        ? _rewriteCssUrls(
            css,
            chapterPath: chapterPath,
            bookRoot: bookRoot,
            resolver: resolver,
            missing: missing,
          )
        : css;
  }

  final headParts = <String>[];
  final styleParts = <String>[];
  if (head != null) {
    for (final child in head.children.toList()) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (tag == 'link') {
        final rel = (child.attributes['rel'] ?? '').toLowerCase();
        final href = child.attributes['href'];
        if (!rel.contains('stylesheet') ||
            href == null ||
            !href.startsWith('file:')) {
          continue;
        }
      }
      if (tag == 'style' || tag == 'link' || tag == 'title') {
        headParts.add(child.outerHtml);
      }
      if (tag == 'style') styleParts.add(child.outerHtml);
    }
  }

  final language = _chapterLanguage(document, body);

  return ChapterContent(
    bodyHtml: body.innerHtml,
    headHtml: headParts.join('\n'),
    bookStyleHtml: styleParts.join('\n'),
    missingResources: missing,
    bodyClass: body.attributes['class'],
    bodyStyle: body.attributes['style'],
    language: language,
  );
}

/// Splits a `srcset` attribute into candidates.
///
/// A comma inside the URL (every `data:` URI) is not a separator, so the URL
/// token is read until whitespace. One or more trailing commas mark a
/// descriptorless candidate (`a.png, b.png`); otherwise only the descriptor
/// that follows is terminated by a comma outside parentheses.
List<String> splitSrcsetCandidates(String value) {
  final candidates = <String>[];
  var index = 0;
  final length = value.length;
  while (index < length) {
    // Separators between candidates are whitespace and commas.
    while (index < length &&
        (value[index] == ',' || value[index].trim().isEmpty)) {
      index++;
    }
    if (index >= length) break;

    final urlStart = index;
    while (index < length && value[index].trim().isNotEmpty) {
      index++;
    }
    var url = value.substring(urlStart, index);
    var hasDescriptor = true;
    while (url.endsWith(',')) {
      url = url.substring(0, url.length - 1);
      hasDescriptor = false;
    }
    if (url.isEmpty) continue;
    if (!hasDescriptor) {
      candidates.add(url);
      continue;
    }

    // A descriptor runs to the next comma outside parentheses.
    while (index < length && value[index].trim().isEmpty) {
      index++;
    }
    final descriptorStart = index;
    var depth = 0;
    while (index < length) {
      final char = value[index];
      if (char == '(') {
        depth++;
      } else if (char == ')' && depth > 0) {
        depth--;
      } else if (char == ',' && depth == 0) {
        break;
      }
      index++;
    }
    final descriptor = value.substring(descriptorStart, index).trim();
    candidates.add(descriptor.isEmpty ? url : '$url $descriptor');
    if (index < length) index++; // Consume the comma.
  }
  return candidates;
}

/// HTML void elements. The HTML5 parser ignores the self-closing flag for
/// every other element, so `<script src="x.js"/>` starts raw-text mode and
/// swallows the rest of the chapter. Expanding all non-void tags fixes that;
/// expanding SVG/MathML elements is harmless in the HTML parser.
const _voidHtmlTags = {
  'area',
  'base',
  'basefont',
  'br',
  'col',
  'embed',
  'frame',
  'hr',
  'img',
  'input',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

final _selfClosingTagPattern = RegExp(
  r'''<([a-zA-Z][a-zA-Z0-9:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)\s*/>''',
);

String _expandSelfClosingTags(String html) {
  return html.replaceAllMapped(_selfClosingTagPattern, (match) {
    final name = match.group(1)!;
    final local = name.split(':').last.toLowerCase();
    if (_voidHtmlTags.contains(local)) return match.group(0)!;
    return '<$name${match.group(2)}></$name>';
  });
}

String _attributeName(Object key) {
  if (key is AttributeName) {
    return key.prefix == null ? key.name : '${key.prefix}:${key.name}';
  }
  return key.toString();
}

/// Reads `lang`/`xml:lang` from the document, falling back to the body.
String? _chapterLanguage(Document document, Element body) {
  for (final element in [document.documentElement, body]) {
    if (element == null) continue;
    for (final key in element.attributes.keys) {
      final name = _attributeName(key).toLowerCase();
      if (name != 'lang' && name != 'xml:lang') continue;
      final value = element.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  return null;
}

String _rewriteCssUrls(
  String css, {
  required String chapterPath,
  required String bookRoot,
  required HrefResolver resolver,
  required List<String> missing,
}) {
  final pattern = RegExp(
    r'''url\(\s*(?:'([^']*)'|"([^"]*)"|([^)'"\s]+))\s*\)''',
    caseSensitive: false,
  );
  return css.replaceAllMapped(pattern, (match) {
    final raw = match.group(1) ?? match.group(2) ?? match.group(3);
    if (raw == null || raw.isEmpty) return match.group(0)!;
    final lower = raw.toLowerCase();
    if (lower.startsWith('data:') || raw.startsWith('#')) {
      return match.group(0)!;
    }
    final resolved = resolver.resolve(raw, basePath: chapterPath);
    if (resolved.isExternal) {
      // No remote images, fonts or tracking pixels from book CSS.
      return 'url("")';
    }
    if (resolved.path == null) {
      missing.add(resolved.normalizedPath ?? raw);
      return 'url("")';
    }
    var uri = resolver.fileUri(p.join(bookRoot, resolved.path!));
    if (resolved.fragment != null && resolved.fragment!.isNotEmpty) {
      uri = '$uri#${Uri.encodeComponent(resolved.fragment!)}';
    }
    return 'url("$uri")';
  });
}

/// Removes `@import` rules that would fetch a remote stylesheet.
String _stripRemoteImports(String css) {
  final pattern = RegExp(
    r'''@import\s+(?:url\(\s*)?["']?(?:https?:)?//[^;]*;?''',
    caseSensitive: false,
  );
  return css.replaceAll(pattern, '');
}

/// Removes every `@import` rule.
///
/// Imported stylesheets cannot be scoped per chapter without inlining them, and
/// an unscoped import would leak rules into the reader chrome and other
/// chapters.
String _stripAllImports(String css) {
  // Match the whole rule, including the closing `)` of `url(...)` and any
  // media query that follows it. Leaving a stray `);` behind would make the
  // next rule's selector invalid, silently dropping real book styles.
  final pattern = RegExp(
    r'''@import\s+(?:url\([^)]*\)\s*|["'][^"']*["']\s*)?[^;]*;?''',
    caseSensitive: false,
  );
  return css.replaceAll(pattern, '');
}

/// Inlines linked stylesheets and scopes the whole book CSS to one chapter.
///
/// EPUB stylesheets routinely style `body`/`html` and use generic selectors
/// such as `p`. Inserted into the reader shell unchanged they would restyle the
/// chrome and, in scroll mode, every other loaded chapter.
Future<ChapterContent> prepareChapterStyles(
  ChapterContent content, {
  required int chapterIndex,
  required String chapterPath,
  required String bookRoot,
  required HrefResolver resolver,
}) async {
  final scope = '.folio-chapter[data-folio-index="$chapterIndex"]';
  final rawCss = <String>[];
  final scopedCss = <String>[];
  final head = html_parser.parseFragment(content.headHtml);

  void addCss(String css) {
    final cleaned = _stripAllImports(css.replaceFirst('\uFEFF', ''));
    if (cleaned.trim().isEmpty) return;
    rawCss.add(cleaned);
    scopedCss.add(scopeBookCss(cleaned, scope));
  }

  for (final element in head.querySelectorAll('style')) {
    addCss(element.text);
  }

  for (final link in head.querySelectorAll('link')) {
    final rel = (link.attributes['rel'] ?? '').toLowerCase();
    final href = link.attributes['href'];
    if (!rel.contains('stylesheet') ||
        href == null ||
        !href.startsWith('file:')) {
      continue;
    }
    final local = parseFileLink(href);
    if (local == null) continue;
    try {
      final bytes = await File(local.path).readAsBytes();
      final css = utf8.decode(bytes, allowMalformed: true);
      final relPath = p
          .relative(local.path, from: bookRoot)
          .replaceAll('\\', '/');
      final rewritten = _rewriteCssUrls(
        css,
        chapterPath: relPath,
        bookRoot: bookRoot,
        resolver: resolver,
        missing: content.missingResources,
      );
      addCss(rewritten);
    } catch (_) {
      // A missing or unreadable stylesheet only costs that stylesheet.
    }
  }

  return ChapterContent(
    bodyHtml: content.bodyHtml,
    headHtml: content.headHtml,
    webStyleHtml: scopedCss.map((css) => '<style>$css</style>').join('\n'),
    bookStyleHtml: rawCss.map((css) => '<style>$css</style>').join('\n'),
    missingResources: content.missingResources,
    bodyClass: content.bodyClass,
    bodyStyle: content.bodyStyle,
    language: content.language,
  );
}

/// Rewrites every selector in [css] so it only matches inside [scope].
String scopeBookCss(String css, String scope) {
  final output = StringBuffer();
  var index = 0;
  while (index < css.length) {
    if (css.startsWith('/*', index)) {
      final end = css.indexOf('*/', index + 2);
      final stop = end < 0 ? css.length : end + 2;
      output.write(css.substring(index, stop));
      index = stop;
      continue;
    }

    final brace = _findTopLevelChar(css, index, '{');
    final semicolon = _findTopLevelChar(css, index, ';');
    if (semicolon >= 0 && (brace < 0 || semicolon < brace)) {
      // Statements such as @charset or @namespace have no block.
      output.write(css.substring(index, semicolon + 1));
      index = semicolon + 1;
      continue;
    }
    if (brace < 0) {
      output.write(css.substring(index));
      break;
    }

    final prelude = css.substring(index, brace).trim();
    final close = _findMatchingBrace(css, brace);
    if (close < 0) {
      output.write(css.substring(index));
      break;
    }
    final body = css.substring(brace + 1, close);
    final lower = prelude.toLowerCase();
    if (lower.startsWith('@')) {
      final name = lower.split(RegExp(r'[\s({]')).first;
      const nested = {
        '@media',
        '@supports',
        '@document',
        '@layer',
        '@container',
        '@starting-style',
      };
      if (nested.contains(name)) {
        output.write('$prelude{${scopeBookCss(body, scope)}}');
      } else {
        // @font-face, @keyframes, @page, ... are not selectors.
        output.write('$prelude{$body}');
      }
    } else {
      output.write('${_scopeSelectorList(prelude, scope)}{$body}');
    }
    index = close + 1;
  }
  return output.toString();
}

String _scopeSelectorList(String selectors, String scope) {
  return _splitTopLevel(selectors, ',')
      .map((selector) => _scopeSelector(selector, scope))
      .where((selector) => selector.isNotEmpty)
      .join(', ');
}

String _scopeSelector(String raw, String scope) {
  final selector = raw.trim();
  if (selector.isEmpty) return '';
  if (selector.contains('.folio-chapter')) return selector;
  final replaced = _replaceRootSelector(selector, scope);
  if (replaced.startsWith(scope)) return replaced;
  if (replaced.startsWith('>') ||
      replaced.startsWith('+') ||
      replaced.startsWith('~')) {
    return '$scope $replaced';
  }
  return '$scope $replaced';
}

/// Turns `body`, `html`, `:root`, `html body p`, ... into `scope ...`.
///
/// A selector attached directly to the root (`body.note`) keeps that class on
/// the scope element; a descendant selector (`html body p`, `body > .note`)
/// becomes a descendant of the scope. Collapsing the two would make rules
/// like `body .note` style the chapter section itself instead of the note.
String _replaceRootSelector(String selector, String scope) {
  var rest = selector;
  var matched = false;
  var descendant = false;
  while (true) {
    final match = RegExp(
      r'^(?:html|body|:root)(?=$|[\s>+~.#:\[])',
      caseSensitive: false,
    ).firstMatch(rest);
    if (match == null) break;
    matched = true;
    var remainder = rest.substring(match.end);
    final separated = remainder.isNotEmpty && remainder[0].trim().isEmpty;
    remainder = remainder.trimLeft();
    if (remainder.startsWith('>') ||
        remainder.startsWith('+') ||
        remainder.startsWith('~')) {
      descendant = true;
      remainder = remainder.substring(1).trimLeft();
    } else if (separated) {
      descendant = true;
    }
    rest = remainder;
  }
  if (!matched) return selector;
  if (rest.isEmpty) return scope;
  if (!descendant &&
      (rest.startsWith('.') ||
          rest.startsWith('#') ||
          rest.startsWith('[') ||
          rest.startsWith(':'))) {
    return '$scope$rest';
  }
  return '$scope $rest';
}

int _findTopLevelChar(String css, int start, String wanted) {
  var parens = 0;
  var brackets = 0;
  var index = start;
  while (index < css.length) {
    final char = css[index];
    if (char == "'" || char == '"') {
      index = _skipString(css, index);
      continue;
    }
    if (css.startsWith('/*', index)) {
      final end = css.indexOf('*/', index + 2);
      index = end < 0 ? css.length : end + 2;
      continue;
    }
    if (char == '(') {
      parens++;
    } else if (char == ')') {
      if (parens > 0) parens--;
    } else if (char == '[') {
      brackets++;
    } else if (char == ']') {
      if (brackets > 0) brackets--;
    } else if (parens == 0 && brackets == 0 && char == wanted) {
      return index;
    }
    index++;
  }
  return -1;
}

int _findMatchingBrace(String css, int open) {
  var depth = 0;
  var index = open;
  while (index < css.length) {
    final char = css[index];
    if (char == "'" || char == '"') {
      index = _skipString(css, index);
      continue;
    }
    if (css.startsWith('/*', index)) {
      final end = css.indexOf('*/', index + 2);
      index = end < 0 ? css.length : end + 2;
      continue;
    }
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return index;
    }
    index++;
  }
  return -1;
}

int _skipString(String css, int start) {
  final quote = css[start];
  var index = start + 1;
  while (index < css.length) {
    if (css[index] == '\\') {
      index += 2;
      continue;
    }
    if (css[index] == quote) return index + 1;
    index++;
  }
  return css.length;
}

List<String> _splitTopLevel(String value, String separator) {
  final parts = <String>[];
  var start = 0;
  var parens = 0;
  var brackets = 0;
  var index = 0;
  while (index < value.length) {
    final char = value[index];
    if (char == "'" || char == '"') {
      index = _skipString(value, index);
      continue;
    }
    if (char == '(') {
      parens++;
    } else if (char == ')') {
      if (parens > 0) parens--;
    } else if (char == '[') {
      brackets++;
    } else if (char == ']') {
      if (brackets > 0) brackets--;
    } else if (parens == 0 && brackets == 0 && char == separator) {
      parts.add(value.substring(start, index));
      start = index + 1;
    }
    index++;
  }
  parts.add(value.substring(start));
  return parts;
}
