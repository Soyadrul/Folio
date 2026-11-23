// This is a basic Flutter widget test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:folio/main.dart';
import 'package:folio/models/app_settings.dart';
import 'package:folio/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: FolioApp()));

    // Verify that the app displays the title.
    expect(find.text('Folio'), findsOneWidget);
  });

  testWidgets('backgrounding the app flushes a setting changed on Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: FolioApp()));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FolioApp)),
    );
    await container
        .read(settingsNotifierProvider.notifier)
        .update((s) => s.copyWith(fontSize: 19));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_app_settings'), isNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    final saved = AppSettings.fromJsonString(
      prefs.getString('folio_app_settings')!,
    );
    expect(saved.fontSize, 19);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
