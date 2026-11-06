/// The operations the reader chrome can perform on whichever content view is
/// mounted (WebView on Android, Flutter fallback on Linux).
abstract class ReaderViewBackend {
  Future<void> loadChapter(int index, {double progress = 0, String? element});
  Future<void> nextPage();
  Future<void> prevPage();
  Future<void> goBack();
  Future<void> goToProgress(double progress, {String? element});
  Future<void> toggleAutoScroll();
  Future<void> pauseAutoScroll();
  Future<void> startAutoScroll();
  Future<void> setAutoScrollSpeed(int speed);
  bool get autoScrollRunning;
  int get currentChapter;
}

/// A tiny indirection so [ReaderScreen] does not need to know which platform
/// view is mounted. The view attaches itself in `initState`.
class ReaderContentController implements ReaderViewBackend {
  ReaderViewBackend? _backend;

  void attach(ReaderViewBackend backend) => _backend = backend;

  void detach(ReaderViewBackend backend) {
    if (identical(_backend, backend)) _backend = null;
  }

  @override
  Future<void> loadChapter(int index, {double progress = 0, String? element}) =>
      _backend?.loadChapter(index, progress: progress, element: element) ??
      Future<void>.value();

  @override
  Future<void> nextPage() => _backend?.nextPage() ?? Future<void>.value();

  @override
  Future<void> prevPage() => _backend?.prevPage() ?? Future<void>.value();

  @override
  Future<void> goBack() => _backend?.goBack() ?? Future<void>.value();

  @override
  Future<void> goToProgress(double progress, {String? element}) =>
      _backend?.goToProgress(progress, element: element) ??
      Future<void>.value();

  @override
  Future<void> toggleAutoScroll() =>
      _backend?.toggleAutoScroll() ?? Future<void>.value();

  @override
  Future<void> pauseAutoScroll() =>
      _backend?.pauseAutoScroll() ?? Future<void>.value();

  @override
  Future<void> startAutoScroll() =>
      _backend?.startAutoScroll() ?? Future<void>.value();

  @override
  Future<void> setAutoScrollSpeed(int speed) =>
      _backend?.setAutoScrollSpeed(speed) ?? Future<void>.value();

  @override
  bool get autoScrollRunning => _backend?.autoScrollRunning ?? false;

  @override
  int get currentChapter => _backend?.currentChapter ?? 0;
}
