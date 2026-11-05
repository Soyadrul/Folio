/// Represents one EPUB book found in the user's library folder.
class Book {
  /// Absolute path to the .epub file on disk.
  final String path;

  /// Book title extracted from the EPUB metadata.
  final String title;

  /// Author name extracted from the EPUB metadata.
  final String author;

  /// Last opened chapter index – used to resume reading.
  final int lastChapterIndex;

  /// Reading progress within the last chapter (0.0 – 1.0).
  final double lastProgress;

  /// Reading progress through the whole book (0.0 – 1.0).
  ///
  /// [lastProgress] only describes the current chapter, so showing it on a
  /// library card makes the bar restart at every chapter. This value is
  /// persisted alongside the reading position and is what the card displays.
  final double overallProgress;

  /// File modification time when the book was scanned. Used to notice a
  /// replaced file after a refresh without re-reading every cover.
  final int lastModifiedMs;

  const Book({
    required this.path,
    required this.title,
    required this.author,
    this.lastChapterIndex = 0,
    this.lastProgress = 0.0,
    this.overallProgress = 0.0,
    this.lastModifiedMs = 0,
  });

  /// Creates a copy of this book with some fields replaced.
  Book copyWith({
    String? path,
    String? title,
    String? author,
    int? lastChapterIndex,
    double? lastProgress,
    double? overallProgress,
    int? lastModifiedMs,
  }) {
    return Book(
      path: path ?? this.path,
      title: title ?? this.title,
      author: author ?? this.author,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastProgress: lastProgress ?? this.lastProgress,
      overallProgress: overallProgress ?? this.overallProgress,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Book && other.path == path);

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Book($title by $author @ $path)';
}
