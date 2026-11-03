import 'package:flutter_test/flutter_test.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns defaults when nothing has been saved', () async {
    final settings = await loadSettings();
    expect(settings.toJson(), const AppSettings().toJson());
  });

  test('saveSettings writes the folio_app_settings key', () async {
    const settings = AppSettings(fontSize: 26, readerMode: ReaderMode.scroll);
    await saveSettings(settings);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_app_settings'), isNotNull);
    expect(await loadSettings(), isA<AppSettings>());
    expect((await loadSettings()).toJson(), settings.toJson());
  });

  test('a corrupt saved string falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({'folio_app_settings': '{not json'});
    expect((await loadSettings()).toJson(), const AppSettings().toJson());
  });

  test(
    'loads settings saved by an older version with missing fields',
    () async {
      SharedPreferences.setMockInitialValues({
        'folio_app_settings': '{"fontSize": 24}',
      });
      final settings = await loadSettings();
      expect(settings.fontSize, 24);
      expect(settings.lineHeight, 1.5);
      expect(settings.readerMode, ReaderMode.book);
    },
  );
}
