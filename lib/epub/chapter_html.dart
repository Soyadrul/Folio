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
  });

  /// Inner HTML of the chapter's `<body>`.
  final String bodyHtml;

  /// Stylesheet links and `<style>` blocks found in the chapter `<head>`.
  final String headHtml;

  /// Local resources that could not be found (for diagnostics/logging).
  final List<String> missingResources;

  final String? bodyClass;
  final String? bodyStyle;
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

  String? rewrite(String? raw, {bool isLink = false}) {
    if (raw == null || raw.trim().isEmpty) return raw;
    final value = raw.trim();
    if (value.toLowerCase().startsWith('javascript:')) return null;

    final resolved = resolver.resolve(value, basePath: chapterPath);
    if (resolved.isExternal) return value;
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
      final rewritten = rewrite(parts.first);
      if (rewritten == null) continue;
      kept.add([rewritten, ...parts.skip(1)].join(' '));
    }
    if (kept.isEmpty) {
      element.attributes.remove('srcset');
    } else {
      element.attributes['srcset'] = kept.join(', ');
    }
  }

  final elements = document.querySelectorAll('*');
  for (final element in elements) {
    final tag = element.localName?.toLowerCase() ?? '';

    if (tag == 'script') {
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

    // Book scripts and inline handlers must not run inside the reader shell.
    for (final name in element.attributes.keys.toList()) {
      if (name.toString().toLowerCase().startsWith('on')) {
        element.attributes.remove(name);
      }
    }

    final isLink = tag == 'a' || tag == 'area' || tag == 'link';

    const urlAttributes = {'src', 'href', 'xlink:href', 'poster', 'data'};
    for (final key in element.attributes.keys.toList()) {
      final attribute = _attributeName(key);
      if (!urlAttributes.contains(attribute.toLowerCase())) continue;
      final rewritten = rewrite(element.attributes[key], isLink: isLink);
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
    final css = styleElement.text;
    if (css.contains('url(')) {
      styleElement.text = _rewriteCssUrls(
        css,
        chapterPath: chapterPath,
        bookRoot: bookRoot,
        resolver: resolver,
        missing: missing,
      );
    }
  }

  final headParts = <String>[];
  if (head != null) {
    for (final child in head.children.toList()) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (tag == 'base' || tag == 'script') continue;
      if (tag == 'meta') continue;
      if (tag == 'link') {
        final rel = (child.attributes['rel'] ?? '').toLowerCase();
        if (!rel.contains('stylesheet')) continue;
      }
      if (tag == 'style' || tag == 'link' || tag == 'title') {
        headParts.add(child.outerHtml);
      }
    }
  }

  return ChapterContent(
    bodyHtml: body.innerHtml,
    headHtml: headParts.join('\n'),
    missingResources: missing,
    bodyClass: body.attributes['class'],
    bodyStyle: body.attributes['style'],
  );
}

String _attributeName(Object key) {
  if (key is AttributeName) {
    return key.prefix == null ? key.name : '${key.prefix}:${key.name}';
  }
  return key.toString();
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
    if (raw.startsWith('data:') ||
        raw.startsWith('http:') ||
        raw.startsWith('https:') ||
        raw.startsWith('#')) {
      return match.group(0)!;
    }
    final resolved = resolver.resolve(raw, basePath: chapterPath);
    if (resolved.isExternal) return match.group(0)!;
    if (resolved.path == null) {
      missing.add(resolved.normalizedPath ?? raw);
      return 'url("")';
    }
    final uri = resolver.fileUri(p.join(bookRoot, resolved.path!));
    return 'url("$uri")';
  });
}
