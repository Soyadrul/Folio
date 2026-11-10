import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'chapter_html.dart';
import 'epub_metadata.dart';
import 'epub_text.dart';
import 'href_resolver.dart';

export 'epub_text.dart' show decodeEpubText;

/// Manifest `properties` is whitespace-separated by specification, but books
/// use tabs and newlines too. Splitting on a single space made `nav` and
/// `cover-image` disappear.
Set<String> epubManifestProperties(String raw) {
  return raw
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .toSet();
}

/// Whether [path] names an image the reader can display.
bool isEpubImagePath(String path) => EpubLoader.isEpubImagePath(path);

/// Chooses a chapter title from its markup.
///
/// `<title>` usually repeats the book title, so the first heading wins.
/// The regex requires whitespace or `>` after `title`, which stops
/// `<titlepage>` from matching.
String chapterTitleFromHtml(String html, {String? bookTitle}) {
  final heading = RegExp(
    r'<h[12](?:\s[^>]*)?>(.*?)</h[12]>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (heading != null && heading.trim().isNotEmpty) {
    return _plainText(heading);
  }
  final title = RegExp(
    r'<title(?:\s[^>]*)?>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html)?.group(1);
  if (title != null && title.trim().isNotEmpty) {
    final plain = _plainText(title);
    if (bookTitle == null || plain != bookTitle.trim()) return plain;
  }
  return '';
}

String _plainText(String html) => (html_parser.parseFragment(html).text ?? '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A user-facing problem while opening an EPUB.
class EpubException implements Exception {
  EpubException(this.message);
  final String message;

  @override
  String toString() => 'EpubException: $message';
}

/// One item of the EPUB spine, in reading order.
class EpubChapter {
  const EpubChapter({
    required this.index,
    required this.href,
    required this.relPath,
    required this.path,
    required this.title,
    required this.byteSize,
    required this.mediaType,
  });

  final int index;

  /// The raw href from the OPF manifest.
  final String href;

  /// Path relative to the extracted book root, with real file case.
  final String relPath;

  /// Absolute path on disk.
  final String path;

  final String title;
  final int byteSize;
  final String mediaType;
}

/// One entry of the table of contents.
class EpubTocEntry {
  const EpubTocEntry({
    required this.title,
    required this.chapterIndex,
    this.fragment,
    this.level = 0,
  });

  final String title;
  final int chapterIndex;
  final String? fragment;
  final int level;
}

/// A parsed, extracted EPUB book.
///
/// Holds only metadata and paths; chapter text is read on demand so a large
/// book never sits in memory as a whole.
class EpubDocument {
  EpubDocument({
    required this.filePath,
    required this.cacheDir,
    required this.opfPath,
    required this.title,
    required this.author,
    required this.chapters,
    required this.toc,
    required this.coverImagePath,
    required this.resolver,
    required this.totalChapterBytes,
    this.auxiliaryDocuments = const [],
  });

  final String filePath;

  /// Folder containing the extracted book.
  final String cacheDir;

  /// Absolute path to the OPF file inside [cacheDir].
  final String opfPath;

  final String title;
  final String author;

  /// Documents in the spine's reading order (next/previous flow).
  final List<EpubChapter> chapters;

  /// Documents that are not part of the reading flow but can be opened by a
  /// link or a table-of-contents entry: `linear="no"` spine items, footnote
  /// pages and other manifest documents outside the spine.
  final List<EpubChapter> auxiliaryDocuments;

  final List<EpubTocEntry> toc;
  final String? coverImagePath;
  final HrefResolver resolver;
  final int totalChapterBytes;

  String get rootDir => cacheDir;

  /// Every openable document, in index order.
  ///
  /// Spine indexes come first and auxiliary indexes follow, so an
  /// [EpubChapter.index] is always the position in this list.
  List<EpubChapter> get allDocuments => [...chapters, ...auxiliaryDocuments];

  int get documentCount => chapters.length + auxiliaryDocuments.length;

  /// Returns the document with the global [index].
  EpubChapter? documentAt(int index) {
    if (index < 0) return null;
    if (index < chapters.length) return chapters[index];
    final auxiliary = index - chapters.length;
    if (auxiliary < auxiliaryDocuments.length) {
      return auxiliaryDocuments[auxiliary];
    }
    return null;
  }

  /// Index of the next document in the reading flow, or null at the end.
  int? nextReadingIndex(int index) {
    final position = chapters.indexWhere((chapter) => chapter.index == index);
    if (position < 0 || position + 1 >= chapters.length) return null;
    return chapters[position + 1].index;
  }

  /// Index of the previous document in the reading flow, or null at the start.
  int? previousReadingIndex(int index) {
    final position = chapters.indexWhere((chapter) => chapter.index == index);
    if (position <= 0) return null;
    return chapters[position - 1].index;
  }

  /// One-based position in the reading flow, or null for an auxiliary page.
  int? readingOrderPosition(int index) {
    final position = chapters.indexWhere((chapter) => chapter.index == index);
    return position < 0 ? null : position + 1;
  }

  /// Reads and rewrites [chapter] for the WebView.
  Future<ChapterContent> loadChapterContent(EpubChapter chapter) async {
    final bytes = await File(chapter.path).readAsBytes();
    // Some older books are not valid UTF-8; replacement characters are much
    // better than refusing to open the chapter.
    final raw = decodeEpubText(bytes);
    final content = rewriteChapterHtml(
      raw,
      chapterPath: chapter.relPath,
      bookRoot: rootDir,
      resolver: resolver,
    );
    return prepareChapterStyles(
      content,
      chapterIndex: chapter.index,
      chapterPath: chapter.relPath,
      bookRoot: rootDir,
      resolver: resolver,
    );
  }
}

/// Extracts EPUBs into a cache and parses their package documents.
///
/// The cache key is the absolute file path; a sidecar file records size and
/// modification time, so a changed book is extracted again.
class EpubLoader {
  EpubLoader({Directory? cacheRoot}) : _cacheRoot = cacheRoot;

  final Directory? _cacheRoot;
  Future<Directory>? _resolvedRoot;

  /// Loads currently running in this process, keyed by cache root and book.
  ///
  /// The cover service and the reader each used to own their own loader; both
  /// could extract (and delete) the same folder at the same time. Sharing the
  /// future also means concurrent callers get the same parsed document.
  static final Map<String, Future<EpubDocument>> _inFlight = {};
  static int _tempCounter = 0;

  Future<Directory> _root() async {
    final injected = _cacheRoot;
    if (injected != null) return injected;
    return _resolvedRoot ??= () async {
      final base = await getApplicationCacheDirectory();
      return Directory(p.join(base.path, 'folio_epub'));
    }();
  }

  /// Opens (and if needed extracts) the EPUB at [filePath].
  Future<EpubDocument> load(String filePath) async {
    final absolute = p.normalize(p.absolute(filePath));
    final root = await _root();
    await root.create(recursive: true);
    final flightKey = '${root.path}|$absolute';
    final running = _inFlight[flightKey];
    if (running != null) return running;

    final future = _load(absolute, root);
    _inFlight[flightKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(flightKey);
    }
  }

  Future<EpubDocument> _load(String absolute, Directory root) async {
    final file = File(absolute);
    if (!await file.exists()) {
      throw EpubException('The book file is missing: $absolute');
    }

    late final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException catch (e) {
      throw EpubException('Cannot read the book file: ${e.message}');
    }

    final key = sha1.convert(utf8.encode(absolute)).toString();
    final dir = Directory(p.join(root.path, 'epub_${key.substring(0, 16)}'));
    final marker = File(p.join(dir.path, '.folio-cache.json'));

    var reusable = false;
    if (await dir.exists() && await marker.exists()) {
      try {
        final data = jsonDecode(await _readText(marker));
        reusable =
            data is Map &&
            data['size'] == stat.size &&
            data['mtime'] == stat.modified.millisecondsSinceEpoch &&
            data['path'] == absolute &&
            await File(p.join(dir.path, 'META-INF', 'container.xml')).exists();
      } catch (_) {
        reusable = false;
      }
    }

    if (!reusable) {
      await _cleanupStaleExtractions(dir);
      await _extractAtomically(file, dir, absolute, stat);
    }

    final container = await _findAndParseContainer(dir);
    return _parse(
      filePath: absolute,
      cacheDir: dir.path,
      opfPath: container.opfPath,
      files: container.files,
    );
  }

  /// Extracts into a sibling folder and renames it into place, so a crash or a
  /// second loader never sees a half-written book with a valid cache marker.
  Future<void> _extractAtomically(
    File file,
    Directory dir,
    String absolute,
    FileStat stat,
  ) async {
    final temp = Directory(
      '${dir.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_tempCounter++}',
    );
    try {
      await temp.create(recursive: true);
      await _extract(file, temp);
      await File(p.join(temp.path, '.folio-cache.json')).writeAsString(
        jsonEncode({
          'path': absolute,
          'size': stat.size,
          'mtime': stat.modified.millisecondsSinceEpoch,
        }),
        flush: true,
      );
      if (await dir.exists()) await dir.delete(recursive: true);
      await temp.rename(dir.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete(recursive: true);
      rethrow;
    }
  }

  /// Removes temporary folders left behind by an interrupted extraction.
  Future<void> _cleanupStaleExtractions(Directory dir) async {
    final parent = Directory(p.dirname(dir.path));
    if (!await parent.exists()) return;
    final prefix = '${p.basename(dir.path)}.tmp-';
    try {
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (!p.basename(entity.path).startsWith(prefix)) continue;
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // Another process may still be using it; leave it alone.
        }
      }
    } on FileSystemException {
      // A cache folder we cannot list is not fatal for opening this book.
    }
  }

  /// Removes every extracted book from the cache.
  Future<void> clearCache() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<Uint8List> _readEpubBytes(File file) async {
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw EpubException('Cannot read the book: ${e.message}');
    }
  }

  static const _maxExtractEntries = 20000;
  static const _maxExtractBytes = 2 * 1024 * 1024 * 1024;

  Future<void> _extract(File file, Directory target) async {
    final bytes = await _readEpubBytes(file);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw EpubException('This book is damaged or is not an EPUB: $e');
    }

    var extracted = 0;
    var entries = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      entries++;
      if (entries > _maxExtractEntries) {
        throw EpubException(
          'This book contains too many files to open safely.',
        );
      }
      extracted += entry.size;
      if (extracted > _maxExtractBytes) {
        throw EpubException('This book is too large to extract safely.');
      }
      final safe = _safeEntryPath(entry.name);
      if (safe == null) continue;
      final output = File(p.joinAll([target.path, ...safe.split('/')]));
      await output.parent.create(recursive: true);
      await output.writeAsBytes(entry.readBytes() ?? const [], flush: false);
    }
  }

  /// Returns a normalised archive-relative path, or null for unsafe entries.
  static String? _safeEntryPath(String rawName) {
    var name = rawName.replaceAll('\\', '/');
    if (name.isEmpty) return null;
    if (name.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(name)) {
      return null;
    }
    name = p.url.normalize(name);
    if (name == '.' || name == '..' || name.startsWith('../')) return null;
    if (name.split('/').any((segment) => segment == '..')) return null;
    return name;
  }

  Future<List<String>> _listFiles(Directory dir) async {
    final files = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
      if (rel == '.folio-cache.json') continue;
      files.add(rel);
    }
    return files;
  }

  Future<({String opfPath, List<String> files})> _findAndParseContainer(
    Directory dir,
  ) async {
    final files = await _listFiles(dir);
    final resolver = HrefResolver(files);
    final found = resolver.resolve(
      'META-INF/container.xml',
      basePath: 'container-root',
    );
    if (found.path == null) {
      throw EpubException(
        'This EPUB has no META-INF/container.xml (the book is damaged).',
      );
    }
    final containerFile = File(
      p.joinAll([dir.path, ...found.path!.split('/')]),
    );
    final XmlDocument container;
    try {
      container = XmlDocument.parse(await _readText(containerFile));
    } catch (e) {
      throw EpubException('META-INF/container.xml is not valid XML: $e');
    }
    XmlElement? rootfile;
    for (final element in container.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'rootfile') {
        rootfile = element;
        break;
      }
    }
    final fullPath = _attribute(rootfile, 'full-path');
    if (fullPath == null || fullPath.isEmpty) {
      throw EpubException(
        'META-INF/container.xml does not point to a package document.',
      );
    }
    final opf = resolver.resolve(fullPath, basePath: '.');
    if (opf.path == null) {
      throw EpubException('The EPUB package document is missing ($fullPath).');
    }
    return (
      opfPath: p.joinAll([dir.path, ...opf.path!.split('/')]),
      files: files,
    );
  }

  Future<EpubDocument> _parse({
    required String filePath,
    required String cacheDir,
    required String opfPath,
    required List<String> files,
  }) async {
    final resolver = HrefResolver(files);
    final opfRel = p.relative(opfPath, from: cacheDir).replaceAll('\\', '/');

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(await _readText(File(opfPath)));
    } catch (e) {
      throw EpubException('The EPUB package document is not valid XML: $e');
    }

    final package = _firstElement(opf, 'package');
    if (package == null) {
      throw EpubException('The EPUB package document has no <package>.');
    }
    final metadata = _firstElement(package, 'metadata');
    final manifest = _firstElement(package, 'manifest');
    final spine = _firstElement(package, 'spine');
    if (manifest == null || spine == null) {
      throw EpubException('The EPUB package is missing its manifest or spine.');
    }

    final bookMetadata = readPackageMetadata(
      package,
      fallbackTitle: p.basenameWithoutExtension(filePath),
    );
    final title = bookMetadata.title;
    final author = bookMetadata.author;

    final manifestItems = <String, _ManifestItem>{};
    for (final item in _allElements(manifest, 'item')) {
      final id = _attribute(item, 'id');
      final href = _attribute(item, 'href');
      if (id == null || href == null || href.isEmpty) continue;
      manifestItems[id] = _ManifestItem(
        id: id,
        href: href,
        mediaType: (_attribute(item, 'media-type') ?? '').toLowerCase(),
        properties: (_attribute(item, 'properties') ?? '').toLowerCase(),
      );
    }

    // Every spine entry is kept: `linear="no"` items and documents outside the
    // spine are still reachable through links and the table of contents.
    final spineDocuments =
        <
          ({
            _ManifestItem item,
            String relPath,
            String absolute,
            String href,
            bool linear,
          })
        >[];
    final seenSpinePaths = <String>{};
    for (final itemref in _allElements(spine, 'itemref')) {
      final idref = _attribute(itemref, 'idref');
      if (idref == null) continue;
      final item = manifestItems[idref];
      if (item == null) continue;
      final resolved = resolver.resolve(item.href, basePath: opfRel);
      if (resolved.path == null) continue;
      if (!seenSpinePaths.add(resolved.path!)) continue;
      final absolute = p.joinAll([cacheDir, ...resolved.path!.split('/')]);
      if (!await File(absolute).exists()) continue;
      // The EPUB 3 navigation document stays in the reading flow even when
      // the publisher marks it non-linear: readers expect to find the book's
      // index page where the publisher placed it.
      final isNavigation = epubManifestProperties(
        item.properties,
      ).contains('nav');
      final linear =
          isNavigation ||
          (_attribute(itemref, 'linear') ?? '').toLowerCase() != 'no';
      spineDocuments.add((
        item: item,
        relPath: resolved.path!,
        absolute: absolute,
        href: item.href,
        linear: linear,
      ));
    }

    final orderedDocuments =
        <
          ({
            ({
              _ManifestItem item,
              String relPath,
              String absolute,
              String href,
              bool linear,
            })
            document,
            bool auxiliary,
          })
        >[
          for (final document in spineDocuments)
            if (document.linear) (document: document, auxiliary: false),
          for (final document in spineDocuments)
            if (!document.linear) (document: document, auxiliary: true),
        ];
    final knownPaths = spineDocuments.map((d) => d.relPath).toSet();
    for (final item in manifestItems.values) {
      if (!_isHtmlDocument(item.mediaType, item.href)) continue;
      final resolved = resolver.resolve(item.href, basePath: opfRel);
      if (resolved.path == null || !knownPaths.add(resolved.path!)) continue;
      final absolute = p.joinAll([cacheDir, ...resolved.path!.split('/')]);
      if (!await File(absolute).exists()) continue;
      orderedDocuments.add((
        document: (
          item: item,
          relPath: resolved.path!,
          absolute: absolute,
          href: item.href,
          linear: false,
        ),
        auxiliary: true,
      ));
    }

    final chapters = <EpubChapter>[];
    final auxiliaryDocuments = <EpubChapter>[];
    var nextIndex = 0;
    for (final entry in orderedDocuments) {
      final document = entry.document;
      final stat = await File(document.absolute).stat();
      final chapter = EpubChapter(
        index: nextIndex++,
        href: document.href,
        relPath: document.relPath,
        path: document.absolute,
        title: '',
        byteSize: stat.size,
        mediaType: document.item.mediaType,
      );
      if (entry.auxiliary) {
        auxiliaryDocuments.add(chapter);
      } else {
        chapters.add(chapter);
      }
    }

    if (chapters.isEmpty) {
      throw EpubException(
        'This EPUB has no readable chapters (the spine is empty).',
      );
    }

    final openableDocuments = [...chapters, ...auxiliaryDocuments];
    final toc = await _parseToc(
      metadata: metadata,
      manifestItems: manifestItems,
      chapters: openableDocuments,
      cacheDir: cacheDir,
      opfRel: opfRel,
      resolver: resolver,
    );

    final tocTitles = <int, String>{};
    for (final entry in toc) {
      if (entry.title.trim().isEmpty) continue;
      tocTitles.putIfAbsent(entry.chapterIndex, () => entry.title);
    }

    Future<EpubChapter> withTitle(EpubChapter chapter) async {
      final tocTitle = tocTitles[chapter.index] ?? '';
      final titleFromChapter = tocTitle.isEmpty
          ? await _chapterTitle(chapter.path, bookTitle: title)
          : tocTitle;
      final inReadingFlow = chapters.any((c) => c.index == chapter.index);
      final fallback = inReadingFlow
          ? 'Chapter ${chapter.index + 1}'
          : p.basenameWithoutExtension(chapter.relPath);
      return EpubChapter(
        index: chapter.index,
        href: chapter.href,
        relPath: chapter.relPath,
        path: chapter.path,
        title: titleFromChapter.isEmpty ? fallback : titleFromChapter,
        byteSize: chapter.byteSize,
        mediaType: chapter.mediaType,
      );
    }

    final titledChapters = <EpubChapter>[];
    for (final chapter in chapters) {
      titledChapters.add(await withTitle(chapter));
    }
    final titledAuxiliary = <EpubChapter>[];
    for (final chapter in auxiliaryDocuments) {
      titledAuxiliary.add(await withTitle(chapter));
    }

    final cover = await _resolveCover(
      metadata: metadata,
      manifestItems: manifestItems,
      tocId: _attribute(spine, 'toc'),
      chapters: titledChapters,
      cacheDir: cacheDir,
      opfRel: opfRel,
      resolver: resolver,
      package: package,
    );

    return EpubDocument(
      filePath: filePath,
      cacheDir: cacheDir,
      opfPath: opfPath,
      title: title,
      author: author,
      chapters: titledChapters,
      auxiliaryDocuments: titledAuxiliary,
      toc: toc,
      coverImagePath: cover,
      resolver: resolver,
      totalChapterBytes: titledChapters.fold(
        0,
        (sum, chapter) => sum + chapter.byteSize,
      ),
    );
  }

  Future<List<EpubTocEntry>> _parseToc({
    required XmlElement? metadata,
    required Map<String, _ManifestItem> manifestItems,
    required List<EpubChapter> chapters,
    required String cacheDir,
    required String opfRel,
    required HrefResolver resolver,
  }) async {
    final entries = <EpubTocEntry>[];
    final indexByPath = {
      for (final chapter in chapters) chapter.relPath: chapter.index,
    };

    void add(String title, String href, String base, {int level = 0}) {
      final resolved = resolver.resolve(href, basePath: base);
      if (resolved.path == null) return;
      final index = indexByPath[resolved.path];
      if (index == null) return;
      entries.add(
        EpubTocEntry(
          title: title.trim(),
          chapterIndex: index,
          fragment: resolved.fragment,
          level: level,
        ),
      );
    }

    // EPUB 3 navigation document.
    final navItem = manifestItems.values
        .where(
          (item) => epubManifestProperties(item.properties).contains('nav'),
        )
        .firstOrNull;
    if (navItem != null) {
      final resolved = resolver.resolve(navItem.href, basePath: opfRel);
      if (resolved.path != null) {
        final file = File(p.joinAll([cacheDir, ...resolved.path!.split('/')]));
        if (await file.exists()) {
          final navBase = resolved.path!;
          final before = entries.length;
          try {
            final document = html_parser.parse(await _readText(file));
            final nav = document
                .querySelectorAll('nav')
                .where((n) => _hasTocType(n))
                .firstOrNull;
            final scope = nav ?? document.body;
            if (scope != null) {
              for (final anchor in scope.querySelectorAll('a')) {
                final href = anchor.attributes['href'];
                if (href == null) continue;
                var level = 0;
                var parent = anchor.parent;
                while (parent != null && parent != scope) {
                  if (parent.localName?.toLowerCase() == 'ol') level++;
                  parent = parent.parent;
                }
                add(
                  anchor.text,
                  href,
                  navBase,
                  level: level > 0 ? level - 1 : 0,
                );
              }
            }
          } catch (_) {
            // A damaged or badly encoded navigation document must not make the
            // book unreadable. Discard a partial result and use the NCX.
            entries.removeRange(before, entries.length);
          }
        }
      }
    }

    // EPUB 2 NCX (also used as a fallback when the NAV is unusable).
    if (entries.isEmpty) {
      final ncx = manifestItems.values
          .where(
            (item) =>
                item.mediaType.contains('dtbncx') ||
                item.href.toLowerCase().endsWith('.ncx'),
          )
          .firstOrNull;
      if (ncx != null) {
        final resolved = resolver.resolve(ncx.href, basePath: opfRel);
        if (resolved.path != null) {
          final file = File(
            p.joinAll([cacheDir, ...resolved.path!.split('/')]),
          );
          if (await file.exists()) {
            try {
              final document = XmlDocument.parse(await _readText(file));
              for (final point
                  in document.descendants.whereType<XmlElement>().where(
                    (e) => e.name.local == 'navPoint',
                  )) {
                final label = _firstElement(point, 'navLabel');
                final text = _textOf(_firstElement(label, 'text')).trim();
                final content = _firstElement(point, 'content');
                final src = _attribute(content, 'src');
                if (src == null || text.isEmpty) continue;
                final before = entries.length;
                add(text, src, resolved.path!);
                if (entries.length > before) {
                  // `_ancestorNames` already excludes the point itself, so a
                  // top-level navPoint has no ancestors (level 0) and its
                  // children have one (level 1).
                  final level = _ancestorNames(point, 'navPoint').length;
                  entries[entries.length - 1] = EpubTocEntry(
                    title: entries.last.title,
                    chapterIndex: entries.last.chapterIndex,
                    fragment: entries.last.fragment,
                    level: level,
                  );
                }
              }
            } catch (_) {
              // A broken NCX must not prevent reading; the spine still works.
            }
          }
        }
      }
    }

    return entries;
  }

  /// Reads an EPUB text file even when a few bytes are invalid.
  ///
  /// Old books regularly contain a stray Windows-1252 byte in the OPF, nav or
  /// NCX, and some use a UTF-16 BOM. Replacement characters are always better
  /// than failing to open the whole book.
  static Future<String> _readText(File file) async {
    return decodeEpubText(await file.readAsBytes());
  }

  Future<String> _chapterTitle(String path, {String? bookTitle}) async {
    try {
      final file = File(path);
      final length = await file.length();
      final bytes = await file
          .openRead(0, length > 8192 ? 8192 : length)
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      final title = chapterTitleFromHtml(
        decodeEpubText(bytes),
        bookTitle: bookTitle,
      );
      if (title.isNotEmpty) return title;
    } catch (_) {
      // Fall through to the generic title.
    }
    return '';
  }

  Future<String?> _resolveCover({
    required XmlElement? metadata,
    required Map<String, _ManifestItem> manifestItems,
    required String? tocId,
    required List<EpubChapter> chapters,
    required String cacheDir,
    required String opfRel,
    required HrefResolver resolver,
    required XmlElement package,
  }) async {
    String? existing(String? relPath) {
      if (relPath == null) return null;
      final file = File(p.joinAll([cacheDir, ...relPath.split('/')]));
      return file.existsSync() ? file.path : null;
    }

    // 1. EPUB 3 cover-image manifest property.
    for (final item in manifestItems.values) {
      if (!epubManifestProperties(item.properties).contains('cover-image')) {
        continue;
      }
      final resolved = resolver.resolve(item.href, basePath: opfRel);
      if (resolved.path == null ||
          !EpubLoader.isEpubImagePath(resolved.path!)) {
        continue;
      }
      final path = existing(resolved.path);
      if (path != null) return path;
    }

    // 2. EPUB 2 <meta name="cover" content="manifest-id">.
    for (final meta in _allElements(metadata, 'meta')) {
      if ((_attribute(meta, 'name') ?? '').toLowerCase() != 'cover') continue;
      final id = _attribute(meta, 'content');
      final item = id == null ? null : manifestItems[id];
      if (item == null) continue;
      final resolved = resolver.resolve(item.href, basePath: opfRel);
      if (resolved.path == null ||
          !EpubLoader.isEpubImagePath(resolved.path!)) {
        continue;
      }
      final path = existing(resolved.path);
      if (path != null) return path;
    }

    // 3. guide reference of type "cover" (image or cover chapter).
    for (final reference in _allElements(package, 'reference')) {
      if ((_attribute(reference, 'type') ?? '').toLowerCase() != 'cover') {
        continue;
      }
      final href = _attribute(reference, 'href');
      if (href == null) continue;
      final resolved = resolver.resolve(href, basePath: opfRel);
      if (resolved.path == null) continue;
      if (EpubLoader.isEpubImagePath(resolved.path!)) {
        final path = existing(resolved.path);
        if (path != null) return path;
      } else {
        final image = await _firstImageIn(resolved.path!, cacheDir, resolver);
        final path = existing(image);
        if (path != null) return path;
      }
    }

    // 4. First image in the first spine chapter.
    final image = await _firstImageIn(
      chapters.first.relPath,
      cacheDir,
      resolver,
    );
    return existing(image);
  }

  Future<String?> _firstImageIn(
    String relPath,
    String cacheDir,
    HrefResolver resolver,
  ) async {
    final file = File(p.joinAll([cacheDir, ...relPath.split('/')]));
    try {
      final length = await file.length();
      final bytes = await file
          .openRead(0, length > 1024 * 1024 ? 1024 * 1024 : length)
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      final document = html_parser.parse(decodeEpubText(bytes));
      for (final element in document.querySelectorAll('img, image, object')) {
        final elementName = element.localName?.toLowerCase();
        String? href;
        if (elementName == 'object') {
          href = element.attributes['data'];
        } else {
          href = element.attributes['src'] ?? element.attributes['href'];
          if (href == null) {
            for (final key in element.attributes.keys) {
              if (key.toString().toLowerCase().endsWith('href')) {
                href = element.attributes[key];
                break;
              }
            }
          }
        }
        if (href == null) continue;
        final resolved = resolver.resolve(href, basePath: relPath);
        if (resolved.path != null &&
            EpubLoader.isEpubImagePath(resolved.path!)) {
          return resolved.path;
        }
      }
    } catch (_) {
      // A broken cover chapter is not fatal.
    }
    return null;
  }

  static bool _isHtmlDocument(String mediaType, String href) {
    final type = mediaType.toLowerCase();
    if (type.contains('xhtml') || type == 'text/html') return true;
    final lower = href.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  static bool isEpubImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.jfif') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.avif') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff');
  }

  static bool _hasTocType(dom.Element nav) {
    for (final key in nav.attributes.keys) {
      if (key.toString().toLowerCase().endsWith('type')) {
        final value = (nav.attributes[key] ?? '').toLowerCase();
        if (value.split(RegExp(r'\s+')).contains('toc')) return true;
      }
    }
    return false;
  }

  static List<XmlElement> _ancestorNames(XmlElement element, String local) {
    final result = <XmlElement>[];
    for (var node = element.parent; node != null; node = node.parent) {
      if (node is XmlElement && node.name.local == local) result.add(node);
    }
    return result;
  }

  static XmlElement? _firstElement(XmlNode? root, String localName) {
    if (root == null) return null;
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static List<XmlElement> _allElements(XmlNode? root, String localName) {
    if (root == null) return const [];
    return root.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == localName)
        .toList();
  }

  static String? _attribute(XmlElement? element, String localName) {
    if (element == null) return null;
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _textOf(XmlElement? element) {
    return element?.innerText ?? '';
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String properties;
}
