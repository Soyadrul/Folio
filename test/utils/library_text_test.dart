import 'package:flutter_test/flutter_test.dart';
import 'package:folio/models/book.dart';
import 'package:folio/utils/library_text.dart';

void main() {
  group('foldDiacritics', () {
    test('maps accented Latin letters to their base letters', () {
      expect(foldDiacritics('Èdipo'), 'edipo');
      expect(foldDiacritics('Öl'), 'ol');
      expect(foldDiacritics('Łódź'), 'lodz');
      expect(foldDiacritics('Zeta'), 'zeta');
    });

    test('folds ligatures and sharp s', () {
      expect(foldDiacritics('Æsir'), 'aesir');
      expect(foldDiacritics('Œuvre'), 'oeuvre');
      expect(foldDiacritics('Straße'), 'strasse');
    });

    test('leaves other scripts alone', () {
      expect(foldDiacritics('東京'), '東京');
      expect(foldDiacritics('Ёлка'), 'ёлка');
    });
  });

  group('bookMatchesQuery', () {
    test('matches an unaccented query against an accented title', () {
      const book = Book(path: '/b.epub', title: 'Èdipo Re', author: 'Sofocle');
      expect(bookMatchesQuery(book, 'edipo'), isTrue);
      expect(bookMatchesQuery(book, 'ÈDIPO'), isTrue);
      expect(bookMatchesQuery(book, 'sofocle'), isTrue);
    });

    test('matches an accented query against an unaccented title', () {
      const book = Book(path: '/b.epub', title: 'Edipo Re', author: 'Sofocle');
      expect(bookMatchesQuery(book, 'èdipo'), isTrue);
    });

    test('an empty query matches every book', () {
      const book = Book(path: '/b.epub', title: 'Anything', author: 'Someone');
      expect(bookMatchesQuery(book, ''), isTrue);
      expect(bookMatchesQuery(book, '   '), isTrue);
    });

    test('still rejects a query that does not occur', () {
      const book = Book(path: '/b.epub', title: 'Èdipo Re', author: 'Sofocle');
      expect(bookMatchesQuery(book, 'amleto'), isFalse);
    });
  });
}
