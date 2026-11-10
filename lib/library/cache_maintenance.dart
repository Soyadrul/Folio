import 'dart:io';

import 'package:path/path.dart' as p;

/// Deletes stale copies made by the Android intent handler and any
/// interrupted `.part` files.
///
/// The reader saves its position under the path of the copy, so removing
/// everything on startup would lose resumes. Only files older than [maxAge]
/// are removed; `.part` files are always removed because the final rename
/// never happened.
Future<int> pruneIncomingFiles(
  Directory cacheDir, {
  Duration maxAge = const Duration(days: 7),
  DateTime? now,
}) async {
  final incoming = Directory(p.join(cacheDir.path, 'incoming'));
  if (!await incoming.exists()) return 0;
  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  var removed = 0;
  try {
    await for (final entity in incoming.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final name = p.basename(entity.path);
        final isPartial = name.endsWith('.part');
        final stat = await entity.stat();
        if (isPartial || stat.modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } on FileSystemException {
        // A file another process still holds is left for the next startup.
      }
    }
  } on FileSystemException {
    // An unreadable cache directory must never block the app.
  }
  return removed;
}
