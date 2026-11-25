import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/epub/href_resolver.dart';
import 'package:folio/reader/book_progress.dart';

void main() {
  test('chapters are weighted equally, not by HTML size', () {
    // The second chapter is a thousand times larger, but only one of the two
    // chapters is behind the reader.
    final document = _book([200, 200000]);

    expect(overallProgressFor(document, 1, 0), closeTo(0.5, 1e-9));
  });

  test('a chapter that fits one screen is not counted as read', () {
    final document = _book([200, 200, 200]);

    // One of three chapters is behind the reader; the open chapter itself
    // counts for nothing yet, even though it fills the screen.
    expect(overallProgressFor(document, 1, 1, pages: 1), closeTo(1 / 3, 1e-9));
  });

  test('the final chapter still completes the book on one page', () {
    final document = _book([200, 200, 200]);

    expect(overallProgressFor(document, 2, 1, pages: 1), 1);
  });

  test('progress inside a multi-page chapter is counted', () {
    final document = _book([200, 200]);

    expect(overallProgressFor(document, 1, 0.5, pages: 4), closeTo(0.75, 1e-9));
  });

  test('a restored position keeps the progress that was saved', () {
    final document = _book([200, 200]);

    // No page count is known while reopening, so the saved value is trusted.
    expect(overallProgressFor(document, 1, 1), 1);
  });

  test('an auxiliary page does not move the book progress', () {
    final document = _book([200, 200]);

    expect(overallProgressFor(document, 7, 0.5), isNull);
  });
}

EpubDocument _book(List<int> byteSizes) {
  return EpubDocument(
    filePath: 'book.epub',
    cacheDir: '.',
    opfPath: 'content.opf',
    title: 'Book',
    author: 'Author',
    chapters: [
      for (var index = 0; index < byteSizes.length; index++)
        EpubChapter(
          index: index,
          href: 'text/ch${index + 1}.xhtml',
          relPath: 'text/ch${index + 1}.xhtml',
          path: '/book/text/ch${index + 1}.xhtml',
          title: 'Chapter ${index + 1}',
          byteSize: byteSizes[index],
          mediaType: 'application/xhtml+xml',
        ),
    ],
    toc: const [],
    coverImagePath: null,
    resolver: HrefResolver(const []),
    totalChapterBytes: byteSizes.fold(0, (sum, size) => sum + size),
  );
}
