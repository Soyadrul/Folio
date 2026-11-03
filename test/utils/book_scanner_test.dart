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

    final books = await scanFolderForBooks(tmp.path);

    expect(books.map((b) => b.title), ['New Book', 'Old Book']);
    expect(books.map((b) => p.basename(b.path)), ['a.epub', 'b.epub']);
    expect(books.every((b) => b.author.isNotEmpty), isTrue);
    expect(books.every((b) => b.lastModifiedMs > 0), isTrue);
  });

  test('keeps books with broken metadata using filename fallbacks', () async {
    await writeBook('good.epub', epub2Entries());
    final broken = File(p.join(tmp.path, 'broken.epub'));
    await broken.writeAsBytes([1, 2, 3, 4]);

    final books = await scanFolderForBooks(tmp.path);

    expect(books, hasLength(2));
    final brokenBook = books.firstWhere((b) => b.title == 'broken');
    expect(brokenBook.author, 'Unknown Author');
    expect(books.any((b) => b.title == 'Old Book'), isTrue);
  });

  test('returns an empty list for a missing folder', () async {
    expect(
      await scanFolderForBooks(p.join(tmp.path, 'does-not-exist')),
      isEmpty,
    );
  });

  test('ignores files that are not .epub, case-insensitively', () async {
    await writeBook('UPPER.EPUB', epub2Entries());

    final books = await scanFolderForBooks(tmp.path);

    expect(books, hasLength(1));
    expect(books.single.title, 'Old Book');
  });
}
