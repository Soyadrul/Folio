import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../epub/epub_cover.dart';
import '../models/book.dart';

/// Resolves book covers into small JPEG thumbnails on disk.
///
/// Covers are produced lazily by the library cards, so opening a folder with
/// hundreds of books never extracts or decodes them all. The thumbnail name
/// includes the EPUB's path, size and modification time: a changed book gets a
/// new thumbnail, while an unchanged one is reused forever.
class CoverService {
  CoverService({
    Directory? cacheRoot,
    this.thumbnailWidth = 300,
    this.maxConcurrent = 2,
  }) : _cacheRoot = cacheRoot;

  final Directory? _cacheRoot;
  final int thumbnailWidth;

  /// Extraction + decoding are CPU/IO heavy, so only a couple of cards may
  /// work at once. The rest wait and the grid stays responsive.
  final int maxConcurrent;

  Future<Directory>? _resolvedRoot;
  int _running = 0;
  final List<Completer<void>> _waiting = [];
  final Map<String, _CachedCover> _memo = {};
  final Map<String, Future<String?>> _inFlight = {};

  Future<Directory> _root() async {
    final injected = _cacheRoot;
    if (injected != null) return injected;
    return _resolvedRoot ??= () async {
      final base = await getApplicationCacheDirectory();
      return Directory(p.join(base.path, 'folio_covers'));
    }();
  }

  Future<Directory> cacheDirectory() => _root();

  /// Returns the thumbnail path for [book], or null when the book has no
  /// usable cover. Never throws: a broken book just keeps its placeholder.
  Future<String?> thumbnailFor(Book book) async {
    final file = File(book.path);
    late final FileStat stat;
    try {
      if (!await file.exists()) return null;
      stat = await file.stat();
    } on FileSystemException {
      return null;
    }

    final signature = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final memo = _memo[book.path];
    if (memo != null && memo.signature == signature) return memo.path;

    final root = await _root();
    final key = sha1
        .convert(
          utf8.encode('${p.normalize(p.absolute(book.path))}|$signature|v1'),
        )
        .toString();
    final destination = p.join(root.path, '$key.jpg');

    final running = _inFlight[book.path];
    if (running != null) return running;

    final future = _build(bookPath: book.path, destination: destination);
    _inFlight[book.path] = future;
    try {
      final result = await future;
      _memo[book.path] = _CachedCover(signature, result);
      return result;
    } finally {
      _inFlight.remove(book.path);
    }
  }

  Future<String?> _build({
    required String bookPath,
    required String destination,
  }) async {
    // A zero-byte sidecar records "this book has no usable cover", so opening
    // the same folder again does not unzip and decode it every time.
    final missingMarker = File('$destination.none');
    try {
      if (await File(destination).exists()) return destination;
      if (await missingMarker.exists()) return null;

      final targetWidth = thumbnailWidth;
      final rendered = await _withSlot(() async {
        // Read only the container, package document and cover entry: the book
        // itself is never extracted, so browsing the library stays cheap.
        final cover = await Isolate.run(() => readEpubCoverStrict(bookPath));
        if (cover == null) return false;
        await Directory(p.dirname(destination)).create(recursive: true);
        return Isolate.run(
          () => _renderThumbnail(
            bytes: cover.bytes,
            destinationPath: destination,
            width: targetWidth,
          ),
        );
      });
      if (rendered && await File(destination).exists()) return destination;
      // Reaching this point means the EPUB was read successfully. Either it
      // has no cover or the image bytes are not decodable; both are stable
      // properties of this file, so remembering the answer is safe.
      await _writeMissingMarker(missingMarker);
      return null;
    } catch (e) {
      // Storage, isolate and memory failures are temporary. Writing `.none`
      // here made the book show a placeholder until the file changed.
      debugPrint('Folio: no cover for $bookPath ($e)');
      return null;
    }
  }

  Future<void> _writeMissingMarker(File marker) async {
    try {
      await marker.parent.create(recursive: true);
      await marker.writeAsBytes(const []);
    } catch (_) {
      // The marker only saves work; failing to write it is harmless.
    }
  }

  Future<T> _withSlot<T>(Future<T> Function() action) async {
    while (_running >= maxConcurrent) {
      final completer = Completer<void>();
      _waiting.add(completer);
      await completer.future;
    }
    _running++;
    try {
      return await action();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  /// Deletes every generated thumbnail (used when the cache is cleared).
  Future<void> clearCache() async {
    _memo.clear();
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _CachedCover {
  const _CachedCover(this.signature, this.path);
  final String signature;
  final String? path;
}

/// Runs in an isolate: decode, orient, resize and re-encode the cover.
bool _renderThumbnail({
  required List<int> bytes,
  required String destinationPath,
  required int width,
}) {
  try {
    final decoded = img.decodeImage(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    if (decoded == null) return false;
    final oriented = img.bakeOrientation(decoded);
    final resized = oriented.width <= width
        ? oriented
        : img.copyResize(oriented, width: width);
    final encoded = img.encodeJpg(resized, quality: 82);
    final temporary = File('$destinationPath.tmp');
    temporary.writeAsBytesSync(encoded, flush: true);
    temporary.renameSync(destinationPath);
    return true;
  } catch (_) {
    return false;
  }
}

final coverServiceProvider = Provider<CoverService>((ref) => CoverService());
