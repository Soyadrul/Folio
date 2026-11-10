import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/chapter_transfer_queue.dart';

void main() {
  test('sends run one at a time in call order', () async {
    final queue = ChapterTransferQueue();
    final events = <String>[];
    final gate = Completer<void>();

    final first = queue.enqueue((id) async {
      events.add('start-$id');
      await gate.future;
      events.add('end-$id');
    });
    final second = queue.enqueue((id) async {
      events.add('start-$id');
      events.add('end-$id');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['start-1']);

    gate.complete();
    await Future.wait([first, second]);
    expect(events, ['start-1', 'end-1', 'start-2', 'end-2']);
  });

  test('ids increase monotonically', () async {
    final queue = ChapterTransferQueue();
    final ids = <int>[];
    await queue.enqueue((id) async => ids.add(id));
    await queue.enqueue((id) async => ids.add(id));
    expect(ids, [1, 2]);
  });

  test('a failed send does not block the next one', () async {
    final queue = ChapterTransferQueue();
    var ran = false;

    final failed = queue.enqueue((_) async {
      throw StateError('bridge died');
    });
    await expectLater(failed, throwsStateError);

    await queue.enqueue((_) async => ran = true);
    expect(ran, isTrue);
  });
}
