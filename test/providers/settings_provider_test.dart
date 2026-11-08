import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test('a preloaded value is available on the first read', () {
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => SettingsNotifier(initial: const AppSettings(fontSize: 28)),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(settingsNotifierProvider).fontSize, 28);
  });

  test('a user edit is not overwritten by the late initial load', () async {
    SharedPreferences.setMockInitialValues({
      'folio_app_settings': const AppSettings(fontSize: 30).toJsonString(),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsNotifierProvider.notifier);

    await notifier.update((s) => s.copyWith(fontSize: 22));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(settingsNotifierProvider).fontSize, 22);

    await notifier.flush();
    final prefs = await SharedPreferences.getInstance();
    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.fontSize, 22);
  });

  test('rapid slider changes are saved once after the debounce', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsNotifierProvider.notifier);

    await notifier.update((s) => s.copyWith(fontSize: 20));
    await notifier.update((s) => s.copyWith(fontSize: 21));
    await notifier.update((s) => s.copyWith(fontSize: 22));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('folio_app_settings'),
      isNull,
      reason: 'nothing is written while the slider is still moving',
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.fontSize, 22);
  });
}
