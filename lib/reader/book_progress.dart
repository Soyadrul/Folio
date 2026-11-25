import '../epub/epub.dart';

/// Where [progress] through the chapter [index] places the reader in the book.
///
/// Chapters are weighted equally rather than by HTML bytes: byte size counts
/// markup and images, so a single chapter with a large SVG could own most of
/// the progress bar. Returns null when [index] is not part of the reading flow,
/// such as a footnote or endnote page.
///
/// A chapter that fits one screen reports `progress == 1` as soon as it is
/// shown. When [pages] is supplied, that only counts as finished for the book's
/// final chapter; otherwise opening a short chapter looked like finishing it.
/// The page count is unknown while a saved position is restored, so callers
/// that reopen a book omit it and keep the saved value.
double? overallProgressFor(
  EpubDocument document,
  int index,
  double progress, {
  int? pages,
}) {
  final position = document.chapters.indexWhere((c) => c.index == index);
  if (position < 0) return null;
  final isLast = position == document.chapters.length - 1;
  final within = pages != null && pages <= 1 && !isLast ? 0.0 : progress;
  return ((position + within) / document.chapters.length).clamp(0.0, 1.0);
}
