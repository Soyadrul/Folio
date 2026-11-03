import 'dart:convert';
import 'dart:io';

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

Future<EpubMetadata> readEpubMetadata(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw FormatException('Not a valid EPUB: $e');
  }

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
  final titleElement = opf.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'title')
      .firstOrNull;
  final creator = opf.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'creator')
      .firstOrNull;
  final title = titleElement?.innerText.trim() ?? '';
  final author = creator?.innerText.trim() ?? '';
  return EpubMetadata(
    title: title.isEmpty ? p.basenameWithoutExtension(filePath) : title,
    author: author.isEmpty ? 'Unknown Author' : author,
  );
}

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } catch (_) {
    return value;
  }
}
