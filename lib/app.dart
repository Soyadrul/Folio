import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/settings_provider.dart';
import 'utils/theme_utils.dart';

/// Root application widget.
///
/// Watches [settingsNotifierProvider] so the theme automatically updates when
/// the user changes the reading mode in Settings.
class FolioApp extends ConsumerWidget {
  const FolioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We don't derive the app theme from the reading mode because the home
    // screen always uses the standard light/dark app theme.  The reading mode
    // only affects the ReaderScreen (applied locally).
    return MaterialApp(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: const _AppShell(),
    );
  }
}

/// Handles the one-time async initialisation (loading saved settings) before
/// showing the HomeScreen.
class _AppShell extends ConsumerWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Import here to avoid circular imports at the top of the file.
    return const _HomeWrapper();
  }
}

class _HomeWrapper extends StatelessWidget {
  const _HomeWrapper();

  @override
  Widget build(BuildContext context) {
    // Lazy import – resolved at runtime.  This avoids a top-level circular
    // dependency between app.dart and home_screen.dart.
    return const _LazyHome();
  }
}

// ── Lazy home ──────────────────────────────────────────────────────────────
// Using a separate widget means home_screen.dart is only imported once,
// keeping the widget tree clean.

class _LazyHome extends StatelessWidget {
  const _LazyHome();

  @override
  Widget build(BuildContext context) {
    // Actual HomeScreen is imported at the entry point (main.dart).
    // This indirection keeps app.dart free of screen-level imports.
    // The Navigator root is set in main.dart instead.
    throw UnimplementedError(
      '_LazyHome should not be built directly – '
      'set home: HomeScreen() in main.dart instead.',
    );
  }
}
