import 'package:flutter_test/flutter_test.dart';
import 'package:folio/reader/reader_content_controller.dart';

class _RecordingBackend implements ReaderViewBackend {
  final calls = <String>[];

  @override
  Future<void> pushHistory() async => calls.add('pushHistory');

  @override
  Future<void> loadChapter(
    int index, {
    double progress = 0,
    String? element,
  }) async {
    calls.add('loadChapter:$index:${element ?? ''}');
  }

  @override
  Future<void> nextPage() async {}
  @override
  Future<void> prevPage() async {}
  @override
  Future<void> goBack() async {}
  @override
  Future<void> goToProgress(double progress, {String? element}) async {}
  @override
  Future<void> toggleAutoScroll() async {}
  @override
  Future<void> pauseAutoScroll() async {}
  @override
  Future<void> startAutoScroll() async {}
  @override
  Future<void> setAutoScrollSpeed(int speed) async {}
  @override
  bool get autoScrollRunning => false;
  @override
  int get currentChapter => 0;
}

void main() {
  test('openChapter pushes history before loading', () async {
    final backend = _RecordingBackend();
    final controller = ReaderContentController()..attach(backend);

    await controller.openChapter(3, element: 'sec2');

    expect(backend.calls, ['pushHistory', 'loadChapter:3:sec2']);
  });
}
