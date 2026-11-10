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
}
