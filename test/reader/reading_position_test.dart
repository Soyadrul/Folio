import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/reading_position.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = ReadingPositionStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads one position per book', () async {
    await store.save(
      '/books/one.epub',
      const ReadingPosition(
        chapterIndex: 4,
        progress: 0.42,
        element: 'chapter-heading',
      ),
    );
    await store.save(
      '/books/two.epub',
      const ReadingPosition(chapterIndex: 1, progress: 0.1),
    );

    final one = await store.load('/books/one.epub');
    expect(one?.chapterIndex, 4);
    expect(one?.progress, 0.42);
    expect(one?.element, 'chapter-heading');

    final two = await store.load('/books/two.epub');
    expect(two?.chapterIndex, 1);
    expect(two?.element, isNull);
  });

  test('a new save replaces the old position for the same book', () async {
    await store.save(
      '/books/one.epub',
      const ReadingPosition(chapterIndex: 1, progress: 0.2),
    );
    await store.save(
      '/books/one.epub',
      const ReadingPosition(chapterIndex: 7, progress: 0.9),
    );

    final position = await store.load('/books/one.epub');
    expect(position?.chapterIndex, 7);
    expect(position?.progress, 0.9);
  });

  test('loadAll returns every saved book without the storage prefix', () async {
    await store.save(
      '/books/one.epub',
      const ReadingPosition(chapterIndex: 2, progress: 0.25),
    );
    await store.save(
      '/books/two.epub',
      const ReadingPosition(chapterIndex: 3, progress: 0.75),
    );

    final all = await store.loadAll();
    expect(all.keys, containsAll(['/books/one.epub', '/books/two.epub']));
    expect(all['/books/two.epub']?.chapterIndex, 3);
  });

  test('missing and corrupt entries are ignored', () async {
    expect(await store.load('/books/missing.epub'), isNull);

    SharedPreferences.setMockInitialValues({
      'folio_reading_position:/books/broken.epub': 'not json',
    });
    expect(await store.load('/books/broken.epub'), isNull);
    expect(await store.loadAll(), isEmpty);
  });

  test('saves overall book progress alongside the chapter position', () async {
    await store.save(
      '/books/one.epub',
      const ReadingPosition(
        chapterIndex: 3,
        progress: 0.5,
        overallProgress: 0.72,
      ),
    );

    final position = await store.load('/books/one.epub');
    expect(position?.overallProgress, 0.72);
  });

  test('old positions without overall progress still load', () async {
    SharedPreferences.setMockInitialValues({
      'folio_reading_position:/books/old.epub':
          '{"chapterIndex":1,"progress":0.4}',
    });

    final position = await store.load('/books/old.epub');
    expect(position?.progress, 0.4);
    expect(position?.overallProgress, 0);
  });

  test('bad numeric values are clamped to the supported position', () async {
    final position = ReadingPosition.fromJson(const {
      'chapterIndex': -3,
      'progress': 7,
    });
    expect(position.chapterIndex, 0);
    expect(position.progress, 1);
  });
}
