import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/library/cache_maintenance.dart';
import 'package:folio/library/cache_service.dart';
import 'package:folio/library/cover_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory cache;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('folio_cache_maint_');
  });

  tearDown(() async {
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  test('deletes old incoming copies and keeps recent ones', () async {
    final incoming = Directory(p.join(cache.path, 'incoming'));
    await incoming.create(recursive: true);
    final old = File(p.join(incoming.path, 'old-book.epub'))
      ..writeAsBytesSync([1, 2, 3]);
    final recent = File(p.join(incoming.path, 'recent-book.epub'))
      ..writeAsBytesSync([4, 5, 6]);
    final partial = File(p.join(incoming.path, 'half.epub.part'))
      ..writeAsBytesSync([7]);
    final now = DateTime.now();
    old.setLastModifiedSync(now.subtract(const Duration(days: 30)));
    recent.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
    partial.setLastModifiedSync(now);

    final removed = await pruneIncomingFiles(cache);

    expect(removed, 2);
    expect(old.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
  });

  test('a missing incoming folder is not an error', () async {
    expect(await pruneIncomingFiles(cache), 0);
  });

  Directory epubCache(String name, {String? source, DateTime? used}) {
    final dir = Directory(p.join(cache.path, 'epub', 'epub_$name'))
      ..createSync(recursive: true);
    File(p.join(dir.path, '.folio-cache.json')).writeAsStringSync(
      jsonEncode({
        'path': source ?? p.join(cache.path, '$name.epub'),
        'size': 1,
        'mtime': 1,
      }),
    );
    if (used != null) {
      final access = File(p.join(dir.path, '.folio-access'));
      access.writeAsStringSync('');
      access.setLastModifiedSync(used);
    }
    return dir;
  }

  test('pruneLibraryCaches drops old, abandoned and temporary books', () async {
    final now = DateTime(2026, 11, 10, 12);
    final source = File(p.join(cache.path, 'kept.epub'))
      ..writeAsBytesSync([1]);

    final fresh = epubCache(
      'fresh',
      source: source.path,
      used: now.subtract(const Duration(days: 2)),
    );
    final old = epubCache(
      'old',
      source: source.path,
      used: now.subtract(const Duration(days: 90)),
    );
    final abandoned = epubCache(
      'abandoned',
      source: p.join(cache.path, 'gone.epub'),
      used: now.subtract(const Duration(days: 2)),
    );
    final temporary = Directory(p.join(cache.path, 'epub', 'epub_fresh.tmp-1'))
      ..createSync(recursive: true);
    final access = File(p.join(temporary.path, '.folio-access'));
    access.writeAsStringSync('');
    access.setLastModifiedSync(now.subtract(const Duration(days: 2)));

    final covers = Directory(p.join(cache.path, 'covers'))..createSync();
    final oldCover = File(p.join(covers.path, 'old.jpg'))
      ..writeAsBytesSync([1]);
    oldCover.setLastModifiedSync(now.subtract(const Duration(days: 90)));
    final freshCover = File(p.join(covers.path, 'fresh.jpg'))
      ..writeAsBytesSync([1]);
    freshCover.setLastModifiedSync(now.subtract(const Duration(days: 2)));

    final removed = await pruneLibraryCaches(
      epubRoot: Directory(p.join(cache.path, 'epub')),
      coversRoot: covers,
      now: now,
    );

    expect(removed, 4);
    expect(fresh.existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
    expect(abandoned.existsSync(), isFalse);
    expect(temporary.existsSync(), isFalse);
    expect(oldCover.existsSync(), isFalse);
    expect(freshCover.existsSync(), isTrue);
  });

  test('clear keeps the open book and removes every other cache', () async {
    final epubRoot = Directory(p.join(cache.path, 'epub'))..createSync();
    final coversRoot = Directory(p.join(cache.path, 'covers'))..createSync();
    final source = File(p.join(cache.path, 'open.epub'))
      ..writeAsBytesSync([1]);
    final openDir = epubCache('open', source: source.path);
    final otherDir = epubCache(
      'other',
      source: p.join(cache.path, 'other.epub'),
    );
    File(p.join(coversRoot.path, 'thumb.jpg')).writeAsBytesSync([1]);

    final service = CacheService(
      epubLoader: EpubLoader(cacheRoot: epubRoot),
      coverService: CoverService(cacheRoot: coversRoot),
    );
    await service.clear(keepBookPaths: {source.path});

    expect(openDir.existsSync(), isTrue);
    expect(otherDir.existsSync(), isFalse);
    expect(coversRoot.existsSync() && coversRoot.listSync().isNotEmpty, isFalse);
  });
}
