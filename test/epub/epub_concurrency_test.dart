import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

void main() {
  late Directory tmp;
  late Directory cache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_epub_concurrency_');
    cache = Directory(p.join(tmp.path, 'cache'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('two loaders opening the same book share one extraction', () async {
    final file = await EpubFixture.write(tmp, epub2Entries());
    final first = EpubLoader(cacheRoot: cache);
    final second = EpubLoader(cacheRoot: cache);

    final documents = await Future.wait([
      first.load(file.path),
      second.load(file.path),
    ]);

    // One extraction, one document: a second caller must not delete the
    // folder the first caller is reading.
    expect(identical(documents[0], documents[1]), isTrue);
    expect(documents[0].chapters, hasLength(2));
    expect(documents[1].chapters, hasLength(2));
  });

  test('concurrent loads leave no temporary extraction folders', () async {
    final file = await EpubFixture.write(tmp, epub2Entries());
    final loader = EpubLoader(cacheRoot: cache);

    await Future.wait([loader.load(file.path), loader.load(file.path)]);

    final entries = await cache.list().toList();
    expect(
      entries.where((entity) => p.basename(entity.path).contains('.tmp-')),
      isEmpty,
    );
  });

  test('a failed extraction does not poison a later load', () async {
    final file = File(p.join(tmp.path, 'book.epub'));
    await file.writeAsBytes([1, 2, 3, 4, 5]);
    final loader = EpubLoader(cacheRoot: cache);

    await expectLater(
      loader.load(file.path),
      throwsA(isA<EpubException>()),
    );

    await EpubFixture.write(tmp, epub2Entries());
    final document = await loader.load(file.path);
    expect(document.chapters, hasLength(2));
  });
}
