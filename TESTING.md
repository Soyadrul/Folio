# Testing note

## Automated checks (this repository)

Run from the repository root:

| Check | Command | Result |
| --- | --- | --- |
| Static analysis | `flutter analyze` | No issues |
| Unit and widget tests | `flutter test` | 79 tests passing |
| Reader JavaScript syntax | `node --check assets/reader/reader.js` | OK |
| Linux desktop build | `flutter build linux --release` | Built `build/linux/x64/release/bundle/folio` |

The tests cover the EPUB parser and URL rewriting, the scanner and cover
thumbnails, settings defaults/ranges/JSON, volume-key mapping, reading-position
storage, and the Settings page groups.

## Android acceptance criteria

No Android SDK, emulator or physical device was available while this work was
done. The criteria in section 11 of `Development_Specification.md` therefore
still need to be checked on a real device before the work is considered
finished.

Suggested manual pass, using at least five EPUB files (EPUB 2 and EPUB 3, a
book with many images, a book whose first item is a cover page, and a book of
more than 500 pages):

1. Open each book: chapter text is complete and formatted (P1).
2. Images appear and fit inside the page, including SVG (P2).
3. The library shows covers; books without a cover show a placeholder.
   Scroll a folder with at least 100 books and check that scrolling is smooth
   (P3).
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

## Known limitations

- Book mode is implemented in the Android WebView reader. The Linux build keeps
  the scroll-only Flutter fallback, so choosing Book mode on Linux does not
  paginate.
- Keep-screen-on is implemented through an Android window flag. On Linux it is
  a no-op and the desktop power settings remain in control.
- Element-level position restore is best effort: it only works when the chapter
  provides element ids. Otherwise the reader restores the 0–1 progress value.
- CSS hyphenation inside the WebView depends on the WebView's language support.
  The Flutter/Linux fallback uses the bundled hyphenator.
- The volume-key interception and the Android keep-screen-on flag could not be
  compiled or run here; they need an on-device check with the rest of the
  Android checklist.
