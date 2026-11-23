import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../epub/epub_metadata.dart';
import '../library/metadata_cache.dart';
import '../models/book.dart';
import 'library_text.dart';

/// Outcome of a library scan.
///
/// A scan keeps going when one folder cannot be read, so the skipped folders
/// are reported here instead of silently truncating the library.
class LibraryScan {
  const LibraryScan({
    this.books = const [],
    this.exists = true,
    this.unreadablePaths = const [],
    this.permissionDenied = false,
    this.cacheHits = 0,
    this.metadataFailed = false,
  });

  final List<Book> books;

  /// False when the root folder itself does not exist.
  final bool exists;

  /// Folders that could not be listed (permission errors, I/O errors, ...).
  final List<String> unreadablePaths;

  /// True when at least one unreadable folder failed with a permission error.
  final bool permissionDenied;

  /// Books whose metadata came from the cache instead of being re-read.
  final int cacheHits;

  /// True when the metadata isolate failed and the books were listed from
  /// their file names instead.
  final bool metadataFailed;

  int get skippedFolders => unreadablePaths.length;
}

/// Walks [folderPath] recursively and returns every .epub file it finds.
///
/// Parsing runs in background isolates so a large library never blocks the
/// interface. A broken book only loses its metadata; the others still load.
/// A folder that cannot be listed is skipped and reported in
/// [LibraryScan.unreadablePaths] rather than aborting the whole scan.
///
/// When [cachePath] is given, metadata is cached in that JSON file and only
/// files whose size or modification time changed are read again.
Future<LibraryScan> scanFolderForBooks(
  String folderPath, {
  String? cachePath,
  @visibleForTesting
  Future<List<Map<String, Object?>>> Function()? metadataLoader,
}) async {
  final dir = Directory(folderPath);
  if (!await dir.exists()) return const LibraryScan(exists: false);

  final collected = await _collectEpubFiles(dir);
  if (collected.paths.isEmpty) {
    return LibraryScan(
      unreadablePaths: collected.unreadablePaths,
      permissionDenied: collected.permissionDenied,
    );
  }

  List<Map<String, Object?>> metadata;
  var metadataFailed = false;
  try {
    final loader =
        metadataLoader ??
        () => Isolate.run(
          () => _readAllMetadata(collected.paths, cachePath, folderPath),
        );
    metadata = await loader();
  } on Object catch (error, stackTrace) {
    // One bad book or an out-of-memory isolate must not hide the whole
    // library behind a blank grid. List every file and tell the user why the
    // titles are missing.
    debugPrint('Folio: metadata scan failed: $error\n$stackTrace');
    metadata = const [];
    metadataFailed = true;
  }

  final byPath = <String, Map<String, Object?>>{
    for (final item in metadata)
      if (item['path'] is String) item['path']! as String: item,
  };

  // Without metadata the isolate never stats the files, but the library still
  // needs a modification time so a changed book refreshes its card later.
  final fallbackModified = <String, int>{};
  if (metadataFailed) {
    for (final path in collected.paths) {
      try {
        fallbackModified[path] = (await File(
          path,
        ).stat()).modified.millisecondsSinceEpoch;
      } on FileSystemException {
        // The card will show 0; the next scan can try again.
      }
    }
  }

  final books = collected.paths.map((path) {
    final item = byPath[path];
    return Book(
      path: path,
      title: (item?['title'] as String?) ?? p.basenameWithoutExtension(path),
      author: (item?['author'] as String?) ?? 'Unknown Author',
      lastModifiedMs:
          (item?['modified'] as int?) ?? fallbackModified[path] ?? 0,
    );
  }).toList();

  books.sort(
    (a, b) => foldDiacritics(a.title).compareTo(foldDiacritics(b.title)),
  );
  return LibraryScan(
    books: books,
    unreadablePaths: collected.unreadablePaths,
    permissionDenied: collected.permissionDenied,
    cacheHits: metadata.where((item) => item['cached'] == true).length,
    metadataFailed: metadataFailed,
  );
}

