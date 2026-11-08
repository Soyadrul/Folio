import 'dart:async';

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
  SettingsNotifier({AppSettings? initial}) : _initial = initial;

  final AppSettings? _initial;
  bool _edited = false;
  Timer? _saveTimer;

  @override
  AppSettings build() {
    ref.onDispose(() => _saveTimer?.cancel());
    if (_initial == null) {
      // Used by tests and embedders that did not preload the settings. The
      // production entry point passes the loaded value to `initial` instead,
      // so the first frame never shows defaults.
      unawaited(_loadSettings());
    }
    return _initial ?? const AppSettings();
  }

  /// Loads settings from disk, unless the user changed something first.
  Future<void> _loadSettings() async {
    final settings = await loadSettings();
    // A slider moved while the disk read was in flight must not be reset to
    // the old saved value when the future completes.
    if (_edited) return;
    state = settings;
  }

  /// Replaces the entire state and schedules a debounced save.
  Future<void> update(AppSettings Function(AppSettings) updater) async {
    final next = updater(state);
    if (next == state) return;
    _edited = true;
    state = next;
    _scheduleSave();
  }

  /// Resets everything to factory defaults and schedules a save.
  Future<void> reset() async {
    _edited = true;
    state = const AppSettings();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), _saveNow);
  }

  Future<void> _saveNow() async {
    _saveTimer = null;
    try {
      await saveSettings(state);
    } catch (error) {
      // A failed write must not become an unhandled async error. The in-memory
      // value stays valid for this session.
      debugPrint('Folio: could not save settings: $error');
    }
  }

  /// Writes any pending change immediately (tests and app shutdown).
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saveNow();
  }
}
