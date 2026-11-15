import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';
import 'package:folio/screens/reader_screen.dart';

void main() {
  final entries = [
    const EpubTocEntry(title: 'Chapter', chapterIndex: 1),
    const EpubTocEntry(title: 'Section A', chapterIndex: 1, fragment: 'a'),
    const EpubTocEntry(title: 'Section B', chapterIndex: 1, fragment: 'b'),
    const EpubTocEntry(title: 'Next chapter', chapterIndex: 2),
  ];

  test('the TOC highlights the entry for the visible fragment', () {
    expect(tocSelectionIndex(entries, chapterIndex: 1, element: 'b'), 2);
  });

  test('the TOC falls back to the first entry of the chapter', () {
    expect(tocSelectionIndex(entries, chapterIndex: 1, element: 'other'), 0);
    expect(tocSelectionIndex(entries, chapterIndex: 1), 0);
    expect(tocSelectionIndex(entries, chapterIndex: 2), 3);
  });
}
