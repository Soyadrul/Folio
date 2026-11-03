import 'package:path/path.dart' as p;

/// The result of resolving a link found inside an EPUB.
///
/// Paths are relative to the extracted book root and use the real case of the
/// file on disk, because Android's file system is case-sensitive while many
/// EPUBs are not.
class ResolvedHref {
  const ResolvedHref({
    this.path,
    this.normalizedPath,
    this.fragment,
    this.isExternal = false,
    this.isMissing = false,
  });

  /// Actual file path (relative to the book root), or null when missing.
  final String? path;

  /// The normalised path that was looked up, even when it does not exist.
  final String? normalizedPath;

  /// The `#fragment` part of the link, without the hash.
  final String? fragment;

  /// True for http(s), mailto, data, protocol-relative and other URL schemes.
  final bool isExternal;

  /// True when a local path was requested but no file matched.
  final bool isMissing;
}

/// Resolves EPUB links against the document that contains them.
///
/// EPUB hrefs are relative to the containing file (a chapter, the OPF, the
/// NAV document), are URL-encoded, may contain `../`, `./`, a fragment or a
/// query, and often disagree with the archive in upper/lower case.
class HrefResolver {
  HrefResolver(Iterable<String> files) {
    for (final raw in files) {
      final actual = raw.replaceAll('\\', '/');
      final decoded = _decode(actual);
      _actualByLowerCase.putIfAbsent(decoded.toLowerCase(), () => actual);
      _actualByLowerCase.putIfAbsent(actual.toLowerCase(), () => actual);
    }
  }

  final Map<String, String> _actualByLowerCase = {};

  /// All real paths known to this resolver, relative to the book root.
  Iterable<String> get files => _actualByLowerCase.values.toSet();

  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

  ResolvedHref resolve(String href, {required String basePath}) {
    var raw = href.trim();
    if (raw.isEmpty) {
      return ResolvedHref(path: basePath, normalizedPath: basePath);
    }

    if (raw.startsWith('#')) {
      return ResolvedHref(
        path: basePath,
        normalizedPath: basePath,
        fragment: _decode(raw.substring(1)),
      );
    }

    if (raw.startsWith('//') || _scheme.hasMatch(raw)) {
      return const ResolvedHref(isExternal: true);
    }

    String? fragment;
    final hash = raw.indexOf('#');
    if (hash >= 0) {
      fragment = _decode(raw.substring(hash + 1));
      raw = raw.substring(0, hash);
    }
    final query = raw.indexOf('?');
    if (query >= 0) raw = raw.substring(0, query);

    raw = raw.replaceAll('\\', '/');
    final decoded = _decode(raw);

    String joined;
    if (decoded.startsWith('/')) {
      joined = decoded.substring(1);
    } else {
      joined = p.url.join(p.url.dirname(basePath), decoded);
    }
    var normalized = p.url.normalize(joined);
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.startsWith('/')) {
      return ResolvedHref(
        normalizedPath: normalized,
        fragment: fragment,
        isMissing: true,
      );
    }

    final actual = _actualByLowerCase[normalized.toLowerCase()];
    if (actual == null) {
      return ResolvedHref(
        normalizedPath: normalized,
        fragment: fragment,
        isMissing: true,
      );
    }
    return ResolvedHref(
      path: actual,
      normalizedPath: actual,
      fragment: fragment,
    );
  }

  /// Converts an absolute native path to a `file://` URI usable by a WebView.
  String fileUri(String absolutePath) => Uri.file(absolutePath).toString();

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }
}
