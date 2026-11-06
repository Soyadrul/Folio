import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/utils/book_scanner.dart';
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_scanner_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> writeBook(
    String relativePath,
    Map<String, String> entries,
  ) async {
    final dir = Directory(p.join(tmp.path, p.dirname(relativePath)));
    await dir.create(recursive: true);
    return EpubFixture.write(dir, entries, name: p.basename(relativePath));
  }

  test('finds nested EPUBs and sorts them by title', () async {
    await writeBook('shelf/b.epub', epub2Entries());
    await writeBook('shelf/deeper/a.epub', epub3Entries());
    await File(p.join(tmp.path, 'notes.txt')).writeAsString('not a book');

    final scan = await scanFolderForBooks(tmp.path);
    final books = scan.books;

    expect(books.map((b) => b.title), ['New Book', 'Old Book']);
    expect(books.map((b) => p.basename(b.path)), ['a.epub', 'b.epub']);
    expect(books.every((b) => b.author.isNotEmpty), isTrue);
    expect(books.every((b) => b.lastModifiedMs > 0), isTrue);
  });

  test('keeps books with broken metadata using filename fallbacks', () async {
    await writeBook('good.epub', epub2Entries());
    final broken = File(p.join(tmp.path, 'broken.epub'));
    await broken.writeAsBytes([1, 2, 3, 4]);

    final books = (await scanFolderForBooks(tmp.path)).books;

    expect(books, hasLength(2));
    final brokenBook = books.firstWhere((b) => b.title == 'broken');
    expect(brokenBook.author, 'Unknown Author');
    expect(books.any((b) => b.title == 'Old Book'), isTrue);
  });

  test('returns a missing-folder result instead of scanning', () async {
    final scan = await scanFolderForBooks(p.join(tmp.path, 'does-not-exist'));

    expect(scan.exists, isFalse);
    expect(scan.books, isEmpty);
  });

  test('ignores files that are not .epub, case-insensitively', () async {
    await writeBook('UPPER.EPUB', epub2Entries());

    final books = (await scanFolderForBooks(tmp.path)).books;

    expect(books, hasLength(1));
    expect(books.single.title, 'Old Book');
  });

  test(
    'reuses cached metadata while the file signature is unchanged',
    () async {
      final file = await writeBook('cached.epub', epub2Entries());
      final cachePath = p.join(tmp.path, 'cache', 'metadata.json');

      final first = await scanFolderForBooks(tmp.path, cachePath: cachePath);
      expect(first.cacheHits, 0);
      expect(first.books.single.title, 'Old Book');
      expect(File(cachePath).existsSync(), isTrue);

      // Keep the size and modification time but destroy the contents. A scan
      // that re-read the archive would fall back to the file name.
      final bytes = await file.readAsBytes();
      final modified = await file.lastModified();
      await file.writeAsBytes(List<int>.filled(bytes.length, 0));
      await file.setLastModified(modified);

      final second = await scanFolderForBooks(tmp.path, cachePath: cachePath);
      expect(second.cacheHits, 1);
      expect(second.books.single.title, 'Old Book');

      // A changed modification time forces a re-read.
      await file.setLastModified(modified.add(const Duration(seconds: 2)));
      final third = await scanFolderForBooks(tmp.path, cachePath: cachePath);
      expect(third.cacheHits, 0);
      expect(third.books.single.title, 'cached');
    },
  );

  test('skips an unreadable sub-folder and reports it', () async {
    await writeBook('good.epub', epub2Entries());
    final locked = Directory(p.join(tmp.path, 'locked'));
    await locked.create();
    await writeBook('locked/hidden.epub', epub2Entries());
    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['700', locked.path]));

    // Root ignores directory permissions; do not assert something the
    // environment cannot produce.
    var unreadable = false;
    try {
      await locked.list().toList();
    } on FileSystemException {
      unreadable = true;
    }
    if (!unreadable) return;

    final scan = await scanFolderForBooks(tmp.path);

    expect(scan.books.map((b) => b.title), contains('Old Book'));
    expect(scan.skippedFolders, greaterThan(0));
    expect(scan.unreadablePaths.any((path) => path.contains('locked')), isTrue);
  });
}
