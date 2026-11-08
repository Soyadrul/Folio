import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'href_resolver.dart';

/// Minimal metadata read for the library grid.
///
/// Unlike [EpubLoader] this does not extract anything: it only unzips the
/// container and package documents. Used by a background isolate during scan.
class EpubMetadata {
  const EpubMetadata({required this.title, required this.author});
  final String title;
  final String author;
}

/// Reads title and author from an already parsed `<package>` document.
///
/// The library grid and the reader both use this so they show the same title
/// and the same (comma-joined) author list. [fallbackTitle] is used when the
/// package has no usable title.
EpubMetadata readPackageMetadata(
  XmlElement package, {
  required String fallbackTitle,
}) {
  final metadata = _firstElement(package, 'metadata');
  final title = _textOf(_firstElement(metadata, 'title')).trim();
  final authors = _allElements(metadata, 'creator')
      .map((element) => element.innerText.trim())
      .where((author) => author.isNotEmpty)
      .toList();
  return EpubMetadata(
    title: title.isEmpty ? fallbackTitle : title,
    author: authors.isEmpty ? 'Unknown Author' : authors.join(', '),
  );
}

Future<EpubMetadata> readEpubMetadata(String filePath) async {
  // Read the ZIP directory and the two documents it points at instead of
  // loading the whole book into memory. A large EPUB can be hundreds of MB.
  final input = InputFileStream(filePath);
  final Archive archive;
  try {
    archive = ZipDecoder().decodeStream(input);
  } catch (e) {
    await input.close();
    throw FormatException('Not a valid EPUB: $e');
  }

  try {
    return _readMetadata(archive, filePath);
  } finally {
    await input.close();
  }
}

EpubMetadata _readMetadata(Archive archive, String filePath) {
  final entries = <String, ArchiveFile>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    entries[file.name.replaceAll('\\', '/')] = file;
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

  final container = entry('META-INF/container.xml');
  if (container == null) {
    throw const FormatException('META-INF/container.xml is missing');
  }
  final containerDoc = XmlDocument.parse(
    utf8.decode(container.readBytes() ?? const [], allowMalformed: true),
  );
  final rootfile = containerDoc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'rootfile')
      .firstOrNull;
  final fullPath = rootfile?.attributes
      .where((a) => a.name.local == 'full-path')
      .map((a) => a.value)
      .firstOrNull;
  if (fullPath == null) {
    throw const FormatException('container.xml has no rootfile');
  }

  final resolver = HrefResolver(entries.keys);
  final opfPath =
      resolver.resolve(fullPath, basePath: '.').path ??
      p.url.normalize(_decode(fullPath));
  final opfEntry = entry(opfPath);
  if (opfEntry == null) {
    throw const FormatException('The package document is missing');
  }
  final opf = XmlDocument.parse(
    utf8.decode(opfEntry.readBytes() ?? const [], allowMalformed: true),
  );
  final package = _firstElement(opf, 'package');
  if (package == null) {
    throw const FormatException('The package document has no <package>');
  }
  return readPackageMetadata(
    package,
    fallbackTitle: p.basenameWithoutExtension(filePath),
  );
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

String _textOf(XmlElement? element) => element?.innerText ?? '';

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
