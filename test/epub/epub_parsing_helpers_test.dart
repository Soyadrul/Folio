import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/epub/epub.dart';

void main() {
  group('epubManifestProperties', () {
    test('splits on any whitespace and lowercases', () {
      expect(epubManifestProperties('  nav\tcover-image\nscripted  '), {
        'nav',
        'cover-image',
        'scripted',
      });
    });

    test('an empty value has no properties', () {
      expect(epubManifestProperties(''), isEmpty);
    });
  });

  group('decodeEpubText', () {
    test('decodes UTF-8 with a BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('héllo')];
      expect(decodeEpubText(bytes), 'héllo');
    });

    test('decodes UTF-16 little endian with a BOM', () {
      final bytes = [0xFF, 0xFE];
      for (final unit in 'héllo'.codeUnits) {
        bytes.addAll([unit & 0xFF, unit >> 8]);
      }
      expect(decodeEpubText(bytes), 'héllo');
    });

    test('decodes UTF-16 big endian with a BOM', () {
      final bytes = [0xFE, 0xFF];
      for (final unit in 'héllo'.codeUnits) {
        bytes.addAll([unit >> 8, unit & 0xFF]);
      }
      expect(decodeEpubText(bytes), 'héllo');
    });

    test('falls back to malformed UTF-8 instead of throwing', () {
      expect(decodeEpubText([0x41, 0xFF, 0x42]), contains('A'));
    });
  });

  group('chapterTitleFromHtml', () {
    test('prefers the first heading over the document title', () {
      expect(
        chapterTitleFromHtml(
          '<html><head><title>Old Book</title></head>'
          '<body><h1>Chapter One</h1></body></html>',
          bookTitle: 'Old Book',
        ),
        'Chapter One',
      );
    });

    test('uses the title when it is not the book title', () {
      expect(
        chapterTitleFromHtml(
          '<html><head><title>Prologue</title></head><body></body></html>',
          bookTitle: 'Old Book',
        ),
        'Prologue',
      );
    });

    test('returns nothing when the title is the book title', () {
      expect(
        chapterTitleFromHtml('<title>Old Book</title>', bookTitle: 'Old Book'),
        '',
      );
    });

    test('returns the title when there is no book title', () {
      expect(chapterTitleFromHtml('<title>Prologue</title>'), 'Prologue');
    });

    test('does not treat <titlepage> as a title element', () {
      expect(
        chapterTitleFromHtml(
          '<html><head><titlepage>no</titlepage></head>'
          '<body></body></html>',
          bookTitle: 'Old Book',
        ),
        '',
      );
    });

    test('still reads a real title in the same shape', () {
      expect(
        chapterTitleFromHtml(
          '<html><head><title>Prologue</title></head>'
          '<body></body></html>',
          bookTitle: 'Old Book',
        ),
        'Prologue',
      );
    });

    test('falls through an empty heading to the title', () {
      expect(
        chapterTitleFromHtml(
          '<html><head><title>Prologue</title></head>'
          '<body><h1><img src="x"></h1></body></html>',
          bookTitle: 'Old Book',
        ),
        'Prologue',
      );
    });

    test('strips markup and decodes entities in a heading', () {
      expect(
        chapterTitleFromHtml('<h1>Chapter &amp; <em>One</em></h1>'),
        'Chapter & One',
      );
    });
  });

  group('isEpubImagePath', () {
    test('recognises common and newer image extensions', () {
      for (final path in [
        'a/b.JPG',
        'a/b.jpeg',
        'a/b.jfif',
        'a/b.avif',
        'a/b.svg',
        'a/b.webp',
      ]) {
        expect(isEpubImagePath(path), isTrue, reason: path);
      }
    });

    test('rejects non-images', () {
      expect(isEpubImagePath('a/b.xhtml'), isFalse);
      expect(isEpubImagePath('a/b.css'), isFalse);
    });
  });
}
