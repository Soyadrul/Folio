import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the reader shell's font-size contract.
///
/// The shell scales a whole chapter so its dominant body text lands on the
/// user's font size. That only works while paragraphs inherit the scaled
/// section size; forcing them back to `--folio-font-size` reintroduces the
/// "same setting, different size" bug for books that wrap text in scaled
/// inline spans.
void main() {
  test('body text is sized by the normalised chapter scale', () {
    final css = File('assets/reader/reader.css').readAsStringSync();

    expect(
      css,
      contains(
        'font-size: var(--folio-chapter-font-size, var(--folio-font-size)) '
        '!important;',
      ),
    );
    expect(css, contains('font-size: inherit !important;'));
    expect(
      css,
      isNot(contains('font-size: var(--folio-font-size) !important;')),
    );
  });
}
