import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/models/book.dart';
import 'package:folio/providers/library_provider.dart';
import 'package:folio/utils/book_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('folio_library_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer containerWith(LibraryScanner scanner) {
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(() => LibraryNotifier(scanner: scanner)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('reports a missing storage permission without scanning', () async {
    var scanned = false;
    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(
          () => LibraryNotifier(
            scanner: (path, {cachePath}) async {
              scanned = true;
              return const LibraryScan();
            },
            hasStoragePermission: () async => false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryProvider.notifier).scanFolder(tmp.path);

    final state = container.read(libraryProvider);
    expect(scanned, isFalse);
    expect(state.needsPermission, isTrue);
    expect(state.errorMessage, contains('Storage permission'));
  });

  test('does not save a folder that does not exist', () async {
    final container = containerWith(
      (path, {cachePath}) async => const LibraryScan(),
    );

    await container
        .read(libraryProvider.notifier)
        .scanFolder(p.join(tmp.path, 'missing'));

    final state = container.read(libraryProvider);
    expect(state.errorMessage, contains('Folder not found'));
    expect(state.isLoading, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_library_folder'), isNull);
  });

  test('saves a validated folder and publishes the scanned books', () async {
    final books = [
      Book(path: p.join(tmp.path, 'a.epub'), title: 'A', author: 'B'),
    ];
    final container = containerWith(
      (path, {cachePath}) async => LibraryScan(books: books),
    );

    await container.read(libraryProvider.notifier).scanFolder(tmp.path);

    final state = container.read(libraryProvider);
    expect(state.books.single.title, 'A');
    expect(state.folderPath, tmp.path);
    expect(state.errorMessage, isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_library_folder'), tmp.path);
  });

  test('a superseded scan does not overwrite the newer result', () async {
    final firstDir = Directory(p.join(tmp.path, 'first'))..createSync();
    final secondDir = Directory(p.join(tmp.path, 'second'))..createSync();
    final releaseFirst = Completer<void>();

    final container = containerWith((path, {cachePath}) async {
      if (path == firstDir.path) {
        await releaseFirst.future;
        return const LibraryScan(
          books: [Book(path: 'older', title: 'Older', author: 'A')],
        );
      }
      return const LibraryScan(
        books: [Book(path: 'newer', title: 'Newer', author: 'B')],
      );
    });
    final notifier = container.read(libraryProvider.notifier);

    final firstRun = notifier.scanFolder(firstDir.path);
    final secondRun = notifier.scanFolder(secondDir.path);

    await secondRun;
    expect(container.read(libraryProvider).books.single.title, 'Newer');

    releaseFirst.complete();
    await firstRun;

    final state = container.read(libraryProvider);
    expect(state.books.single.title, 'Newer');
    expect(state.isLoading, isFalse);
    expect(state.folderPath, secondDir.path);
  });

  test('reports sub-folders that could not be read', () async {
    final container = containerWith(
      (path, {cachePath}) async => const LibraryScan(
        books: [Book(path: 'a', title: 'A', author: 'B')],
        unreadablePaths: ['/locked'],
      ),
    );

    await container.read(libraryProvider.notifier).scanFolder(tmp.path);

    final state = container.read(libraryProvider);
    expect(state.books, hasLength(1));
    expect(state.errorMessage, isNull);
    expect(state.warningMessage, contains('could not be read'));
  });

  test('an empty valid folder is still remembered', () async {
    final container = containerWith(
      (path, {cachePath}) async => const LibraryScan(),
    );

    await container.read(libraryProvider.notifier).scanFolder(tmp.path);

    expect(container.read(libraryProvider).books, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_library_folder'), tmp.path);
  });
  test('a superseded scan cannot overwrite the saved folder', () async {
    final firstDir = Directory(p.join(tmp.path, 'first'))..createSync();
    final secondDir = Directory(p.join(tmp.path, 'second'))..createSync();
    final releaseFirst = Completer<void>();
    var permissionChecks = 0;

    final container = ProviderContainer(
      overrides: [
        libraryProvider.overrideWith(
          () => LibraryNotifier(
            scanner: (path, {cachePath}) async => const LibraryScan(),
            hasStoragePermission: () async {
              permissionChecks++;
              if (permissionChecks == 1) await releaseFirst.future;
              return true;
            },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(libraryProvider.notifier);

    final firstRun = notifier.scanFolder(firstDir.path);
    await Future<void>.delayed(Duration.zero);
    await notifier.scanFolder(secondDir.path);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('folio_library_folder'), secondDir.path);

    releaseFirst.complete();
    await firstRun;
    expect(prefs.getString('folio_library_folder'), secondDir.path);
  });

  test(
    'a scan finishing after the notifier is disposed does not throw',
    () async {
      final release = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          libraryProvider.overrideWith(
            () => LibraryNotifier(
              scanner: (path, {cachePath}) async {
                await release.future;
                return const LibraryScan(
                  books: [Book(path: 'a', title: 'A', author: 'B')],
                );
              },
            ),
          ),
        ],
      );
      final notifier = container.read(libraryProvider.notifier);
      final run = notifier.scanFolder(tmp.path);
      await Future<void>.delayed(Duration.zero);

      // The home screen can be replaced (tests, hot restart) while a scan runs.
      container.dispose();
      release.complete();

      await run;
    },
  );

  test('warns when the metadata scan failed', () async {
    final container = containerWith(
      (path, {cachePath}) async => const LibraryScan(
        books: [Book(path: 'a', title: 'a', author: 'Unknown Author')],
        metadataFailed: true,
      ),
    );

    await container.read(libraryProvider.notifier).scanFolder(tmp.path);

    final state = container.read(libraryProvider);
    expect(state.warningMessage, contains('file names'));
  });
}
