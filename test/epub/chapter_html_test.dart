import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/href_resolver.dart';
import 'package:folio/epub/chapter_html.dart';
import 'package:path/path.dart' as p;

void main() {
  final resolver = HrefResolver([
    'OEBPS/text/ch1.xhtml',
    'OEBPS/text/ch2.xhtml',
    'OEBPS/images/pic.jpg',
    'OEBPS/images/other.png',
    'OEBPS/images/sprite.svg',
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

    test('keeps data URLs but drops external image URLs', () {
      final c = rewrite(
        '<img src="data:image/png;base64,AAAA"/>'
        '<img src="https://example.com/pic.png"/>',
      );
      expect(c.bodyHtml, contains('src="data:image/png;base64,AAAA"'));
      expect(c.bodyHtml, isNot(contains('https://example.com/pic.png')));
    });

    test('drops frames, objects, forms, meta refresh and base', () {
      final c = rewrite(
        '<iframe srcdoc="<script>alert(1)</script>"></iframe>'
        '<iframe src="https://example.com/frame"></iframe>'
        '<object data="https://example.com/a.swf"></object>'
        '<embed src="https://example.com/a.swf">'
        '<form action="https://example.com/post">'
        '<button formaction="https://example.com/post">go</button>'
        '</form>'
        '<meta http-equiv="refresh" content="0;url=https://example.com">'
        '<base href="https://example.com/">'
        '<p>safe text</p>',
      );
      expect(c.bodyHtml, contains('safe text'));
      expect(c.bodyHtml, isNot(contains('iframe')));
      expect(c.bodyHtml, isNot(contains('srcdoc')));
      expect(c.bodyHtml, isNot(contains('object')));
      expect(c.bodyHtml, isNot(contains('embed')));
      expect(c.bodyHtml, isNot(contains('form')));
      expect(c.bodyHtml, isNot(contains('formaction')));
      expect(c.bodyHtml, isNot(contains('http-equiv')));
      expect(c.bodyHtml, isNot(contains('example.com')));
      expect(c.headHtml, isNot(contains('example.com')));
    });

    test('removes srcdoc, formaction and ping attributes', () {
      final c = rewrite(
        '<p srcdoc="x" formaction="https://example.com" ping="https://e.com">'
        'text</p>',
      );
      expect(c.bodyHtml, isNot(contains('srcdoc')));
      expect(c.bodyHtml, isNot(contains('formaction')));
      expect(c.bodyHtml, isNot(contains('ping')));
      expect(c.bodyHtml, contains('text'));
    });

    test('keeps local stylesheet links and drops external ones', () {
      final c = rewrite(
        '<html><head>'
        '<link rel="stylesheet" href="../style/book.css"/>'
        '<link rel="stylesheet" href="https://example.com/evil.css"/>'
        '<link rel="preload" href="../images/pic.jpg"/>'
        '</head><body><p>x</p></body></html>',
      );
      expect(c.headHtml, contains('file:///cache/book/OEBPS/style/book.css'));
      expect(c.headHtml, isNot(contains('example.com')));
      expect(c.headHtml, isNot(contains('preload')));
    });

    test('strips remote urls and imports from book CSS', () {
      final c = rewrite(
        '<html><head><style>'
        '@import url("https://example.com/evil.css");'
        '@import "https://example.com/evil2.css";'
        'body{background:url(https://example.com/tracker.png)}'
        '.x{background:url(data:image/png;base64,AAAA)}'
        '</style></head><body>'
        '<p style="background:url(https://example.com/track2.png)">x</p>'
        '</body></html>',
      );
      expect(c.headHtml, isNot(contains('https://example.com')));
      expect(c.bodyHtml, isNot(contains('https://example.com')));
      expect(c.headHtml, contains('data:image/png;base64,AAAA'));
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

    for (final tag in ['script', 'iframe', 'object', 'font', 'applet']) {
      test('a self-closing <$tag/> keeps the rest of the chapter', () {
        final c = rewrite(
          '<html><body><$tag src="a.js"/><p>Hello</p></body></html>',
        );
        expect(c.bodyHtml, contains('Hello'), reason: tag);
        expect(c.bodyHtml, isNot(contains('</html>')), reason: tag);
      });
    }

    test('HTML void elements stay void when self-closed', () {
      final c = rewrite(
        '<html><body><p>a<br/>b<img src="../images/pic.jpg"/></p></body></html>',
      );
      expect(c.bodyHtml, contains('<br>'));
      expect(c.bodyHtml, isNot(contains('<br></br>')));
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/pic.jpg'));
    });

    test('keeps a bare fragment on SVG elements', () {
      final c = rewrite(
        '<svg><defs><path id="p"/></defs><use href="#p"/></svg>'
        '<svg><textPath href="#t">x</textPath></svg>',
      );
      expect(c.bodyHtml, contains('href="#p"'));
      expect(c.bodyHtml, contains('href="#t"'));
      expect(
        c.bodyHtml,
        isNot(contains('file:///cache/book/OEBPS/text/ch1.xhtml#p')),
      );
    });

    test('keeps the fragment of a CSS url()', () {
      final c = rewrite(
        '<p style="fill: url(../images/sprite.svg#icon)">x</p>',
      );
      expect(
        c.bodyHtml,
        contains(
          'url(&quot;file:///cache/book/OEBPS/images/sprite.svg#icon&quot;)',
        ),
      );
    });

    test('srcset keeps data URIs and commas inside them', () {
      final c = rewrite(
        '<img srcset="data:image/png;base64,AAA 1x, ../images/pic.jpg 2x"/>',
      );
      expect(c.bodyHtml, contains('data:image/png;base64,AAA 1x'));
      expect(
        c.bodyHtml,
        contains('file:///cache/book/OEBPS/images/pic.jpg 2x'),
      );
    });

    test('srcset keeps descriptorless candidates after a comma', () {
      final c = rewrite(
        '<img srcset="../images/pic.jpg, ../images/other.png"/>',
      );
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/pic.jpg'));
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/other.png'));
    });

    test('a style element inside the body is scoped instead of leaking', () {
      final c = rewrite(
        '<html><body><style>p{color:red}</style><p>Hi</p></body></html>',
      );
      expect(c.bodyHtml, isNot(contains('<style>')));
      expect(c.bookStyleHtml, contains('p{color:red}'));
      expect(c.headHtml, contains('p{color:red}'));
    });

    test('a stylesheet link inside the body is moved to the head', () {
      final c = rewrite(
        '<html><body><link rel="stylesheet" href="../style/book.css"/>'
        '<p>Hi</p></body></html>',
      );
      expect(c.bodyHtml, isNot(contains('<link')));
      expect(c.headHtml, contains('style/book.css'));
    });

    test('form and object wrappers are removed but their text survives', () {
      final c = rewrite(
        '<html><body><form action="x"><p>Visible</p></form>'
        '<object data="x"><p>Fallback</p></object></body></html>',
      );
      expect(c.bodyHtml, contains('Visible'));
      expect(c.bodyHtml, contains('Fallback'));
      expect(c.bodyHtml, isNot(contains('<form')));
      expect(c.bodyHtml, isNot(contains('<object')));
    });
  });

  group('splitSrcsetCandidates', () {
    test('does not split a data URI at its comma', () {
      expect(splitSrcsetCandidates('data:image/png;base64,AAA 1x, b.png 2x'), [
        'data:image/png;base64,AAA 1x',
        'b.png 2x',
      ]);
    });

    test('splits descriptorless candidates', () {
      expect(splitSrcsetCandidates('a.png, b.png'), ['a.png', 'b.png']);
    });

    test('splits candidates with descriptors', () {
      expect(splitSrcsetCandidates('a.png 1x, b.png 2x'), [
        'a.png 1x',
        'b.png 2x',
      ]);
    });

    test('does not split a comma inside descriptor parentheses', () {
      expect(splitSrcsetCandidates('a.png (max-width: 600px), b.png 2x'), [
        'a.png (max-width: 600px)',
        'b.png 2x',
      ]);
    });
  });

  group('XHTML self-closing tags', () {
    test('expands an empty anchor instead of swallowing the chapter', () {
      final c = rewrite('<p>before</p><a id="marker"/><p>after</p>');
      expect(c.bodyHtml, contains('before'));
      expect(c.bodyHtml, contains('after'));
      final anchor = RegExp(
        r'<a[^>]*id="marker"[^>]*>(.*?)</a>',
        dotAll: true,
      ).firstMatch(c.bodyHtml);
      expect(anchor, isNotNull);
      expect(anchor!.group(1), isEmpty);
    });

    test('does not let a self-closing title eat the body', () {
      final c = rewrite(
        '<html><head><title/></head><body><p>visible</p></body></html>',
      );
      expect(c.bodyHtml, contains('visible'));
    });

    test('leaves void tags self-closing', () {
      final c = rewrite('<p>a<br/>b</p><img src="../images/pic.jpg"/>');
      expect(c.bodyHtml, contains('<br>'));
      expect(c.bodyHtml, contains('file:///cache/book/OEBPS/images/pic.jpg'));
    });
  });

  group('fragment links', () {
    test('keeps a same-chapter fragment on the page', () {
      final c = rewrite('<a href="ch1.xhtml#note1">note</a>');
      expect(c.bodyHtml, contains('href="#note1"'));
      expect(
        c.bodyHtml,
        isNot(contains('file:///cache/book/OEBPS/text/ch1.xhtml')),
      );
    });

    test('keeps a bare #fragment unchanged', () {
      final c = rewrite('<a href="#note2">note</a>');
      expect(c.bodyHtml, contains('href="#note2"'));
    });

    test('rewrites a cross-chapter link with its fragment', () {
      final c = rewrite('<a href="ch2.xhtml#sec">next</a>');
      expect(
        c.bodyHtml,
        contains('href="file:///cache/book/OEBPS/text/ch2.xhtml#sec"'),
      );
    });
  });

  group('scopeBookCss', () {
    const scope = '.folio-chapter[data-folio-index="2"]';

    test('prefixes an element selector with the chapter scope', () {
      expect(
        scopeBookCss('p { color: red; }', scope),
        '$scope p{ color: red; }',
      );
    });

    test('turns body and html selectors into the chapter scope', () {
      expect(
        scopeBookCss('body { color: red }', scope),
        '$scope{ color: red }',
      );
      expect(
        scopeBookCss('html body p { margin: 0 }', scope),
        '$scope p{ margin: 0 }',
      );
      expect(
        scopeBookCss('body > .x { color: red }', scope),
        '$scope .x{ color: red }',
      );
      expect(
        scopeBookCss('body .note { color: red }', scope),
        '$scope .note{ color: red }',
      );
      expect(
        scopeBookCss('body.note { color: red }', scope),
        '$scope.note{ color: red }',
      );
    });

    test('scopes every rule in a selector list', () {
      final scoped = scopeBookCss('p, .note { color: red }', scope);
      expect(scoped, contains('$scope p'));
      expect(scoped, contains('$scope .note'));
    });

    test('scopes rules inside @media but leaves @font-face alone', () {
      final scoped = scopeBookCss(
        '@media (min-width: 1px) { p { color: red } }'
        '@font-face { font-family: X; src: url(font.woff); }',
        scope,
      );
      expect(scoped, contains('@media (min-width: 1px){'));
      expect(scoped, contains('$scope p{ color: red }'));
      expect(scoped, contains('@font-face{ font-family: X;'));
    });

    test('keeps comments and does not touch strings containing braces', () {
      final scoped = scopeBookCss(
        '/* a } comment */ p::before { content: "}" }',
        scope,
      );
      expect(scoped, contains('/* a } comment */'));
      expect(scoped, contains('$scope p::before{ content: "}" }'));
    });
  });

  group('prepareChapterStyles', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('folio-styles-');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('inlines a linked stylesheet and scopes it to the chapter', () async {
      final styleDir = Directory(p.join(tmp.path, 'OEBPS', 'style'))
        ..createSync(recursive: true);
      final cssFile = File(p.join(styleDir.path, 'book.css'))
        ..writeAsStringSync(
          '@import url("other.css");'
          'body { font-family: serif; }'
          'p.note { color: red; }',
        );
      final chapterFile = File(p.join(tmp.path, 'OEBPS', 'text', 'ch1.xhtml'))
        ..createSync(recursive: true);

      final content = ChapterContent(
        bodyHtml: '<p class="note">x</p>',
        headHtml:
            '<link rel="stylesheet" href="${Uri.file(cssFile.path)}"/>'
            '<style>.local { color: blue }</style>',
        missingResources: [],
      );

      final prepared = await prepareChapterStyles(
        content,
        chapterIndex: 2,
        chapterPath: 'OEBPS/text/ch1.xhtml',
        bookRoot: tmp.path,
        resolver: HrefResolver([
          'OEBPS/text/ch1.xhtml',
          'OEBPS/style/book.css',
          'OEBPS/style/other.css',
        ]),
      );

      expect(chapterFile.existsSync(), isTrue);
      expect(
        prepared.webStyleHtml,
        contains('.folio-chapter[data-folio-index="2"]'),
      );
      expect(
        prepared.webStyleHtml,
        contains('.folio-chapter[data-folio-index="2"] p.note'),
      );
      expect(prepared.webStyleHtml, isNot(contains('@import')));
      expect(prepared.webStyleHtml, isNot(contains(');')));
      expect(prepared.webStyleHtml, contains('font-family: serif'));
      expect(
        prepared.webStyleHtml,
        contains('.folio-chapter[data-folio-index="2"] .local'),
      );
    });

    test('keeps book CSS for the fallback without scope prefixes', () async {
      const content = ChapterContent(
        bodyHtml: '<p>x</p>',
        headHtml: '<style>p { color: red }</style>',
        missingResources: [],
      );

      final prepared = await prepareChapterStyles(
        content,
        chapterIndex: 0,
        chapterPath: 'OEBPS/text/ch1.xhtml',
        bookRoot: tmp.path,
        resolver: resolver,
      );

      expect(prepared.bookStyleHtml, contains('p { color: red }'));
      expect(
        prepared.bookStyleHtml,
        isNot(contains('.folio-chapter[data-folio-index="0"]')),
      );
    });

    test('survives a missing linked stylesheet', () async {
      final content = ChapterContent(
        bodyHtml: '<p>x</p>',
        headHtml:
            '<link rel="stylesheet" href="file://${tmp.path}/OEBPS/style/gone.css"/>',
        missingResources: [],
      );

      final prepared = await prepareChapterStyles(
        content,
        chapterIndex: 0,
        chapterPath: 'OEBPS/text/ch1.xhtml',
        bookRoot: tmp.path,
        resolver: resolver,
      );

      expect(prepared.bodyHtml, contains('<p>x</p>'));
      expect(prepared.webStyleHtml, isEmpty);
    });
  });
}
