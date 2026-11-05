import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../reader/reading_position.dart';
import '../utils/book_scanner.dart';

// ── Persistence keys ───────────────────────────────────────────────────────
const _kLibraryFolderKey = 'folio_library_folder';

// ── State ─────────────────────────────────────────────────────────────────

class LibraryState {
  /// The folder path the user has selected, or null if none yet.
  final String? folderPath;

  /// Books found in [folderPath] (and sub-folders).
  final List<Book> books;

  /// True while a scan is running.
  final bool isLoading;

  /// Non-null when the last scan encountered an error.
  final String? errorMessage;

  const LibraryState({
    this.folderPath,
    this.books = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  LibraryState copyWith({
    String? folderPath,
    List<Book>? books,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      folderPath: folderPath ?? this.folderPath,
      books: books ?? this.books,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(() {
  return LibraryNotifier();
});

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    // Load saved folder on initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedFolder();
    });
    return const LibraryState();
  }

  /// Restores the previously selected folder and re-scans it on startup.
  Future<void> _loadSavedFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLibraryFolderKey);
    if (saved != null) {
      await scanFolder(saved);
    }
  }

  /// Stores [path] as the library folder and scans it for books.
  Future<void> scanFolder(String path) async {
    // Save immediately so the choice is remembered across restarts.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLibraryFolderKey, path);

    state = state.copyWith(folderPath: path, isLoading: true, clearError: true);

    try {
      final scanned = await scanFolderForBooks(path);
      final books = await _withSavedPositions(scanned);
      state = state.copyWith(books: books, isLoading: false);
    } catch (e) {
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
    await scanFolder(folder);
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
