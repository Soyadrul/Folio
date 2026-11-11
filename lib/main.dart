// Copyright (C) 2026 Soyadrul
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'epub/epub_metadata.dart';
import 'library/cache_maintenance.dart';
import 'library/cache_service.dart';
import 'models/book.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/reader_screen.dart';
import 'utils/open_file_service.dart';
import 'utils/theme_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is offline-first: every font it uses ships in assets. A missing
  // asset is a build error the tests catch, not a reason to call Google.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Allow portrait and landscape. The reader reflows when the device rotates.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Load the saved settings before the first frame. Building the notifier with
  // the value also closes the race where a late disk read overwrote an edit.
  final settings = await loadSettings();

  runApp(
    ProviderScope(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => SettingsNotifier(initial: settings),
        ),
      ],
      child: const FolioApp(),
    ),
  );
}

/// Root [MaterialApp] for the Folio ebook reader.
class FolioApp extends StatefulWidget {
  const FolioApp({super.key});

  @override
  State<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends State<FolioApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _openFiles = OpenFileService();
  final _pendingOpenFiles = <String>[];
  StreamSubscription<String>? _openSubscription;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _openSubscription = _openFiles.files.listen(_handleOpenFile);
    // Start the channel after the first frame so a pending file has a
    // navigator to open into.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _ready = true;
      // Old copies of files opened from other apps are never reused; drop them
      // so the cache cannot grow without bound. This runs before the intent
      // channel starts: Android only begins copying after `ready`, so pruning
      // here can never delete a `.part` file that is still being written.
      await _pruneCaches();
      if (!mounted) return;
      _openFiles.start();
      if (_pendingOpenFiles.isNotEmpty) {
        final pending = List<String>.from(_pendingOpenFiles);
        _pendingOpenFiles.clear();
        for (final path in pending) {
          _handleOpenFile(path);
        }
      }
    });
  }

  @override
  void dispose() {
    _openSubscription?.cancel();
    _openFiles.dispose();
    super.dispose();
  }

  Future<void> _pruneCaches() async {
    try {
      final cache = await getTemporaryDirectory();
      await pruneIncomingFiles(cache);
      await CacheService().prune();
    } catch (error) {
      debugPrint('Folio: could not prune the cache: $error');
    }
  }

  Future<void> _handleOpenFile(String path) async {
    final navigator = _navigatorKey.currentState;
    if (!_ready || navigator == null) {
      _pendingOpenFiles.add(path);
      return;
    }
    if (!File(path).existsSync()) return;

    String title;
    String author;
    try {
      final metadata = await readEpubMetadata(path);
      title = metadata.title;
      author = metadata.author;
    } catch (_) {
      title = p.basenameWithoutExtension(path);
      author = 'Unknown Author';
    }
    if (!mounted) return;

    final book = Book(path: path, title: title, author: author);
    navigator.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // Follow the system's light/dark preference on the home screen.
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
