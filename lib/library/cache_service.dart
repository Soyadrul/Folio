import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../epub/epub.dart';
import 'cache_maintenance.dart';
import 'cover_service.dart';

/// Owns the two disposable caches: extracted books and cover thumbnails.
class CacheService {
  CacheService({EpubLoader? epubLoader, CoverService? coverService})
    : _epub = epubLoader ?? EpubLoader(),
      _covers = coverService ?? CoverService();

  final EpubLoader _epub;
  final CoverService _covers;

  /// Age-based cleanup run at startup. Never throws.
  Future<int> prune() async {
    try {
      return await pruneLibraryCaches(
        epubRoot: await _epub.cacheDirectory(),
        coversRoot: await _covers.cacheDirectory(),
      );
    } catch (_) {
      return 0;
    }
  }

  /// Removes every cache entry except the extraction of an open book.
  Future<void> clear({Set<String> keepBookPaths = const {}}) async {
    await _covers.clearCache();
    await _epub.clearCache(keepBookPaths: keepBookPaths);
  }
}

final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(coverService: ref.read(coverServiceProvider));
});
