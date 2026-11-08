# Testing

## Automated checks

Run from the repository root:

| Check | Command |
| --- | --- |
| Static analysis | `flutter analyze` |
| Unit and widget tests | `flutter test` |
| Reader JavaScript syntax | `node --check assets/reader/reader.js` |
| Reader JavaScript tests | `node --test test/js/reader_test.mjs` |
| Linux desktop build | `flutter build linux --release` |

The Dart/Flutter suite covers the EPUB parser (spine order, nested NCX/nav
tables of contents, metadata/cover fallbacks, cache reuse and concurrency),
URL rewriting and sanitising, the library scanner and metadata cache, settings
defaults/ranges/JSON compatibility, the settings notifier (preload, debounce,
late-load race), volume-key mapping, reading-position storage, and the
Settings screen. The JavaScript suite exercises the reader's progress maths,
page snapping, chapter-request debounce, trailing progress reports and
hyphenation CSS.

The workflow in `.github/workflows/build-release.yml` runs `flutter analyze`,
`flutter test`, `node --check` and `node --test` before building, so these
checks are also enforced in CI.

## Android acceptance criteria

An Android SDK, emulator and physical device are not available in every
development environment. Check the following on a real device before a
release:

Suggested manual pass, using at least five EPUB files (EPUB 2 and EPUB 3, a
book with many images, a book whose first item is a cover page, and a book of
more than 500 pages):

1. Open each book: chapter text is complete and formatted.
2. Images appear and fit inside the page, including SVG.
3. The library shows covers; books without a cover show a placeholder.
   Scroll a folder with at least 100 books and check that scrolling is smooth.
4. Book mode: turn pages with volume buttons, taps in both zones, and swipes.
   Switch each method off and confirm it stops responding. Cross chapter
   boundaries in both directions.
5. Scroll mode: start and pause with a tap, change speed, and confirm chapters
   continue without a jump. Hold/drag to scroll manually and confirm automatic
   scrolling pauses.
6. Change every option in Settings while a book is open. Each change should
   take effect without reopening the book. Restart the app and confirm all
   values survive.
7. Leave a book in the middle of a chapter, close the app, reopen it, and
   confirm the same text is visible. Repeat after switching Book/Scroll mode
   and after changing the font size.
8. Open a deliberately corrupted EPUB and a book with missing images/covers.
   The app must show an error or a placeholder, not crash.
9. Open a book whose EPUB 3 navigation document is marked `linear="no"` (for
   example *La caduta di Hyperion*): the “Indice” page appears after the cover
   and before the first chapter, and its links open the right chapter or
   section.
10. Check the heading hierarchy and running text: chapter numbers stand out,
    paragraphs are indented without blank lines between them, and justified
    Italian text hyphenates instead of leaving wide word gaps.
11. Open an `.epub` shared from another app (mail, file manager) and confirm it
    opens in Folio.
12. Background the app while a book is open, then return: the reader must
    recover if Android killed the WebView process.

## Known limitations

- Book mode (pagination) is implemented in the Android WebView reader. The
  Linux build keeps the scroll-only Flutter fallback, so choosing Book mode on
  Linux does not paginate.
- Keep-screen-on and volume-key interception are implemented through Android
  bridges. On Linux they are no-ops and the desktop power settings remain in
  control.
- Element-level position restore is best effort: it only works when the chapter
  provides element ids. Otherwise the reader restores the 0–1 progress value.
- CSS hyphenation inside the WebView uses the chapter's own language. If the
  WebView has no dictionary for that language, the text is simply not
  hyphenated. The Linux native reader does not hyphenate.
- Including a previously skipped EPUB 3 navigation document adds one chapter
  to such books, so a position saved by an older Folio build can resume one
  chapter early once.
- WebView rendering, volume-key interception and the keep-screen-on flag need
  the on-device checklist above; unit tests cannot exercise them.
