import 'dart:async';

/// Runs chapter transfers strictly one after another.
///
/// Each `_sendChapter` is several awaited `evaluateJavascript` calls. Without
/// this queue, a `needChapter` append can interleave with a TOC load and both
/// chapters end up in JavaScript's single `chapterTransfer` buffer.
class ChapterTransferQueue {
  Future<void> _tail = Future<void>.value();
  int _nextId = 0;

  /// A new id for the next transfer. Ids are only compared for equality.
  int takeId() => ++_nextId;

  /// Schedules [send] after every previously enqueued send has finished.
  ///
  /// The returned future completes with the result of [send]; the internal
  /// tail swallows errors so one failed transfer cannot stall the queue.
  Future<void> enqueue(Future<void> Function(int transferId) send) {
    final id = takeId();
    final result = _tail.then((_) => send(id));
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
