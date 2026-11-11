import 'dart:convert';
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

/// Removes extracted books and cover thumbnails that have not been used for
/// [maxAge], abandoned extractions whose source file vanished, and leftovers
/// from an interrupted replace (`.tmp-`/`.old-`).
///
/// Temporary leftovers only need to outlive an extraction that is still
/// running in another process, so they use the much shorter [leftoverGrace]
/// instead of [maxAge].
Future<int> pruneLibraryCaches({
  required Directory epubRoot,
  required Directory coversRoot,
  Duration maxAge = const Duration(days: 30),
  Duration leftoverGrace = const Duration(hours: 1),
  DateTime? now,
}) async {
  final base = now ?? DateTime.now();
  final cutoff = base.subtract(maxAge);
  final leftoverCutoff = base.subtract(leftoverGrace);
  var removed = 0;

  if (await epubRoot.exists()) {
    try {
      await for (final entity in epubRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        final temporary = name.contains('.tmp-') || name.contains('.old-');
        if (temporary) {
          if (await _olderThan(entity, leftoverCutoff) &&
              await _deleteQuietly(entity)) {
            removed++;
          }
          continue;
        }
        if (!name.startsWith('epub_')) continue;
        if ((await _sourceGone(entity) || await _olderThan(entity, cutoff)) &&
            await _deleteQuietly(entity)) {
          removed++;
        }
      }
    } on FileSystemException {
      // An unreadable cache must never block startup.
    }
  }

  if (await coversRoot.exists()) {
    try {
      await for (final entity in coversRoot.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.jpg') && !name.endsWith('.none')) continue;
        if (await _olderThan(entity, cutoff) &&
            await _deleteQuietly(entity)) {
          removed++;
        }
      }
    } on FileSystemException {
      // Same as above.
    }
  }
  return removed;
}

Future<bool> _olderThan(FileSystemEntity entity, DateTime cutoff) async {
  try {
    if (entity is Directory) {
      final access = File(p.join(entity.path, '.folio-access'));
      if (await access.exists()) {
        return (await access.stat()).modified.isBefore(cutoff);
      }
    }
    return (await entity.stat()).modified.isBefore(cutoff);
  } on FileSystemException {
    return false;
  }
}

Future<bool> _sourceGone(Directory dir) async {
  final marker = File(p.join(dir.path, '.folio-cache.json'));
  try {
    if (!await marker.exists()) return true;
    final raw = jsonDecode(await marker.readAsString());
    if (raw is! Map || raw['path'] is! String) return true;
    return !await File(raw['path'] as String).exists();
  } catch (_) {
    return true;
  }
}

Future<bool> _deleteQuietly(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: entity is Directory);
    return true;
  } on FileSystemException {
    return false;
  }
}
