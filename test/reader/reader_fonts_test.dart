import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/reader_fonts.dart';
import 'package:folio/utils/theme_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every selectable reader font ships woff2 faces', () async {
    for (final family in kAvailableFonts) {
      final faces = kReaderFontFaces[family];
      expect(faces, isNotNull, reason: '$family has bundled faces');
      for (final face in faces!) {
        final data = await rootBundle.load(face.asset);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        expect(bytes.length, greaterThan(1000), reason: face.asset);
        expect(
          String.fromCharCodes(bytes.take(4)),
          'wOF2',
          reason: '${face.asset} is a woff2 font',
        );
      }
    }
  });

  test('the bundled catalogue has no stale families', () {
    expect(kReaderFontFaces.keys.toSet(), kAvailableFonts.toSet());
  });

  test('font face CSS embeds the selected family as a data URI', () async {
    final css = await readerFontFaceCss('Lora');

    expect(css, contains("font-family:'Lora'"));
    expect(css, contains('src:url(data:font/woff2;base64,'));
    expect(css, contains('font-weight:400 700'));
    expect(css, contains("font-style:italic"));
  });

  test('an unknown family produces no font face rules', () async {
    expect(await readerFontFaceCss('Comic Sans MS'), isEmpty);
  });

  test('the CSS stack names real fonts and uses exact family matching', () {
    final merriweather = readerFontStack('Merriweather');
    expect(merriweather, startsWith('"Merriweather",'));
    expect(merriweather, contains('serif'));

    final lato = readerFontStack('Lato');
    expect(lato, startsWith('"Lato",'));
    expect(lato, contains('sans-serif'));

    // The old `contains('roboto')` heuristic made unknown families silently
    // render as Roboto instead of falling back.
    final unknown = readerFontStack('Roboto Slab');
    expect(unknown, isNot(contains('Roboto')));
    expect(unknown, contains('serif'));

    expect(readerFontStack(''), contains('serif'));
  });
}
