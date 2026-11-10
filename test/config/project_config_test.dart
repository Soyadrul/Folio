import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android/CI configuration fixes (F-34 and F-35) so a later edit
/// cannot silently reintroduce the removed permission or the signing failure.
void main() {
  test('the manifest does not request WAKE_LOCK', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('android.permission.WAKE_LOCK')));
    expect(manifest, contains('MANAGE_EXTERNAL_STORAGE'));
  });

  test('backup rules only include shared preferences', () {
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final rules = File(path).readAsStringSync();
      expect(rules, isNot(contains('domain="file"')), reason: path);
      expect(rules, contains('domain="sharedpref"'), reason: path);
    }
  });

  test('CI runs analysis and both test suites before building', () {
    final workflow = File(
      '.github/workflows/build-release.yml',
    ).readAsStringSync();
    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test'));
    expect(workflow, contains('node --check assets/reader/reader.js'));
    expect(workflow, contains('node --test test/js/reader_test.mjs'));
    expect(workflow, contains("flutter-version: '"));
  });

  test('release builds fall back to debug signing without key.properties', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('keystorePropertiesFile.exists()'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
  });

  test('the cover reader streams the archive', () {
    final source = File('lib/epub/epub_cover.dart').readAsStringSync();
    expect(source, contains('InputFileStream'));
    expect(source, isNot(contains('readAsBytes()')));
  });
}
