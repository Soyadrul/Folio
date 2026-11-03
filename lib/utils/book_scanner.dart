import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../epub/epub_metadata.dart';
import '../models/book.dart';

/// Walks [folderPath] recursively and returns every .epub file it finds.
///
/// Parsing runs in a background isolate so a large library never blocks the
/// interface. A broken book only loses its metadata; the others still load.
Future<List<Book>> scanFolderForBooks(String folderPath) async {
  final dir = Directory(folderPath);
  if (!await dir.exists()) return [];

  final paths = await _collectEpubFiles(dir);
  if (paths.isEmpty) return [];

  List<Map<String, Object?>> metadata;
  try {
    metadata = await Isolate.run(() => _readAllMetadata(paths));
  } on Object {
    metadata = const [];
  }

  final byPath = <String, Map<String, Object?>>{
    for (final item in metadata)
      if (item['path'] is String) item['path']! as String: item,
  };

  final books = paths.map((path) {
    final item = byPath[path];
    return Book(
      path: path,
      title: (item?['title'] as String?) ?? p.basenameWithoutExtension(path),
      author: (item?['author'] as String?) ?? 'Unknown Author',
      lastModifiedMs: (item?['modified'] as int?) ?? 0,
    );
  }).toList();

  books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return books;
}

Future<List<Map<String, Object?>>> _readAllMetadata(List<String> paths) async {
  final result = <Map<String, Object?>>[];
  for (final path in paths) {
    var modified = 0;
    try {
      modified = (await File(path).lastModified()).millisecondsSinceEpoch;
    } on FileSystemException {
      modified = 0;
    }
    try {
      final metadata = await readEpubMetadata(path);
      result.add({
        'path': path,
        'title': metadata.title,
        'author': metadata.author,
        'modified': modified,
      });
    } catch (_) {
      result.add({
        'path': path,
        'title': p.basenameWithoutExtension(path),
        'author': 'Unknown Author',
        'modified': modified,
      });
    }
  }
  return result;
}

/// Recursively lists all *.epub files under [dir].
Future<List<String>> _collectEpubFiles(Directory dir) async {
  final results = <String>[];
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
        results.add(entity.path);
      }
    }
  } on FileSystemException {
    return results;
  }
  return results;
}