/// Reads metadata for [paths] in a background isolate.
///
/// Unchanged files are served from [cachePath]; the rest are split across a
/// few worker isolates so a large library is read in parallel and only the ZIP
/// directory plus the package document are opened.
Future<List<Map<String, Object?>>> _readAllMetadata(
  List<String> paths,
  String? cachePath,
  String folderPath,
) async {
  final cache = await MetadataCache.load(cachePath);
  final results = <Map<String, Object?>>[];
  final pending = <Map<String, Object?>>[];

  for (final path in paths) {
    FileStat? stat;
    try {
      stat = await File(path).stat();
    } on FileSystemException {
      stat = null;
    }
    if (stat == null) {
      results.add({
        'path': path,
        'title': p.basenameWithoutExtension(path),
        'author': 'Unknown Author',
        'modified': 0,
        'cached': false,
      });
      continue;
    }
    final modified = stat.modified.millisecondsSinceEpoch;
    final hit = cache.lookup(path, size: stat.size, modified: modified);
    if (hit != null) {
      results.add({
        'path': path,
        'title': hit['title'],
        'author': hit['author'],
        'modified': modified,
        'cached': true,
      });
    } else {
      pending.add({'path': path, 'size': stat.size, 'modified': modified});
    }
  }

  final chunks = _chunk(pending, _workerCount(pending.length));
  final read = await Future.wait(
    chunks.map((chunk) => Isolate.run(() => _readMetadataChunk(chunk))),
  );

  for (final chunk in read) {
    for (final item in chunk) {
      results.add(item);
      cache.store(
        item['path']! as String,
        size: item['size']! as int,
        modified: item['modified']! as int,
        title: item['title']! as String,
        author: item['author']! as String,
      );
    }
  }

  cache.retainWithin(folderPath, paths.toSet());
  await cache.save();
  return results;
}

/// Reads the metadata of one group of changed files.
Future<List<Map<String, Object?>>> _readMetadataChunk(
  List<Map<String, Object?>> chunk,
) async {
  final result = <Map<String, Object?>>[];
  for (final item in chunk) {
    final path = item['path']! as String;
    final size = item['size']! as int;
    final modified = item['modified']! as int;
    try {
      final metadata = await readEpubMetadata(path);
      result.add({
        'path': path,
        'title': metadata.title,
        'author': metadata.author,
        'size': size,
        'modified': modified,
        'cached': false,
      });
    } catch (_) {
      result.add({
        'path': path,
        'title': p.basenameWithoutExtension(path),
        'author': 'Unknown Author',
        'size': size,
        'modified': modified,
        'cached': false,
      });
    }
  }
  return result;
}

/// Splits [items] into at most [workers] roughly equal parts.
List<List<T>> _chunk<T>(List<T> items, int workers) {
  if (items.isEmpty) return const [];
  final count = math.max(1, math.min(workers, items.length));
  final chunks = <List<T>>[];
  for (var i = 0; i < count; i++) {
    final start = (items.length * i) ~/ count;
    final end = (items.length * (i + 1)) ~/ count;
    chunks.add(items.sublist(start, end));
  }
  return chunks;
}

int _workerCount(int items) {
  if (items <= 1) return 1;
  return math.min(math.min(4, Platform.numberOfProcessors), items);
}

class _CollectedFiles {
  const _CollectedFiles(
    this.paths,
    this.unreadablePaths,
    this.permissionDenied,
  );

  final List<String> paths;
  final List<String> unreadablePaths;
  final bool permissionDenied;
}

/// Recursively lists all *.epub files under [root].
///
/// Each folder is listed on its own, so an unreadable sub-folder only skips
/// that folder instead of aborting the whole walk.
Future<_CollectedFiles> _collectEpubFiles(Directory root) async {
  final results = <String>[];
  final unreadable = <String>[];
  var permissionDenied = false;
  final queue = <Directory>[root];

  while (queue.isNotEmpty) {
    final dir = queue.removeLast();
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          queue.add(entity);
        } else if (entity is File &&
            entity.path.toLowerCase().endsWith('.epub')) {
          results.add(entity.path);
        }
      }
    } on FileSystemException catch (error) {
      unreadable.add(dir.path);
      if (_isPermissionError(error)) permissionDenied = true;
    }
  }

  return _CollectedFiles(results, unreadable, permissionDenied);
}

bool _isPermissionError(FileSystemException error) {
  final code = error.osError?.errorCode;
  // EACCES/EPERM on Linux and Android.
  if (code == 1 || code == 13) return true;
  final message = error.message.toLowerCase();
  return message.contains('permission') || message.contains('access denied');
}
