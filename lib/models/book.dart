import 'dart:typed_data';

/// Represents one EPUB book found in the user's library folder.
class Book {
  /// Absolute path to the .epub file on disk.
  final String path;

  /// Book title extracted from the EPUB metadata.
  final String title;

  /// Author name extracted from the EPUB metadata.
  final String author;

  /// Raw bytes of the cover image (may be null if the epub has no cover).
  final Uint8List? coverImage;

  /// Last opened chapter index – used to resume reading.
  final int lastChapterIndex;

  /// Reading progress within the last chapter (0.0 – 1.0).
  final double lastProgress;

  const Book({
    required this.path,
    required this.title,
    required this.author,
    this.coverImage,
    this.lastChapterIndex = 0,
    this.lastProgress = 0.0,
  });

  /// Creates a copy of this book with some fields replaced.
  Book copyWith({
    String? path,
    String? title,
    String? author,
    Uint8List? coverImage,
    bool clearCover = false,
    int? lastChapterIndex,
    double? lastProgress,
  }) {
    return Book(
      path: path ?? this.path,
      title: title ?? this.title,
      author: author ?? this.author,
      coverImage: clearCover ? null : (coverImage ?? this.coverImage),
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastProgress: lastProgress ?? this.lastProgress,
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
