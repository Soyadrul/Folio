import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/library/cover_service.dart';
import 'package:folio/models/book.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

List<int> coverBytes({int width = 600, int height = 900, int shade = 120}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(shade, 80, 40));
  return img.encodeJpg(image, quality: 88);
}

void main() {
  late Directory tmp;
  late Directory coverCache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_cover_test_');
    coverCache = Directory(p.join(tmp.path, 'covers'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  CoverService service() => CoverService(cacheRoot: coverCache);

  Book bookFor(File file) =>
      Book(path: file.path, title: 'Title', author: 'Author');

  Future<File> writeWithCover(List<int> bytes, {String name = 'book.epub'}) {
    return EpubFixture.write(tmp, <String, Object>{
      ...epub2Entries(),
      'OEBPS/images/Cover.JPG': bytes,
    }, name: name);
  }

  test('creates a ~300px wide thumbnail and reuses it', () async {
    final book = bookFor(await writeWithCover(coverBytes()));

    final first = await service().thumbnailFor(book);
    expect(first, isNotNull);
    final file = File(first!);
    expect(file.existsSync(), isTrue);

    final decoded = img.decodeImage(await file.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.width, 300);
    expect(decoded.height, 450);

    final modified = await file.lastModified();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = await service().thumbnailFor(book);
    expect(second, first);
    expect(await File(second!).lastModified(), modified);
  });

  test('does not upscale a small cover', () async {
    final book = bookFor(
      await writeWithCover(coverBytes(width: 120, height: 180)),
    );
    final path = await service().thumbnailFor(book);
    final decoded = img.decodeImage(await File(path!).readAsBytes());
    expect(decoded!.width, 120);
  });

  test('a changed book gets a fresh thumbnail', () async {
    final book = bookFor(await writeWithCover(coverBytes()));
    final first = await service().thumbnailFor(book);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    await writeWithCover(coverBytes(width: 500, height: 700, shade: 220));
    final second = await service().thumbnailFor(book);

    expect(second, isNotNull);
    expect(second, isNot(first));
    expect(File(second!).existsSync(), isTrue);
  });

  test('unwraps an SVG cover page to its raster image', () async {
    final opf = epub3Opf.replaceFirst(
      'href="images/cover.png" media-type="image/png"',
      'href="images/cover.svg" media-type="image/svg+xml"',
    );
    final file = await EpubFixture.write(tmp, <String, Object>{
      ...epub3Entries(opf: opf),
      'OEBPS/images/cover.svg':
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" '
          'viewBox="0 0 600 900">'
          '<image width="600" height="900" xlink:href="cover.png"/>'
          '</svg>',
      'OEBPS/images/cover.png': coverBytes(),
    });

    final path = await service().thumbnailFor(bookFor(file));
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
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

    expect(await service().thumbnailFor(bookFor(file)), isNull);
  });

  test('returns null for a corrupt cover image', () async {
    final file = await writeWithCover(<int>[1, 2, 3, 4]);
    expect(await service().thumbnailFor(bookFor(file)), isNull);
  });

  test('returns null for a corrupt book', () async {
    final file = File(p.join(tmp.path, 'broken.epub'));
    await file.writeAsBytes([1, 2, 3]);
    expect(await service().thumbnailFor(bookFor(file)), isNull);
  });

  test('clearCache removes generated thumbnails', () async {
    final book = bookFor(await writeWithCover(coverBytes()));
    final serviceUnderTest = service();
    final path = await serviceUnderTest.thumbnailFor(book);
    expect(File(path!).existsSync(), isTrue);

    await serviceUnderTest.clearCache();
    expect(File(path).existsSync(), isFalse);
  });

  test('a temporary read failure does not leave a permanent marker', () async {
    final broken = File(p.join(tmp.path, 'temporarily-broken.epub'));
    await broken.writeAsBytes([1, 2, 3, 4]);

    expect(await service().thumbnailFor(bookFor(broken)), isNull);

    final markers = coverCache.existsSync()
        ? coverCache
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.none'))
        : const <File>[];
    expect(markers, isEmpty);
  });

  test('a readable book without a cover does leave a marker', () async {
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
    }, name: 'no-cover.epub');

    expect(await service().thumbnailFor(bookFor(file)), isNull);

    final markers = coverCache
        .listSync(recursive: true)
        .whereType<File>()
        .where((candidate) => candidate.path.endsWith('.none'));
    expect(markers, hasLength(1));
  });
}
