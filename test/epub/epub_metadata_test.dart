import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub_metadata.dart';
import 'package:path/path.dart' as p;

import '../support/epub_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('folio_metadata_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('reads title and author from an EPUB 2 package', () async {
    final file = await EpubFixture.write(tmp, epub2Entries());
    final metadata = await readEpubMetadata(file.path);
    expect(metadata.title, 'Old Book');
    expect(metadata.author, 'Jane Doe');
  });

  test('reads title and author from an EPUB 3 package', () async {
    final file = await EpubFixture.write(tmp, epub3Entries());
    final metadata = await readEpubMetadata(file.path);
    expect(metadata.title, 'New Book');
    expect(metadata.author, 'John Roe');
  });

  test('falls back to the file name and Unknown Author', () async {
    final opf = epub2Opf
        .replaceFirst('<dc:title>Old Book</dc:title>', '')
        .replaceFirst('<dc:creator>Jane Doe</dc:creator>', '');
    final file = await EpubFixture.write(
      tmp,
      epub2Entries(opf: opf),
      name: 'A File Name.epub',
    );
    final metadata = await readEpubMetadata(file.path);
    expect(metadata.title, 'A File Name');
    expect(metadata.author, 'Unknown Author');
  });

  test('decodes URL-encoded container and package paths', () async {
    final entries = epub2Entries()
      ..remove('OEBPS/content.opf')
      ..['OEBPS/My Content.opf'] = epub2Opf;
    entries['META-INF/container.xml'] = containerXml.replaceFirst(
      'OEBPS/content.opf',
      'OEBPS/My%20Content.opf',
    );
    final file = await EpubFixture.write(tmp, entries);
    final metadata = await readEpubMetadata(file.path);
    expect(metadata.title, 'Old Book');
  });

  test('rejects damaged archives with a FormatException', () async {
    final file = File(p.join(tmp.path, 'broken.epub'));
    await file.writeAsBytes([1, 2, 3, 4, 5]);
    expect(() => readEpubMetadata(file.path), throwsA(isA<FormatException>()));
  });

  test('rejects a book without container.xml', () async {
    final file = await EpubFixture.write(tmp, {'OEBPS/content.opf': epub2Opf});
    expect(
      () => readEpubMetadata(file.path),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('container.xml'),
        ),
      ),
    );
  });
}
