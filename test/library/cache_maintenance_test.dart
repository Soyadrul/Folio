import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/library/cache_maintenance.dart';
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
}
