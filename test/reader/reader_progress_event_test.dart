import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/webview_reader.dart';

void main() {
  test('a negative chapter index is rejected', () {
    expect(
      progressEventFromMessage({
        'type': 'progress',
        'chapterIndex': -1,
        'progress': 0,
        'page': 1,
        'pages': 1,
        'element': null,
      }),
      isNull,
    );
  });

  test('a valid progress message is parsed', () {
    final event = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 4,
      'progress': 0.42,
      'page': 3,
      'pages': 9,
      'element': 'note1',
    });
    expect(event, isNotNull);
    expect(event!.chapterIndex, 4);
    expect(event.progress, closeTo(0.42, 1e-9));
    expect(event.page, 3);
    expect(event.pages, 9);
    expect(event.element, 'note1');
  });

  test('a non-string element is ignored instead of throwing', () {
    final event = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 1,
      'progress': 0.1,
      'page': 1,
      'pages': 2,
      'element': 17,
    });
    expect(event, isNotNull);
    expect(event!.element, isNull);
  });

  test('non-finite progress is clamped to zero', () {
    final event = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 1,
      'progress': double.nan,
      'page': 1,
      'pages': 2,
    });
    expect(event!.progress, 0);
  });

  test('non-numeric numbers fall back instead of throwing', () {
    final event = progressEventFromMessage({
      'type': 'progress',
      'chapterIndex': 1,
      'progress': 'half',
      'page': 'three',
      'pages': const [9],
    });
    expect(event, isNotNull);
    expect(event!.progress, 0);
    expect(event.page, 1);
    expect(event.pages, 1);
  });
}
