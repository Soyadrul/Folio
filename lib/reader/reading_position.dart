import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where the reader was inside one book.
///
/// [progress] is the position inside the chapter as a value from 0 to 1.
/// [element] is the id of the first visible element when the chapter provides
/// ids; it is more stable than [progress] when the font size changes.
class ReadingPosition {
  const ReadingPosition({
    required this.chapterIndex,
    required this.progress,
    this.element,
  });

  final int chapterIndex;
  final double progress;
  final String? element;

  Map<String, dynamic> toJson() => {
    'chapterIndex': chapterIndex,
    'progress': progress,
    if (element != null && element!.isNotEmpty) 'element': element,
  };

  factory ReadingPosition.fromJson(Map<String, dynamic> json) {
    final rawChapter = json['chapterIndex'];
    final rawProgress = json['progress'];
    final rawElement = json['element'];
    final chapter = rawChapter is num ? rawChapter.toInt() : 0;
    final progress = rawProgress is num ? rawProgress.toDouble() : 0.0;
    return ReadingPosition(
      chapterIndex: chapter < 0 ? 0 : chapter,
      progress: progress.isNaN || progress.isInfinite
          ? 0
          : progress.clamp(0.0, 1.0).toDouble(),
      element: rawElement is String && rawElement.isNotEmpty
          ? rawElement
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingPosition &&
          other.chapterIndex == chapterIndex &&
          other.progress == progress &&
          other.element == element);

  @override
  int get hashCode => Object.hash(chapterIndex, progress, element);

  @override
  String toString() =>
      'ReadingPosition(chapter: $chapterIndex, progress: $progress, '
      'element: $element)';
}

/// Persists one [ReadingPosition] per book in [SharedPreferences].
///
/// Each book gets its own key so saving one book can never overwrite another,
/// even when several saves are in flight at the same time.
class ReadingPositionStore {
  const ReadingPositionStore();

  static const _prefix = 'folio_reading_position:';

  static String _keyFor(String bookPath) => '$_prefix$bookPath';

  Future<ReadingPosition?> load(String bookPath) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(bookPath));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        return ReadingPosition.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (_) {
      // Corrupt or old data is ignored; the reader starts from the beginning.
    }
    return null;
  }

  Future<void> save(String bookPath, ReadingPosition position) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(bookPath), jsonEncode(position.toJson()));
  }

  /// Loads every saved position, keyed by the book path it belongs to.
  Future<Map<String, ReadingPosition>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final positions = <String, ReadingPosition>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          positions[key.substring(_prefix.length)] = ReadingPosition.fromJson(
            Map<String, dynamic>.from(json),
          );
        }
      } catch (_) {
        // Ignore corrupt entries and keep the other books intact.
      }
    }
    return positions;
  }

  Future<void> remove(String bookPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(bookPath));
  }
}
