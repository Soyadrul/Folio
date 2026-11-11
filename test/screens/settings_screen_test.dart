import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/providers/settings_provider.dart';
import 'package:folio/screens/settings_screen.dart';
import 'package:folio/utils/theme_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows every section from the specification', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MODE'), findsOneWidget);
    expect(find.text('BOTH MODES'), findsOneWidget);
    expect(find.text('Font size'), findsOneWidget);
    expect(find.text('Line spacing'), findsOneWidget);
    expect(find.text('Margins'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('BOOK MODE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BOOK MODE'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('SCROLL MODE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SCROLL MODE'), findsOneWidget);
    expect(find.text('Scroll speed'), findsOneWidget);
    expect(find.text('Start automatically when book opens'), findsOneWidget);
  });

  testWidgets('changing the mode applies and saves immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(
      container.read(settingsNotifierProvider).readerMode,
      ReaderMode.book,
    );

    // The mode chips are near the top, above the lazily built groups.
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsNotifierProvider).readerMode,
      ReaderMode.scroll,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.readerMode, ReaderMode.scroll);
  });

  testWidgets('Reset asks for confirmation before discarding settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Reset settings?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('theme choices are Light, Sepia and Dark only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Sepia'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
  });
}
