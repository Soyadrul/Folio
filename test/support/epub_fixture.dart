import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Helpers that build small, valid EPUB files in a temporary directory.
class EpubFixture {
  /// Writes an EPUB with [entries] (zip path -> file contents) to [dir].
  ///
  /// A value may be a [String] (UTF-8 text) or a `List<int>` (binary data such
  /// as a real image).
  static Future<File> write(
    Directory dir,
    Map<String, Object> entries, {
    String name = 'book.epub',
  }) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      final value = entry.value;
      if (value is String) {
        archive.addFile(ArchiveFile.string(entry.key, value));
      } else if (value is List<int>) {
        archive.addFile(ArchiveFile(entry.key, value.length, value));
      } else {
        throw ArgumentError.value(value, entry.key, 'Unsupported entry type');
      }
    }
    final bytes = ZipEncoder().encode(archive);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }
}

const containerXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0"
    xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
        media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const chapterOne = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>One</title><link rel="stylesheet" href="../style/book.css"/></head>
<body><h1 id="start">Chapter One</h1>
<p>Hello <em>world</em>.</p>
<p><img src="../images/pic.jpg" alt="pic"/></p>
</body></html>
''';

const chapterTwo = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Two</title></head>
<body><h1 id="sec">Chapter Two</h1><p>Second chapter.</p></body></html>
''';

const notesPage = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Notes</title></head>
<body><aside id="n1"><p>First note.</p></aside></body></html>
''';

const endnotesPage = '''
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Endnotes</title></head>
<body><aside id="e1"><p>An endnote.</p></aside></body></html>
''';

const bookCss = 'body { font-family: serif; }';

const epub2Opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0"
    unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>Old Book</dc:title>
    <dc:creator>Jane Doe</dc:creator>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="notes" href="text/notes.xhtml" media-type="application/xhtml+xml"/>
    <item id="endnotes" href="text/endnotes.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover-img" href="images/Cover.JPG" media-type="image/jpeg"/>
    <item id="css" href="style/book.css" media-type="text/css"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
    <itemref idref="notes" linear="no"/>
  </spine>
  <guide>
    <reference type="cover" href="text/ch1.xhtml" title="Cover"/>
  </guide>
</package>
''';

const epub2Ncx = '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1">
      <navLabel><text>One</text></navLabel>
      <content src="text/ch1.xhtml"/>
    </navPoint>
    <navPoint id="n2" playOrder="2">
      <navLabel><text>Two</text></navLabel>
      <content src="text/ch2.xhtml#sec"/>
    </navPoint>
  </navMap>
</ncx>
''';

Map<String, String> epub2Entries({
  String opf = epub2Opf,
  String ncx = epub2Ncx,
}) => {
  'META-INF/container.xml': containerXml,
  'OEBPS/content.opf': opf,
  'OEBPS/toc.ncx': ncx,
  'OEBPS/text/ch1.xhtml': chapterOne,
  'OEBPS/text/ch2.xhtml': chapterTwo,
  'OEBPS/text/notes.xhtml': notesPage,
  'OEBPS/text/endnotes.xhtml': endnotesPage,
  'OEBPS/style/book.css': bookCss,
  'OEBPS/images/Cover.JPG': 'cover-bytes',
  'OEBPS/images/pic.jpg': 'pic-bytes',
};

const epub3Opf = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0"
    unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>New Book</dc:title>
    <dc:creator>John Roe</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"
        properties="nav"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover" href="images/cover.png" media-type="image/png"
        properties="cover-image"/>
    <item id="css" href="style/book.css" media-type="text/css"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';

const epub3Nav = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"
      xmlns:epub="http://www.idpf.org/2007/ops">
<body>
  <nav epub:type="toc"><ol>
    <li><a href="text/ch1.xhtml">First</a></li>
    <li><a href="text/ch2.xhtml#sec">Second</a></li>
  </ol></nav>
</body>
</html>
''';

Map<String, String> epub3Entries({String opf = epub3Opf}) => {
  'META-INF/container.xml': containerXml,
  'OEBPS/content.opf': opf,
  'OEBPS/nav.xhtml': epub3Nav,
  'OEBPS/text/ch1.xhtml': chapterOne,
  'OEBPS/text/ch2.xhtml': chapterTwo,
  'OEBPS/style/book.css': bookCss,
  'OEBPS/images/cover.png': 'cover-bytes',
  'OEBPS/images/pic.jpg': 'pic-bytes',
};

/// A tiny in-memory check that the generated fixtures are valid zip files.
void sanityCheckFixture(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.files.isEmpty) {
    throw StateError('fixture is empty');
  }
  // ignore: avoid_print
  print(
    'fixture has ${archive.files.length} entries: '
    '${utf8.decode(archive.files.first.name.codeUnits, allowMalformed: true)}',
  );
}
