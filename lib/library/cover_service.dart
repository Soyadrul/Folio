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
import 'package:xml/xml.dart';

import '../epub/epub.dart';
import '../epub/href_resolver.dart';
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
    EpubLoader? loader,
    this.thumbnailWidth = 300,
    this.maxConcurrent = 2,
  }) : _cacheRoot = cacheRoot,
       _loader = loader ?? EpubLoader();

  final Directory? _cacheRoot;
  final EpubLoader _loader;
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
    try {
      if (await File(destination).exists()) return destination;

      final document = await _loader.load(bookPath);
      final source = _rasterSource(document);
      if (source == null) return null;

      final targetWidth = thumbnailWidth;
      await _withSlot(() async {
        await Directory(p.dirname(destination)).create(recursive: true);
        return Isolate.run(
          () => _renderThumbnail(
            sourcePath: source,
            destinationPath: destination,
            width: targetWidth,
          ),
        );
      });
      return await File(destination).exists() ? destination : null;
    } catch (e) {
      // A damaged cover, unsupported image format or unreadable book must not
      // stop the rest of the library.
      debugPrint('Folio: no cover for $bookPath ($e)');
      return null;
    }
  }

  /// Returns a raster file for the document's cover, unwrapping an SVG cover
  /// page to the first raster image it references.
  String? _rasterSource(EpubDocument document) {
    final cover = document.coverImagePath;
    if (cover == null) return null;
    if (p.extension(cover).toLowerCase() != '.svg') return cover;
    return _rasterInsideSvg(cover, document.rootDir, document.resolver);
  }

  String? _rasterInsideSvg(
    String svgPath,
    String bookRoot,
    HrefResolver resolver,
  ) {
    try {
      final document = XmlDocument.parse(File(svgPath).readAsStringSync());
      final svgRel = p.relative(svgPath, from: bookRoot).replaceAll('\\', '/');
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
        final resolved = resolver.resolve(href, basePath: svgRel);
        if (resolved.path == null) continue;
        final absolute = p.joinAll([bookRoot, ...resolved.path!.split('/')]);
        if (File(absolute).existsSync()) return absolute;
      }
    } catch (_) {
      // An unreadable SVG cover just falls back to the placeholder.
    }
    return null;
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
  required String sourcePath,
  required String destinationPath,
  required int width,
}) {
  try {
    final bytes = File(sourcePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
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
