import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../reader/reading_position.dart';
import '../utils/android_storage.dart';
import '../utils/book_scanner.dart';

// ── Persistence keys ───────────────────────────────────────────────────────
const _kLibraryFolderKey = 'folio_library_folder';

/// The function used to scan a folder. Injectable so tests can control timing.
typedef LibraryScanner =
    Future<LibraryScan> Function(String path, {String? cachePath});

/// Checks Android storage permission. Injectable so tests can simulate denial.
typedef StoragePermissionCheck = Future<bool> Function();

// ── State ─────────────────────────────────────────────────────────────────

class LibraryState {
  /// The folder path the user has selected, or null if none yet.
  final String? folderPath;

  /// Books found in [folderPath] (and sub-folders).
  final List<Book> books;

  /// True while a scan is running.
  final bool isLoading;

  /// Non-null when the last scan could not produce a library.
  final String? errorMessage;

  /// A non-fatal problem, e.g. some sub-folders that could not be read.
  final String? warningMessage;

  /// True when Android storage permission is required before scanning.
  final bool needsPermission;

  const LibraryState({
    this.folderPath,
    this.books = const [],
    this.isLoading = false,
    this.errorMessage,
    this.warningMessage,
    this.needsPermission = false,
  });

  LibraryState copyWith({
    String? folderPath,
    List<Book>? books,
    bool? isLoading,
    String? errorMessage,
    String? warningMessage,
    bool clearError = false,
    bool clearWarning = false,
    bool? needsPermission,
  }) {
    return LibraryState(
      folderPath: folderPath ?? this.folderPath,
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      warningMessage: clearWarning
          ? null
          : (warningMessage ?? this.warningMessage),
      needsPermission: needsPermission ?? this.needsPermission,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(() {
  return LibraryNotifier();
});

class LibraryNotifier extends Notifier<LibraryState> {
  LibraryNotifier({
    LibraryScanner? scanner,
    StoragePermissionCheck? hasStoragePermission,
  }) : _scanner = scanner ?? scanFolderForBooks,
       _hasStoragePermissionOverride = hasStoragePermission;

  final LibraryScanner _scanner;
  final StoragePermissionCheck? _hasStoragePermissionOverride;

  /// Every scan gets a token; only the newest one may publish its result.
  int _scanToken = 0;
  String? _cachePath;
  bool _cachePathResolved = false;

  @override
  LibraryState build() {
    // Load saved folder on initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedFolder();
    });
    return const LibraryState();
  }

  Future<String?> _metadataCachePath() async {
    if (_cachePathResolved) return _cachePath;
    _cachePathResolved = true;
    try {
      final support = await getApplicationSupportDirectory();
      _cachePath = p.join(support.path, 'library_metadata.json');
    } catch (_) {
      // Without a support directory scanning still works, just uncached.
      _cachePath = null;
    }
    return _cachePath;
  }

  Future<bool> _hasStoragePermission() async {
    final override = _hasStoragePermissionOverride;
    if (override != null) return override();
    return hasStorageAccess();
  }

  /// Restores the previously selected folder and re-scans it on startup.
  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLibraryFolderKey);
    if (saved == null) return;
    // A folder picked by the user while this was loading wins.
    if (state.folderPath != null) return;
    state = state.copyWith(folderPath: saved);
    await scanFolder(saved, persist: false);
  }

  /// Stores [path] as the library folder and scans it for books.
  ///
  /// The folder is validated and (when [persist] is true) saved only once it
  /// exists, so a bad pick is not remembered. Overlapping scans are supported:
  /// a superseded scan never publishes its result.
  Future<void> scanFolder(String path, {bool persist = true}) async {
    final token = ++_scanToken;
    state = state.copyWith(
      folderPath: path,
      isLoading: true,
      clearError: true,
      clearWarning: true,
      needsPermission: false,
    );

    if (!await _hasStoragePermission()) {
      if (token != _scanToken) return;
      state = state.copyWith(
        isLoading: false,
        needsPermission: true,
        errorMessage: 'Storage permission is required to read your books.',
      );
      return;
    }

    if (!await Directory(path).exists()) {
      if (token != _scanToken) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Folder not found: $path',
      );
      return;
    }

    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLibraryFolderKey, path);
    }

    try {
      final scanned = await _scanner(
        path,
        cachePath: await _metadataCachePath(),
      );
      if (token != _scanToken) return;
      final books = await _withSavedPositions(scanned.books);
      if (token != _scanToken) return;
      final permissionProblem = scanned.permissionDenied;
      final warning =
          _warningFor(scanned) ??
          (Platform.isAndroid && books.isEmpty
              ? 'No EPUB files were found. On Android 11 and newer, grant '
                    '"All files access" or choose a folder under Documents.'
              : null);
      state = state.copyWith(
        books: books,
        isLoading: false,
        needsPermission: permissionProblem,
        errorMessage: permissionProblem && books.isEmpty
            ? 'Storage permission is required to read your books.'
            : null,
        warningMessage: warning,
        clearError: !(permissionProblem && books.isEmpty),
        clearWarning: false,
      );
    } catch (e) {
      if (token != _scanToken) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Could not scan folder: $e',
      );
    }
  }

  /// Re-scans the current folder (e.g. after the user adds new books).
  Future<void> refresh() async {
    final folder = state.folderPath;
    if (folder == null) return;
    await scanFolder(folder, persist: false);
  }

  String? _warningFor(LibraryScan scan) {
    if (scan.skippedFolders == 0) return null;
    final count = scan.skippedFolders;
    final folders = count == 1 ? 'One folder' : '$count folders';
    return '$folders could not be read and were skipped. '
        'Check the storage permission or folder access.';
  }

  /// Merges positions persisted by the reader into freshly scanned books.
  ///
  /// A scan creates new [Book] instances without reading progress, so without
  /// this step the library would forget where each book was left after a
  /// restart even though the reader itself saved the position.
  Future<List<Book>> _withSavedPositions(List<Book> books) async {
    if (books.isEmpty) return books;
    try {
      final saved = await const ReadingPositionStore().loadAll();
      if (saved.isEmpty) return books;
      return books.map((book) {
        final position = saved[book.path];
        if (position == null) return book;
        return book.copyWith(
          lastChapterIndex: position.chapterIndex,
          lastProgress: position.progress,
          overallProgress: position.overallProgress,
        );
      }).toList();
    } catch (error) {
      // A failure to read positions must never hide the scanned books.
      debugPrint('Folio: could not restore reading positions: $error');
      return books;
    }
  }

  /// Updates the saved reading progress for a book (called from the reader).
  void updateReadingProgress(
    String bookPath,
    int chapterIndex,
    double progress, {
    double? overallProgress,
  }) {
    final updated = state.books.map((b) {
      if (b.path == bookPath) {
        return b.copyWith(
          lastChapterIndex: chapterIndex,
          lastProgress: progress,
          overallProgress: overallProgress,
        );
      }
      return b;
    }).toList();
    state = state.copyWith(books: updated);
  }
}
