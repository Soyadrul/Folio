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
