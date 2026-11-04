import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/href_resolver.dart';
import 'package:folio/epub/chapter_html.dart';

void main() {
  final resolver = HrefResolver([
    'OEBPS/text/ch1.xhtml',
    'OEBPS/text/ch2.xhtml',
    'OEBPS/images/pic.jpg',
    'OEBPS/images/other.png',
    'OEBPS/style/book.css',
  ]);
  const root = '/cache/book';

  ChapterContent rewrite(String body) => rewriteChapterHtml(
    body,
    chapterPath: 'OEBPS/text/ch1.xhtml',
    bookRoot: root,
    resolver: resolver,
  );

  group('rewriteChapterHtml', () {
    test('rewrites img sources to absolute encoded file URIs', () {
      final c = rewrite('<p><img src="../images/pic.jpg" alt="a"/></p>');
      expect(
        c.bodyHtml,
        contains('src="file:///cache/book/OEBPS/images/pic.jpg"'),
      );
    });

    test('rewrites SVG-wrapped images (xlink:href and href)', () {
      final c = rewrite(
        '<svg><image xlink:href="../images/pic.jpg"/></svg>'
        '<svg><image href="../images/other.png"/></svg>',
      );
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/pic.jpg'));
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/other.png'));
    });

    test('rewrites stylesheet and anchor links, keeps external ones', () {
      final c = rewrite(
        '<a href="ch2.xhtml#s1">next</a>'
        '<a href="https://example.com">web</a>',
      );
      expect(
        c.bodyHtml,
        contains('href="file:///cache/book/OEBPS/text/ch2.xhtml#s1"'),
      );
      expect(c.bodyHtml, contains('href="https://example.com"'));
    });

    test('keeps the chapter language for hyphenation', () {
      final c = rewrite(
        '<html lang="it-IT" xml:lang="it-IT"><body><p>ciao</p></body></html>',
      );
      expect(c.language, 'it-IT');
    });

    test('collects head styles and separates the body', () {
      final c = rewrite(
        '<html><head><style>p{color:red}</style>'
        '<link rel="stylesheet" href="../style/book.css"/></head>'
        '<body class="x"><p>Hello</p></body></html>',
      );
      expect(c.bodyHtml, contains('<p>Hello</p>'));
      expect(c.bodyHtml, isNot(contains('<head>')));
      expect(c.headHtml, contains('p{color:red}'));
      expect(c.headHtml, contains('file:///cache/book/OEBPS/style/book.css'));
    });

    test('removes scripts and inline event handlers', () {
      final c = rewrite('<p onclick="alert(1)">x</p><script>alert(2)</script>');
      expect(c.bodyHtml, isNot(contains('script')));
      expect(c.bodyHtml, isNot(contains('onclick')));
    });

    test('drops a missing image without breaking the rest', () {
      final c = rewrite(
        '<p>before</p><img src="../images/gone.png" alt="missing"/>'
        '<p>after</p>',
      );
      expect(c.bodyHtml, contains('before'));
      expect(c.bodyHtml, contains('after'));
      expect(c.bodyHtml, isNot(contains('gone.png')));
      expect(c.missingResources, contains('OEBPS/images/gone.png'));
    });

    test('rewrites srcset candidates', () {
      final c = rewrite(
        '<img src="../images/pic.jpg" '
        'srcset="../images/pic.jpg 1x, ../images/other.png 2x"/>',
      );
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/other.png'));
    });

    test('resolves encoded and differently-cased image names', () {
      final c = rewrite('<img src="../IMAGES/PIC.jpg"/>');
      expect(
        c.bodyHtml,
        contains('src="file:///cache/book/OEBPS/images/pic.jpg"'),
      );
    });

    test('keeps aspect ratio information on SVG with a viewBox', () {
      final c = rewrite(
        '<svg viewBox="0 0 600 900"><image xlink:href="../images/pic.jpg" '
        'width="600" height="900"/></svg>',
      );
      expect(c.bodyHtml, contains('viewBox="0 0 600 900"'));
      expect(c.bodyHtml, contains('preserveAspectRatio="xMidYMid meet"'));
      expect(c.bodyHtml, contains('width="600"'));
    });

    test('drops a missing SVG image but keeps the surrounding SVG', () {
      final c = rewrite(
        '<svg viewBox="0 0 10 10"><image href="../images/gone.png"/></svg>',
      );
      expect(c.bodyHtml, contains('<svg'));
      expect(c.bodyHtml, isNot(contains('gone.png')));
      expect(c.bodyHtml, contains('data-folio-missing-image'));
      expect(c.missingResources, contains('OEBPS/images/gone.png'));
    });

    test('keeps data and external image URLs untouched', () {
      final c = rewrite(
        '<img src="data:image/png;base64,AAAA"/>'
        '<img src="https://example.com/pic.png"/>',
      );
      expect(c.bodyHtml, contains('src="data:image/png;base64,AAAA"'));
      expect(c.bodyHtml, contains('src="https://example.com/pic.png"'));
    });

    test('rewrites CSS urls in style attributes and style blocks', () {
      final c = rewrite(
        '<html><head><style>'
        '.x{background:url("../IMAGES/PIC.jpg")}</style></head>'
        '<body><p style="background-image:url(../images/other.png)">x</p>'
        '</body></html>',
      );
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/other.png'));
      expect(
        c.headHtml,
        contains('url("file:///cache/book/OEBPS/images/pic.jpg")'),
      );
    });

    test('hides a missing image but keeps the rest of the chapter', () {
      final c = rewrite('<img src="../images/gone.png"/>');
      expect(c.bodyHtml, contains('data-folio-missing-image'));
      expect(c.bodyHtml, isNot(contains('gone.png')));
    });
  });
}
