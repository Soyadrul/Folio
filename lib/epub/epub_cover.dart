import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'href_resolver.dart';

/// A cover image read straight from the EPUB archive.
class EpubCover {
  const EpubCover({required this.entryName, required this.bytes});

  /// Archive-relative path of the image, with its real spelling.
  final String entryName;

  /// Raw (still encoded) image bytes.
  final Uint8List bytes;
}

/// Reads the cover image of the EPUB at [filePath] without extracting the book.
///
/// The cover is located the same way [EpubLoader] does it: EPUB 3
/// `cover-image`, EPUB 2 `<meta name="cover">`, the guide's cover page, then
/// the first image of the first spine chapter. SVG covers are unwrapped to the
/// raster image they reference.
///
/// Returns null for a missing, damaged or cover-less book instead of throwing,
/// because a library card can always fall back to its placeholder.
Future<EpubCover?> readEpubCover(String filePath) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(await File(filePath).readAsBytes());
  } catch (_) {
    return null;
  }

  final entries = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = _safeEntryName(file.name);
    if (name == null) continue;
    entries[name] = file;
  }

  ArchiveFile? entry(String wanted) {
    final direct = entries[wanted];
    if (direct != null) return direct;
    final lower = wanted.toLowerCase();
    for (final candidate in entries.entries) {
      if (candidate.key.toLowerCase() == lower) return candidate.value;
    }
    // Some tools store percent-encoded zip names.
    final decoded = _decode(wanted);
    for (final candidate in entries.entries) {
      if (_decode(candidate.key).toLowerCase() == decoded.toLowerCase()) {
        return candidate.value;
      }
    }
    return null;
  }

  try {
    final containerEntry = entry('META-INF/container.xml');
    if (containerEntry == null) return null;
    final container = XmlDocument.parse(
      _text(containerEntry.readBytes() ?? const []),
    );
    final rootfile = container.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'rootfile')
        .firstOrNull;
    final fullPath = _attribute(rootfile, 'full-path');
    if (fullPath == null || fullPath.isEmpty) return null;

    final resolver = HrefResolver(entries.keys);
    final opfPath =
        resolver.resolve(fullPath, basePath: '.').path ??
        p.url.normalize(_decode(fullPath));
    final opfEntry = entry(opfPath);
    if (opfEntry == null) return null;
    final opf = XmlDocument.parse(_text(opfEntry.readBytes() ?? const []));

    final package = _firstElement(opf, 'package');
    if (package == null) return null;
    final metadata = _firstElement(package, 'metadata');
    final manifest = _firstElement(package, 'manifest');
    final spine = _firstElement(package, 'spine');
    if (manifest == null) return null;

    final manifestItems = <String, _ManifestItem>{};
    for (final item in _allElements(manifest, 'item')) {
      final id = _attribute(item, 'id');
      final href = _attribute(item, 'href');
      if (id == null || href == null || href.isEmpty) continue;
      manifestItems[id] = _ManifestItem(
        id: id,
        href: href,
        properties: (_attribute(item, 'properties') ?? '').toLowerCase(),
      );
    }

    String? resolveHref(String href) {
      final resolved = resolver.resolve(href, basePath: opfPath);
      return resolved.path;
    }

    String? coverPath;

    // 1. EPUB 3 cover-image manifest property.
    for (final item in manifestItems.values) {
      if (!item.properties.split(RegExp(r'\s+')).contains('cover-image')) {
        continue;
      }
      final path = resolveHref(item.href);
      if (path != null && _isImagePath(path)) {
        coverPath = path;
        break;
      }
    }

    // 2. EPUB 2 <meta name="cover" content="manifest-id">.
    if (coverPath == null) {
      for (final meta in _allElements(metadata, 'meta')) {
        if ((_attribute(meta, 'name') ?? '').toLowerCase() != 'cover') continue;
        final item = manifestItems[_attribute(meta, 'content')];
        if (item == null) continue;
        final path = resolveHref(item.href);
        if (path != null && _isImagePath(path)) {
          coverPath = path;
          break;
        }
      }
    }

    // 3. guide reference of type "cover" (image or cover chapter).
    if (coverPath == null) {
      for (final reference in _allElements(package, 'reference')) {
        if ((_attribute(reference, 'type') ?? '').toLowerCase() != 'cover') {
          continue;
        }
        final href = _attribute(reference, 'href');
        if (href == null) continue;
        final path = resolveHref(href);
        if (path == null) continue;
        if (_isImagePath(path)) {
          coverPath = path;
        } else {
          coverPath = _firstImageIn(path, entries, resolver);
        }
        if (coverPath != null) break;
      }
    }

    // 4. First image in the first spine chapter.
    if (coverPath == null && spine != null) {
      for (final itemref in _allElements(spine, 'itemref')) {
        final item = manifestItems[_attribute(itemref, 'idref')];
        if (item == null) continue;
        final path = resolveHref(item.href);
        if (path == null || _isImagePath(path)) continue;
        coverPath = _firstImageIn(path, entries, resolver);
        if (coverPath != null) break;
      }
    }

    if (coverPath == null) return null;
    if (p.extension(coverPath).toLowerCase() == '.svg') {
      coverPath = _rasterInsideSvg(coverPath, entries, resolver) ?? coverPath;
    }

    final coverEntry = entries[coverPath];
    if (coverEntry == null) return null;
    final bytes = coverEntry.readBytes();
    if (bytes == null || bytes.isEmpty) return null;
    return EpubCover(entryName: coverPath, bytes: bytes);
  } catch (_) {
    // A damaged container/package/cover must not stop the library scan.
    return null;
  }
}

