import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/models/app_settings.dart';

void main() {
  group('defaults from section 8', () {
    test('match the specification exactly', () {
      const settings = AppSettings();
      expect(settings.readerMode, ReaderMode.book);
      expect(settings.fontSize, 18);
      expect(settings.lineHeight, 1.5);
      expect(settings.marginHorizontal, 16);
      expect(settings.keepScreenOn, isTrue);
      expect(settings.readingMode, ReadingMode.light);
      expect(settings.volumeButtonsTurnPages, isTrue);
      expect(settings.invertVolumeButtons, isFalse);
      expect(settings.tapZones, isTrue);
      expect(settings.tapZoneWidth, 30);
      expect(settings.swipeToTurnPage, isTrue);
      expect(settings.pageAnimation, isTrue);
      expect(settings.autoScrollSpeed, 40);
      expect(settings.tapToStartStop, isTrue);
      expect(settings.volumeButtonsChangeSpeed, isTrue);
      expect(settings.scrollAutoStart, isFalse);
    });

    test('an empty saved object falls back to the defaults', () {
      final settings = AppSettings.fromJson(const {});
      expect(settings.fontSize, 18);
      expect(settings.lineHeight, 1.5);
      expect(settings.marginHorizontal, 16);
      expect(settings.readingMode, ReadingMode.light);
      expect(settings.readerMode, ReaderMode.book);
    });
  });

  test('every setting survives a JSON round trip', () {
    const original = AppSettings(
      fontSize: 22.5,
      fontFamily: 'Lora',
      lineHeight: 1.8,
      textAlign: TextAlign.left,
      hyphenation: false,
      hyphenationLanguage: 'it',
      marginHorizontal: 24,
      readingMode: ReadingMode.sepia,
      keepScreenOn: false,
      showProgressBar: false,
      readerMode: ReaderMode.scroll,
      volumeButtonsTurnPages: false,
      invertVolumeButtons: true,
      tapZones: false,
      tapZoneWidth: 42,
      swipeToTurnPage: false,
      pageAnimation: false,
      autoScrollSpeed: 120,
      tapToStartStop: false,
      volumeButtonsChangeSpeed: false,
      scrollAutoStart: true,
    );

    final restored = AppSettings.fromJson(
      Map<String, dynamic>.from(original.toJson()),
    );

    expect(restored.toJson(), original.toJson());
    expect(restored.textAlign, TextAlign.left);
    expect(restored.readingMode, ReadingMode.sepia);
    expect(restored.readerMode, ReaderMode.scroll);
  });

  test('survives the string form used by SharedPreferences', () {
    const original = AppSettings(fontSize: 33, autoScrollSpeed: 250);
    final restored = AppSettings.fromJsonString(original.toJsonString());
    expect(restored.toJson(), original.toJson());
  });

  test('clamps out-of-range saved numbers to the supported range', () {
    final settings = AppSettings.fromJson(const {
      'fontSize': 900,
      'lineHeight': 9,
      'marginHorizontal': -20,
      'tapZoneWidth': 90,
      'autoScrollSpeed': 0,
    });
    expect(settings.fontSize, 40);
    expect(settings.lineHeight, 2.2);
    expect(settings.marginHorizontal, 0);
    expect(settings.tapZoneWidth, 45);
    expect(settings.autoScrollSpeed, 5);
  });

  test('ignores invalid enum indexes instead of throwing', () {
    final settings = AppSettings.fromJson(const {
      'readingMode': 99,
      'readerMode': -1,
      'textAlign': 12,
    });
    expect(settings.readingMode, ReadingMode.light);
    expect(settings.readerMode, ReaderMode.book);
    expect(settings.textAlign, TextAlign.justify);
  });

  test('copyWith changes only the requested fields', () {
    const original = AppSettings();
    final changed = original.copyWith(
      fontSize: 30,
      readerMode: ReaderMode.scroll,
    );
    expect(changed.fontSize, 30);
    expect(changed.readerMode, ReaderMode.scroll);
    expect(changed.lineHeight, original.lineHeight);
    expect(changed.tapZones, original.tapZones);
  });
}
