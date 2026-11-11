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

  test('files opened from other apps keep a stable cache name', () {
    final source = File(
      'android/app/src/main/kotlin/com/github/Soyadrul/Folio/MainActivity.kt',
    ).readAsStringSync();
    expect(source, contains('MessageDigest.getInstance("SHA-256")'));
    expect(source, isNot(contains('System.currentTimeMillis()}-\$fileName')));
    expect(source, contains('.part'));
  });

  test('publishing fails when signing secrets are missing', () {
    final workflow = File(
      '.github/workflows/build-release.yml',
    ).readAsStringSync();
    expect(
      workflow,
      contains('Refusing to publish an APK signed with the debug key'),
    );
    expect(workflow, contains('exit 1'));
  });

  test('publishing verifies the APK uses the release certificate', () {
    final workflow = File(
      '.github/workflows/build-release.yml',
    ).readAsStringSync();
    // A silent key.properties/Gradle fallback must not reach a release.
    expect(workflow, contains('if [ ! -f "android/key.properties" ]'));
    expect(workflow, contains('certificate SHA-256 digest'));
    expect(
      workflow,
      contains('not signed with the configured release key'),
    );
  });

  test('the release manifest does not request INTERNET', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));

    // Debug/profile builds still need the permission for hot reload.
    for (final path in [
      'android/app/src/debug/AndroidManifest.xml',
      'android/app/src/profile/AndroidManifest.xml',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('android.permission.INTERNET'),
      );
    }
  });

  test('runtime font fetching is disabled before the first frame', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      contains('GoogleFonts.config.allowRuntimeFetching = false;'),
    );
    expect(
      source.indexOf('allowRuntimeFetching = false'),
      lessThan(source.indexOf('runApp(')),
    );
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/google_fonts/'),
    );
  });

  test('the README describes the reading modes that actually exist', () {
    final readme = File('README.md').readAsStringSync();
    expect(readme, isNot(contains('4 display modes')));
    expect(readme, contains('3 display modes'));
    expect(readme, contains('Book (paginated, Android)'));
    expect(readme, contains('Scroll (continuous, Android + Linux)'));
  });
}