String? _firstImageIn(
  String relPath,
  Map<String, ArchiveFile> entries,
  HrefResolver resolver,
) {
  final file = entries[relPath];
  if (file == null) return null;
  try {
    final document = html_parser.parse(_text(file.readBytes() ?? const []));
    for (final element in document.querySelectorAll('img, image, object')) {
      final elementName = element.localName?.toLowerCase();
      String? href;
      if (elementName == 'object') {
        href = element.attributes['data'];
      } else {
        href = element.attributes['src'] ?? element.attributes['href'];
        if (href == null) {
          for (final key in element.attributes.keys) {
            if (key.toString().toLowerCase().endsWith('href')) {
              href = element.attributes[key];
              break;
            }
          }
        }
      }
      if (href == null || href.isEmpty) continue;
      final resolved = resolver.resolve(href, basePath: relPath);
      final path = resolved.path;
      if (path != null && _isImagePath(path)) return path;
    }
  } catch (_) {
    // An unreadable cover chapter is not fatal.
  }
  return null;
}

String? _rasterInsideSvg(
  String svgPath,
  Map<String, ArchiveFile> entries,
  HrefResolver resolver,
) {
  final file = entries[svgPath];
  if (file == null) return null;
  try {
    final document = XmlDocument.parse(_text(file.readBytes() ?? const []));
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local.toLowerCase() != 'image') continue;
      String? href;
      for (final attribute in element.attributes) {
        if (attribute.name.local.toLowerCase() == 'href') {
          href = attribute.value;
          break;
        }
      }
      if (href == null || href.isEmpty) continue;
      final path = resolver.resolve(href, basePath: svgPath).path;
      if (path == null) continue;
      if (!_isImagePath(path) || p.extension(path).toLowerCase() == '.svg') {
        continue;
      }
      return path;
    }
  } catch (_) {
    // An unreadable SVG cover just falls back to the placeholder.
  }
  return null;
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.svg') ||
      lower.endsWith('.bmp');
}

String _text(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

String? _safeEntryName(String rawName) {
  var name = rawName.replaceAll('\\', '/');
  if (name.isEmpty) return null;
  if (name.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(name)) {
    return null;
  }
  name = p.url.normalize(name);
  if (name == '.' || name == '..' || name.startsWith('../')) return null;
  if (name.split('/').any((segment) => segment == '..')) return null;
  return name;
}

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}

XmlElement? _firstElement(XmlNode? root, String localName) {
  if (root == null) return null;
  for (final element in root.descendants.whereType<XmlElement>()) {
    if (element.name.local == localName) return element;
  }
  return null;
}

List<XmlElement> _allElements(XmlNode? root, String localName) {
  if (root == null) return const [];
  return root.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName)
      .toList();
}

String? _attribute(XmlElement? element, String localName) {
  if (element == null) return null;
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return null;
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.properties,
  });

  final String id;
  final String href;
  final String properties;
}
