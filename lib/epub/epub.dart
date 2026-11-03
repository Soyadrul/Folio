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
import 'href_resolver.dart';

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
  });

  final String filePath;

  /// Folder containing the extracted book.
  final String cacheDir;

  /// Absolute path to the OPF file inside [cacheDir].
  final String opfPath;

  final String title;
  final String author;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;
  final String? coverImagePath;
  final HrefResolver resolver;
  final int totalChapterBytes;

  String get rootDir => cacheDir;

  EpubChapter? chapterByRelPath(String relPath) {
    for (final chapter in chapters) {
      if (chapter.relPath == relPath) return chapter;
    }
    return null;
  }

  /// Index of the chapter containing [relPath], or the closest earlier one.
  int? chapterIndexForPath(String relPath) {
    final exact = chapterByRelPath(relPath);
    if (exact != null) return exact.index;
    return null;
  }

  /// Reads and rewrites [chapter] for the WebView.
  Future<ChapterContent> loadChapterContent(EpubChapter chapter) async {
    final bytes = await File(chapter.path).readAsBytes();
    // Some older books are not valid UTF-8; replacement characters are much
    // better than refusing to open the chapter.
    final raw = utf8.decode(bytes, allowMalformed: true);
    return rewriteChapterHtml(
      raw,
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

    final root = await _root();
    await root.create(recursive: true);
    final key = sha1.convert(utf8.encode(absolute)).toString();
    final dir = Directory(p.join(root.path, 'epub_${key.substring(0, 16)}'));
    final marker = File(p.join(dir.path, '.folio-cache.json'));

    var reusable = false;
    if (await dir.exists() && await marker.exists()) {
      try {
        final data = jsonDecode(await marker.readAsString());
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
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      await _extract(file, dir);
      await marker.writeAsString(
        jsonEncode({
          'path': absolute,
          'size': stat.size,
          'mtime': stat.modified.millisecondsSinceEpoch,
        }),
      );
    }

    return _parse(
      filePath: absolute,
      cacheDir: dir.path,
      opfPath: await _findAndParseContainer(dir),
    );
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

  Future<void> _extract(File file, Directory target) async {
    final bytes = await _readEpubBytes(file);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw EpubException('This book is damaged or is not an EPUB: $e');
    }

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
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

  Future<String> _findAndParseContainer(Directory dir) async {
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
      container = XmlDocument.parse(await containerFile.readAsString());
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
    return p.joinAll([dir.path, ...opf.path!.split('/')]);
  }

  Future<EpubDocument> _parse({
    required String filePath,
    required String cacheDir,
    required String opfPath,
  }) async {
    final files = await _listFiles(Directory(cacheDir));
    final resolver = HrefResolver(files);
    final opfRel = p.relative(opfPath, from: cacheDir).replaceAll('\\', '/');

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(await File(opfPath).readAsString());
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

    final title = _textOf(_firstElement(metadata, 'title')).trim();
    final authors = _allElements(
      metadata,
      'creator',
    ).map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).toList();
    final author = authors.isEmpty ? 'Unknown Author' : authors.join(', ');

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

    final chapters = <EpubChapter>[];
    final spineHrefs = <String>{};
    for (final itemref in _allElements(spine, 'itemref')) {
      final idref = _attribute(itemref, 'idref');
      if (idref == null) continue;
      if ((_attribute(itemref, 'linear') ?? '').toLowerCase() == 'no') {
        continue;
      }
      final item = manifestItems[idref];
      if (item == null) continue;
      final resolved = resolver.resolve(item.href, basePath: opfRel);
      if (resolved.path == null) continue;
      final absolute = p.joinAll([cacheDir, ...resolved.path!.split('/')]);
      if (!await File(absolute).exists()) continue;
      if (!spineHrefs.add(resolved.path!)) continue;
      final stat = await File(absolute).stat();
      chapters.add(
        EpubChapter(
          index: chapters.length,
          href: item.href,
          relPath: resolved.path!,
          path: absolute,
          title: '',
          byteSize: stat.size,
          mediaType: item.mediaType,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw EpubException(
        'This EPUB has no readable chapters (the spine is empty).',
      );
    }

    final toc = await _parseToc(
      metadata: metadata,
      manifestItems: manifestItems,
      chapters: chapters,
      cacheDir: cacheDir,
      opfRel: opfRel,
      resolver: resolver,
    );

    final titledChapters = <EpubChapter>[];
    for (final chapter in chapters) {
      final tocTitle = toc
          .where((t) => t.chapterIndex == chapter.index)
          .map((t) => t.title)
          .firstWhere((t) => t.trim().isNotEmpty, orElse: () => '');
      final titleFromChapter = tocTitle.isEmpty
          ? await _chapterTitle(chapter.path)
          : tocTitle;
      titledChapters.add(
        EpubChapter(
          index: chapter.index,
          href: chapter.href,
          relPath: chapter.relPath,
          path: chapter.path,
          title: titleFromChapter.isEmpty
              ? 'Chapter ${chapter.index + 1}'
              : titleFromChapter,
          byteSize: chapter.byteSize,
          mediaType: chapter.mediaType,
        ),
      );
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
      title: title.isEmpty ? p.basenameWithoutExtension(filePath) : title,
      author: author,
      chapters: titledChapters,
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

    void add(String title, String href, String base) {
      final resolved = resolver.resolve(href, basePath: base);
      if (resolved.path == null) return;
      final index = chapters
          .where((c) => c.relPath == resolved.path)
          .firstOrNull
          ?.index;
      if (index == null) return;
      entries.add(
        EpubTocEntry(
          title: title.trim(),
          chapterIndex: index,
          fragment: resolved.fragment,
          level: 0,
        ),
      );
    }

    // EPUB 3 navigation document.
    final navItem = manifestItems.values
        .where((item) => item.properties.split(' ').contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final resolved = resolver.resolve(navItem.href, basePath: opfRel);
      if (resolved.path != null) {
        final file = File(p.joinAll([cacheDir, ...resolved.path!.split('/')]));
        if (await file.exists()) {
          final navBase = resolved.path!;
          final document = html_parser.parse(await file.readAsString());
          final nav = document
              .querySelectorAll('nav')
              .where((n) => _hasTocType(n))
              .firstOrNull;
          final scope = nav ?? document.body;
          if (scope != null) {
            for (final anchor in scope.querySelectorAll('a')) {
              final href = anchor.attributes['href'];
              if (href == null) continue;
              add(anchor.text, href, navBase);
            }
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
              final document = XmlDocument.parse(await file.readAsString());
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
                  final level = _ancestorNames(point, 'navPoint').length - 1;
                  entries[entries.length - 1] = EpubTocEntry(
                    title: entries.last.title,
                    chapterIndex: entries.last.chapterIndex,
                    fragment: entries.last.fragment,
                    level: level < 0 ? 0 : level,
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

  Future<String> _chapterTitle(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      final bytes = await file
          .openRead(0, length > 8192 ? 8192 : length)
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      final raw = utf8.decode(bytes, allowMalformed: true);
      final title = RegExp(
        r'<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw)?.group(1);
      if (title != null && title.trim().isNotEmpty) {
        return _plainText(title);
      }
      final heading = RegExp(
        r'<h[12][^>]*>(.*?)</h[12]>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw)?.group(1);
      if (heading != null && heading.trim().isNotEmpty) {
        return _plainText(heading);
      }
    } catch (_) {
      // Fall through to the generic title.
    }
    return '';
  }

  static String _plainText(String html) =>
      (html_parser.parseFragment(html).text ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

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
      if (!item.properties.split(' ').contains('cover-image')) continue;
      final resolved = resolver.resolve(item.href, basePath: opfRel);
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
      if (_isImagePath(resolved.path!)) {
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
      final document = html_parser.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
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
        if (resolved.path != null && _isImagePath(resolved.path!)) {
          return resolved.path;
        }
      }
    } catch (_) {
      // A broken cover chapter is not fatal.
    }
    return null;
  }

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.bmp');
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
