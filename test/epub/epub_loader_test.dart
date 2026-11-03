import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

void main() {
  late Directory tmp;
  late Directory cache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_epub_test_');
    cache = Directory(p.join(tmp.path, 'cache'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  EpubLoader loader() => EpubLoader(cacheRoot: cache);

  group('EPUB 2', () {
    test('parses metadata, spine order, TOC and cover', () async {
      final file = await EpubFixture.write(tmp, epub2Entries());
      final book = await loader().load(file.path);

      expect(book.title, 'Old Book');
      expect(book.author, 'Jane Doe');
      expect(book.chapters, hasLength(2));
      expect(book.chapters[0].href, 'text/ch1.xhtml');
      expect(book.chapters[1].href, 'text/ch2.xhtml');
      expect(book.chapters[0].title, 'One');
      expect(book.chapters[1].title, 'Two');
      expect(book.toc, hasLength(2));
      expect(book.toc[1].chapterIndex, 1);
      expect(book.toc[1].fragment, 'sec');
      expect(book.coverImagePath, endsWith('OEBPS/images/Cover.JPG'));
      expect(File(book.coverImagePath!).existsSync(), isTrue);
      expect(book.totalChapterBytes, greaterThan(0));
    });

    test('excludes spine items marked linear="no"', () async {
      final opf = epub2Opf.replaceFirst(
        '<itemref idref="skipped" linear="no"/>',
        '<item idref="skipped" href="text/ch2.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<itemref idref="skipped" linear="no"/>',
      );
      final file = await EpubFixture.write(tmp, epub2Entries(opf: opf));
      final book = await loader().load(file.path);
      expect(book.chapters.map((c) => c.href), [
        'text/ch1.xhtml',
        'text/ch2.xhtml',
      ]);
    });

    test('falls back to the guide cover chapter image', () async {
      final opf = epub2Opf
          .replaceFirst('    <meta name="cover" content="cover-img"/>\n', '')
          .replaceFirst(
            '<item id="cover-img" href="images/Cover.JPG" media-type="image/jpeg"/>',
            '<item id="cover-page" href="text/cover.xhtml" '
                'media-type="application/xhtml+xml"/>',
          );
      final entries = epub2Entries(opf: opf)
        ..['OEBPS/text/cover.xhtml'] =
            '<html><body><svg><image xlink:href="../images/pic.jpg"/></svg>'
            '</body></html>';
      final file = await EpubFixture.write(tmp, entries);
      final book = await loader().load(file.path);
      expect(book.coverImagePath, endsWith('OEBPS/images/pic.jpg'));
    });

    test('falls back to the first image in the first spine chapter', () async {
      final opf = epub2Opf
          .replaceFirst('    <meta name="cover" content="cover-img"/>\n', '')
          .replaceFirst('  <guide>\n', '  <guide></guide>\n  <!--\n')
          .replaceFirst('  </guide>\n', '  -->\n')
          .replaceFirst(
            '<item id="cover-img" href="images/Cover.JPG" media-type="image/jpeg"/>',
            '',
          );
      final file = await EpubFixture.write(tmp, epub2Entries(opf: opf));
      final book = await loader().load(file.path);
      expect(book.coverImagePath, endsWith('OEBPS/images/pic.jpg'));
    });
  });

  group('EPUB 3', () {
    test('reads cover-image, nav TOC and creators', () async {
      final file = await EpubFixture.write(tmp, epub3Entries());
      final book = await loader().load(file.path);

      expect(book.title, 'New Book');
      expect(book.author, 'John Roe');
      expect(book.coverImagePath, endsWith('OEBPS/images/cover.png'));
      expect(book.chapters, hasLength(2));
      expect(book.toc.map((t) => t.title), ['First', 'Second']);
      expect(book.toc[1].chapterIndex, 1);
      expect(book.toc[1].fragment, 'sec');
    });

    test('supports URL-encoded manifest hrefs', () async {
      final opf = epub3Opf.replaceFirst(
        '<item id="cover" href="images/cover.png" media-type="image/png"',
        '<item id="cover" href="images/My%20Cover.png" media-type="image/png"',
      );
      final entries = epub3Entries(opf: opf)
        ..remove('OEBPS/images/cover.png')
        ..['OEBPS/images/My Cover.png'] = 'cover-bytes';
      final file = await EpubFixture.write(tmp, entries);
      final book = await loader().load(file.path);
      expect(book.coverImagePath, endsWith('OEBPS/images/My Cover.png'));
    });
  });

  group('cache', () {
    test('extracts once and reuses the cache for an unchanged file', () async {
      final file = await EpubFixture.write(tmp, epub2Entries());
      final l = loader();
      final first = await l.load(file.path);
      final sentinel = File(p.join(first.cacheDir, 'sentinel.txt'));
      await sentinel.writeAsString('keep me');

      final second = await l.load(file.path);
      expect(second.cacheDir, first.cacheDir);
      expect(sentinel.existsSync(), isTrue);
    });

    test('re-extracts when size or mtime changes', () async {
      final file = await EpubFixture.write(tmp, epub2Entries());
      final l = loader();
      final first = await l.load(file.path);
      final sentinel = File(p.join(first.cacheDir, 'sentinel.txt'));
      await sentinel.writeAsString('stale');

      // Rewrite the book with one extra file and a new modification time.
      await EpubFixture.write(
        tmp,
        epub2Entries()
          ..['OEBPS/extra.txt'] = 'extra'
          ..['META-INF/container.xml'] = containerXml,
      );
      final second = await l.load(file.path);
      expect(second.cacheDir, first.cacheDir);
      expect(sentinel.existsSync(), isFalse);
      expect(
        File(p.join(second.cacheDir, 'OEBPS/extra.txt')).existsSync(),
        isTrue,
      );
    });
  });

  group('robustness', () {
    test('rejects a damaged archive with a clear EpubException', () async {
      final file = File(p.join(tmp.path, 'broken.epub'));
      await file.writeAsBytes([1, 2, 3, 4, 5]);
      expect(() => loader().load(file.path), throwsA(isA<EpubException>()));
    });

    test('rejects a book without META-INF/container.xml', () async {
      final file = await EpubFixture.write(tmp, {
        'OEBPS/content.opf': epub2Opf,
      });
      expect(
        () => loader().load(file.path),
        throwsA(
          isA<EpubException>().having(
            (e) => e.message,
            'message',
            contains('container.xml'),
          ),
        ),
      );
    });

    test('never writes outside the extraction folder (zip slip)', () async {
      final file = await EpubFixture.write(
        tmp,
        epub2Entries()
          ..['../evil.txt'] = 'evil'
          ..['/absolute.txt'] = 'evil',
      );
      final book = await loader().load(file.path);
      expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
      expect(File('/absolute.txt').existsSync(), isFalse);
      expect(
        File(p.join(book.cacheDir, '..', 'evil.txt')).existsSync(),
        isFalse,
      );
    });
  });
}
