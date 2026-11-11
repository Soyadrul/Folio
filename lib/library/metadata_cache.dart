import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A small JSON cache of library metadata (title/author) keyed by file path.
///
/// Re-reading the container and package document of every EPUB on each launch
/// is the main cost of opening a large library. A cached entry is reused while
/// the file's size and modification time are unchanged; a replaced or edited
/// book automatically gets a new entry.
class MetadataCache {
  MetadataCache._(this._path, this._entries);

  /// Cache file to read from and write to, or null to keep the cache in memory.
  final String? _path;
  final Map<String, Map<String, Object?>> _entries;

  static const _version = 1;

  static Future<MetadataCache> load(String? path) async {
    if (path == null) return MetadataCache._(null, {});
    try {
      final file = File(path);
      if (!await file.exists()) return MetadataCache._(path, {});
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['version'] != _version) {
        return MetadataCache._(path, {});
      }
      final entries = raw['entries'];
      if (entries is! Map) return MetadataCache._(path, {});
      final parsed = <String, Map<String, Object?>>{};
      for (final entry in entries.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is Map) {
          parsed[key] = Map<String, Object?>.from(value);
        }
      }
      return MetadataCache._(path, parsed);
    } catch (_) {
      // A damaged cache is never worth failing a scan over.
      return MetadataCache._(path, {});
    }
  }

  /// Returns the cached metadata for [path] when the file signature matches.
  Map<String, Object?>? lookup(
    String path, {
    required int size,
    required int modified,
  }) {
    final entry = _entries[path];
    if (entry == null) return null;
    if (entry['size'] != size) return null;
    if (entry['modified'] != modified) return null;
    final title = entry['title'];
    final author = entry['author'];
    if (title is! String || author is! String) return null;
    return {'title': title, 'author': author};
  }

  /// Records the metadata read for [path].
  void store(
    String path, {
    required int size,
    required int modified,
    required String title,
    required String author,
  }) {
    _entries[path] = {
      'size': size,
      'modified': modified,
      'title': title,
      'author': author,
    };
  }

  /// Drops entries for files that were scanned but no longer exist in
  /// [folderPath].
  ///
  /// Entries belonging to another library folder are kept: switching between
  /// two folders used to delete the other folder's cache and re-read every
  /// book on the next switch.
  void retainWithin(String folderPath, Set<String> paths) {
    final root = p.normalize(p.absolute(folderPath));
    _entries.removeWhere((path, _) {
      final absolute = p.normalize(p.absolute(path));
      final inFolder = absolute == root || p.isWithin(root, absolute);
      return inFolder && !paths.contains(path);
    });
  }

  static final Map<String, Future<void>> _writes = {};

  Future<void> save() async {
    final path = _path;
    if (path == null) return;
    final previous = _writes[path] ?? Future<void>.value();
    final next = previous.then((_) => _writeAtomically(path));
    _writes[path] = next.catchError((_) {});
    return next;
  }

  Future<void> _writeAtomically(String path) async {
    final file = File(path);
    final temporary = File('$path.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        jsonEncode({'version': _version, 'entries': _entries}),
        flush: true,
      );
      // POSIX rename replaces the destination in one step, so a scan that is
      // reading the file never sees half a JSON document.
      await temporary.rename(path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Nothing else to do; the cache is an optimisation.
      }
    }
  }
}
