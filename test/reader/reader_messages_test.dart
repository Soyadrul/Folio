import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/webview_reader.dart';

void main() {
  test('a string element is kept, any other type is dropped', () {
    final ok = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 1,
      'progress': 0.5,
      'page': 1,
      'pages': 2,
      'element': 'n1',
    });
    final wrong = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 1,
      'progress': 0.5,
      'page': 1,
      'pages': 2,
      'element': const ['n1'],
    });
    expect(ok!.element, 'n1');
    expect(wrong!.element, isNull);
  });

  test('a non-numeric chapter index is rejected', () {
    expect(
      progressEventFromMessage({
        'type': 'progress',
        'chapterIndex': 'two',
        'progress': 0.5,
        'page': 1,
        'pages': 2,
      }),
      isNull,
    );
  });

  test('unsupported link schemes produce a visible message', () {
    expect(
      unsupportedLinkMessage('http://example.com'),
      'External links are not opened by Folio.',
    );
    expect(
      unsupportedLinkMessage('https://example.com'),
      'External links are not opened by Folio.',
    );
    expect(
      unsupportedLinkMessage('mailto:reader@example.com'),
      'mailto links are not opened by Folio.',
    );
    expect(
      unsupportedLinkMessage('tel:+15551234'),
      'tel links are not opened by Folio.',
    );
    expect(unsupportedLinkMessage('file:///book/ch2.xhtml'), isNull);
    expect(unsupportedLinkMessage('#note1'), isNull);
  });
}
