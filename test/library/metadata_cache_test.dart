import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/library/metadata_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_metadata_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  void store(MetadataCache cache, String path) {
    cache.store(path, size: 1, modified: 1, title: 'T', author: 'A');
  }

  test('switching folders keeps the other folder in the cache', () async {
    final cache = await MetadataCache.load(null);
    final first = p.join(tmp.path, 'first', 'a.epub');
    final second = p.join(tmp.path, 'second', 'b.epub');
    store(cache, first);
    store(cache, second);

    cache.retainWithin(p.join(tmp.path, 'first'), {first});
    expect(cache.lookup(first, size: 1, modified: 1), isNotNull);
    expect(cache.lookup(second, size: 1, modified: 1), isNotNull);

    cache.retainWithin(p.join(tmp.path, 'first'), {});
    expect(cache.lookup(first, size: 1, modified: 1), isNull);
    expect(cache.lookup(second, size: 1, modified: 1), isNotNull);
  });

  test('save is atomic and leaves no temporary file behind', () async {
    final path = p.join(tmp.path, 'cache', 'metadata.json');
    final cache = await MetadataCache.load(path);
    store(cache, p.join(tmp.path, 'a.epub'));

    await cache.save();

    final siblings = Directory(
      p.dirname(path),
    ).listSync().map((e) => p.basename(e.path));
    expect(siblings, contains('metadata.json'));
    expect(siblings.where((name) => name.endsWith('.tmp')), isEmpty);
    final decoded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect(decoded['entries'], hasLength(1));
  });

  test('overlapping saves leave a valid file', () async {
    final path = p.join(tmp.path, 'cache', 'metadata.json');
    final one = await MetadataCache.load(path);
    final two = await MetadataCache.load(path);
    store(one, p.join(tmp.path, 'a.epub'));
    store(two, p.join(tmp.path, 'b.epub'));

    await Future.wait([one.save(), two.save()]);

    final decoded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    expect(decoded, isA<Map<String, dynamic>>());
    expect(decoded['entries'], isA<Map<String, dynamic>>());
  });
}
