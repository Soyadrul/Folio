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
    this.bodyClass,
    this.bodyStyle,
    this.language,
  });

  /// Inner HTML of the chapter's `<body>`.
  final String bodyHtml;

  /// Stylesheet links and `<style>` blocks found in the chapter `<head>`.
  final String headHtml;

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
  final document = html_parser.parse(rawHtml);
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
    for (final candidate in value.split(',')) {
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
      final rel = (element.attributes['rel'] ?? '')
          .toLowerCase()
          .split(RegExp(r'\s+'));
      if (!rel.contains('stylesheet')) {
        element.remove();
        continue;
      }
      final rewritten = rewrite(
        element.attributes['href'],
        isStylesheet: true,
      );
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
    }
  }

  final language = _chapterLanguage(document, body);

  return ChapterContent(
    bodyHtml: body.innerHtml,
    headHtml: headParts.join('\n'),
    missingResources: missing,
    bodyClass: body.attributes['class'],
    bodyStyle: body.attributes['style'],
    language: language,
  );
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
    final uri = resolver.fileUri(p.join(bookRoot, resolved.path!));
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
