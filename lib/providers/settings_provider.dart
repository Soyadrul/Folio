import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

// ── SharedPreferences key ──────────────────────────────────────────────────
const _kSettingsKey = 'folio_app_settings';

/// Loads [AppSettings] from [SharedPreferences].
///
/// Returns default settings if nothing has been saved yet.
Future<AppSettings> loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kSettingsKey);
  if (raw == null) return const AppSettings();
  try {
    return AppSettings.fromJsonString(raw);
  } catch (_) {
    return const AppSettings();
  }
}

/// Persists [settings] to [SharedPreferences].
Future<void> saveSettings(AppSettings settings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSettingsKey, settings.toJsonString());
}

// ── Riverpod provider ──────────────────────────────────────────────────────

/// Asynchronously provides the initial [AppSettings] by reading from disk.
///
/// The [settingsNotifierProvider] is what the UI watches; it is initialised
/// from this future provider.
final settingsFutureProvider = FutureProvider<AppSettings>((ref) async {
  return loadSettings();
});

/// Holds and exposes the mutable [AppSettings] for the whole app.
///
/// Usage:
///   ```dart
///   // Read:
///   final settings = ref.watch(settingsNotifierProvider);
///   // Update:
///   ref.read(settingsNotifierProvider.notifier).update((s) => s.copyWith(fontSize: 20));
///   ```
final settingsNotifierProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Load settings asynchronously after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
    return const AppSettings();
  }

  /// Loads settings from SharedPreferences and updates state.
  Future<void> _loadSettings() async {
    final settings = await loadSettings();
    state = settings;
  }

  /// Replaces the entire state and persists it.
  Future<void> update(AppSettings Function(AppSettings) updater) async {
    state = updater(state);
    await saveSettings(state);
  }

  /// Resets everything to factory defaults and persists.
  Future<void> reset() async {
    state = const AppSettings();
    await saveSettings(state);
  }
}
