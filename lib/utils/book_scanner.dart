import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';

/// Walks [folderPath] recursively and returns every .epub file it finds.
///
/// Each file is parsed with [epubx] to extract the title, author, and cover
/// image.  Parsing happens in a simple try/catch so a corrupt epub never
/// prevents the rest of the library from loading.
Future<List<Book>> scanFolderForBooks(String folderPath) async {
  final dir = Directory(folderPath);
  if (!await dir.exists()) return [];

  final epubFiles = await _collectEpubFiles(dir);
  final books = <Book>[];

  for (final file in epubFiles) {
    try {
      final book = await _parseEpub(file);
      books.add(book);
    } catch (_) {
      // Use the filename as a fallback title if parsing fails.
      books.add(Book(
        path: file.path,
        title: p.basenameWithoutExtension(file.path),
        author: 'Unknown Author',
      ));
    }
  }

  // Sort alphabetically by title (case-insensitive).
  books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return books;
}

/// Recursively lists all *.epub files under [dir].
Future<List<File>> _collectEpubFiles(Directory dir) async {
  final results = <File>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
      results.add(entity);
    }
  }
  return results;
}

/// Reads one EPUB file and extracts its metadata.
Future<Book> _parseEpub(File file) async {
  final bytes = await file.readAsBytes();
  final epub = await EpubReader.readBook(bytes);

  final title = (epub.Title?.trim().isNotEmpty ?? false)
      ? epub.Title!.trim()
      : p.basenameWithoutExtension(file.path);

  final author = (epub.Author?.trim().isNotEmpty ?? false)
      ? epub.Author!.trim()
      : 'Unknown Author';

  // Try to extract the cover image.
  Uint8List? cover;
  try {
    cover = _extractCover(epub);
  } catch (_) {
    cover = null;
  }

  return Book(
    path: file.path,
    title: title,
    author: author,
    coverImage: cover,
  );
}

/// Attempts to find a cover image inside the parsed [EpubBook].
///
/// Tries several common locations where epub publishers place the cover art.
Uint8List? _extractCover(EpubBook epub) {
  // 1. Direct cover field - Image from image package, use getBytes().
  final cover = epub.CoverImage;
  if (cover != null) {
    return cover.getBytes();
  }

  // 2. Look for an image named "cover" in the content files.
  final images = epub.Content?.Images;
  if (images == null) return null;

  for (final entry in images.entries) {
    final key = entry.key.toLowerCase();
    if (key.contains('cover') && entry.value.Content != null) {
      return Uint8List.fromList(entry.value.Content!);
    }
  }

  // 3. Fall back to the very first image in the book.
  if (images.isNotEmpty) {
    final first = images.values.first;
    if (first.Content != null) {
      return Uint8List.fromList(first.Content!);
    }
  }

  return null;
}
