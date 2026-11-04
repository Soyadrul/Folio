import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/href_resolver.dart';

void main() {
  final resolver = HrefResolver([
    'OEBPS/content.opf',
    'OEBPS/text/ch1.xhtml',
    'OEBPS/text/ch2.xhtml',
    'OEBPS/images/Cover.JPG',
    'OEBPS/images/My Pic.jpg',
    'OEBPS/images/encoded%20name.png',
    'OEBPS/style/book.css',
  ]);

  group('HrefResolver.resolve', () {
    test('resolves ../ relative to the chapter, not the book root', () {
      final r = resolver.resolve(
        '../images/Cover.JPG',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/images/Cover.JPG');
      expect(r.isExternal, isFalse);
      expect(r.isMissing, isFalse);
    });

    test('decodes percent-encoded names and finds the real file', () {
      final r = resolver.resolve(
        '../images/My%20Pic.jpg',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/images/My Pic.jpg');
    });

    test('matches case-insensitively and returns the actual case', () {
      final r = resolver.resolve(
        '../images/cover.jpg',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/images/Cover.JPG');
    });

    test('handles ./ and parent traversal', () {
      final r = resolver.resolve(
        './../../OEBPS/style/book.css',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/style/book.css');
    });

    test('keeps a fragment on the same document', () {
      final r = resolver.resolve('#part2', basePath: 'OEBPS/text/ch1.xhtml');
      expect(r.path, 'OEBPS/text/ch1.xhtml');
      expect(r.fragment, 'part2');
      expect(r.isExternal, isFalse);
    });

    test('splits fragment and query from a relative link', () {
      final r = resolver.resolve(
        'ch2.xhtml?v=1#note',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/text/ch2.xhtml');
      expect(r.fragment, 'note');
    });

    test('leaves http(s) and mailto links external', () {
      for (final href in [
        'https://example.com/a.png',
        'http://example.com/a.png',
        'mailto:me@example.com',
        '//example.com/a.png',
      ]) {
        expect(
          resolver.resolve(href, basePath: 'OEBPS/text/ch1.xhtml').isExternal,
          isTrue,
          reason: href,
        );
      }
    });

    test('root-relative paths resolve from the book root', () {
      final r = resolver.resolve(
        '/OEBPS/style/book.css',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/style/book.css');
    });

    test('reports a missing file without throwing', () {
      final r = resolver.resolve(
        '../images/nope.png',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, isNull);
      expect(r.isMissing, isTrue);
    });

    test('accepts backslashes used by some bad zip tools', () {
      final r = resolver.resolve(
        r'..\images\Cover.JPG',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/images/Cover.JPG');
    });

    test('finds an entry whose zip name is itself percent-encoded', () {
      final r = resolver.resolve(
        '../images/My Pic.jpg#ignored',
        basePath: 'OEBPS/text/ch1.xhtml',
      );
      expect(r.path, 'OEBPS/images/My Pic.jpg');
    });
  });

  group('HrefResolver.fileUri', () {
    test('builds an encoded absolute file URI', () {
      final uri = resolver.fileUri('/tmp/a b/c#d.xhtml');
      expect(uri, 'file:///tmp/a%20b/c%23d.xhtml');
    });
  });

  group('parseFileLink', () {
    test('splits and decodes the anchor of a file URI', () {
      final link = parseFileLink(
        'file:///tmp/Book%20One/ch%201.xhtml#caf%C3%A9',
      );
      expect(link, isNotNull);
      expect(link!.path, '/tmp/Book One/ch 1.xhtml');
      expect(link.fragment, 'café');
    });

    test('returns no fragment when the URI has no anchor', () {
      final link = parseFileLink('file:///tmp/book/ch1.xhtml');
      expect(link!.path, '/tmp/book/ch1.xhtml');
      expect(link.fragment, isNull);
    });

    test('ignores non-file links', () {
      expect(parseFileLink('https://example.com/a#b'), isNull);
      expect(parseFileLink('mailto:me@example.com'), isNull);
    });
  });
}
