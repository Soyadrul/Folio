import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub_cover.dart';
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_epub_cover_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('reads the EPUB 2 meta cover without extracting the book', () async {
    final file = await EpubFixture.write(tmp, {
      ...epub2Entries(),
      'OEBPS/images/Cover.JPG': <int>[9, 8, 7, 6],
    });

    final cover = await readEpubCover(file.path);

    expect(cover, isNotNull);
    expect(cover!.entryName, 'OEBPS/images/Cover.JPG');
    expect(cover.bytes, [9, 8, 7, 6]);
    final folders = (await tmp.list().toList()).whereType<Directory>();
    expect(
      folders.where((dir) => p.basename(dir.path).startsWith('epub_')),
      isEmpty,
    );
  });

  test('reads the EPUB 3 cover-image property', () async {
    final file = await EpubFixture.write(tmp, epub3Entries());
    final cover = await readEpubCover(file.path);
    expect(cover, isNotNull);
    expect(cover!.entryName, 'OEBPS/images/cover.png');
    expect(cover.bytes, utf8.encode('cover-bytes'));
  });

  test('unwraps an SVG cover to its raster image', () async {
    final opf = epub3Opf.replaceFirst(
      'href="images/cover.png" media-type="image/png"',
      'href="images/cover.svg" media-type="image/svg+xml"',
    );
    final file = await EpubFixture.write(tmp, <String, Object>{
      ...epub3Entries(opf: opf),
      'OEBPS/images/cover.svg':
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 600 900">'
          '<image width="600" height="900" xlink:href="cover.png"/>'
          '</svg>',
      'OEBPS/images/cover.png': <int>[1, 2, 3],
    });

    final cover = await readEpubCover(file.path);
    expect(cover, isNotNull);
    expect(cover!.entryName, 'OEBPS/images/cover.png');
    expect(cover.bytes, [1, 2, 3]);
  });

  test('falls back to the guide cover chapter image', () async {
    final opf = epub2Opf
        .replaceFirst('    <meta name="cover" content="cover-img"/>\n', '')
        .replaceFirst(
          '<item id="cover-img" href="images/Cover.JPG" media-type="image/jpeg"/>',
          '<item id="cover-page" href="text/cover.xhtml" '
              'media-type="application/xhtml+xml"/>',
        );
    final file = await EpubFixture.write(tmp, <String, Object>{
      ...epub2Entries(opf: opf),
      'OEBPS/text/cover.xhtml':
          '<html><body><svg><image xlink:href="../images/pic.jpg"/></svg>'
          '</body></html>',
    });

    final cover = await readEpubCover(file.path);
    expect(cover, isNotNull);
    expect(cover!.entryName, 'OEBPS/images/pic.jpg');
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

    final cover = await readEpubCover(file.path);
    expect(cover, isNotNull);
    expect(cover!.entryName, 'OEBPS/images/pic.jpg');
  });

  test('returns null for a book without a cover', () async {
    final opf = epub2Opf.replaceFirst(
      '    <meta name="cover" content="cover-img"/>\n',
      '',
    );
    final chapter = chapterOne.replaceFirst(
      '<p><img src="../images/pic.jpg" alt="pic"/></p>',
      '',
    );
    final entries = epub2Entries(opf: opf)..remove('OEBPS/images/pic.jpg');
    final file = await EpubFixture.write(tmp, <String, Object>{
      ...entries,
      'OEBPS/text/ch1.xhtml': chapter,
    });

    expect(await readEpubCover(file.path), isNull);
  });

  test('returns null for a damaged book', () async {
    final file = File(p.join(tmp.path, 'broken.epub'));
    await file.writeAsBytes([1, 2, 3, 4]);
    expect(await readEpubCover(file.path), isNull);
  });
}
