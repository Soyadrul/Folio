# 📖 Folio – Distraction-free EPUB Reader

A clean, distraction-free EPUB reader for **Android** and **Linux desktop**,
built with Flutter.

---

## ✨ Features

| Feature | Detail |
|---|---|
| EPUB support | EPUB 2 & 3, nested NCX/nav tables of contents, `linear="no"` and auxiliary documents reachable by links |
| Rendering | Android renders chapters in a bundled WebView shell; Linux uses the native Flutter reader (`flutter_html` + `flutter_svg`) |
| Library scan | Pick any folder; sub-folders are scanned automatically in background isolates |
| Library cache | Title/author metadata is cached by file size and modification time |
| Covers | Lazy JPEG thumbnails from the EPUB archive; books without a cover get a generated placeholder |
| Resume reading | Chapter, in-chapter progress, element anchor and whole-book progress are saved per book |
| Table of contents | Slide-out drawer with nested chapter links |
| In-book links | Footnotes, internal links and TOC jumps stay inside the reader; a back action returns to the previous location |
| Distraction-free reader | Full-screen immersive mode; tap to toggle controls |
| 3 display modes | **Light** · **Dark** · **Sepia** (the old Auto value is kept only for saved settings) |
| Font family | 12 font families bundled for offline use (Latin + Latin-ext) |
| Font size | Adjustable from 10 px to 40 px |
| Line spacing | 1.0 – 2.2 multiplier |
| Side margins | 0 px – 48 px |
| Text alignment | Left · Justify · Right |
| Hyphenation | Automatic for justified text in the Android WebView reader |
| Reading modes | **Book** (CSS-paginated, Android) and **Scroll** (Android + Linux) |
| Page controls | Tap zones (15–45% wide), swipe, and Android volume buttons; volume direction can be inverted |
| Auto-scroll | 5 – 300 px/s, tap to start/stop, optional auto-start, volume-key speed changes |
| Progress bar | Thin reading-progress strip plus overall percentage (toggleable) |
| Keep screen on | Prevents display dimming while reading (Android) |
| Search | Filter the library by title or author |
| Open from other apps | Android intent filter for `.epub` files |
| Storage controls | Clear extracted books and cover thumbnails; reset every setting to its default |

> **Linux note:** the Linux reader is scroll-only. Book mode, page animation,
> keep-screen-on and volume-key handling are Android features. Linux still
> honours typography, margins, colours, alignment and auto-scroll settings.

---

## 🗂 Project Structure

```
Folio/
├── lib/
│   ├── main.dart                    # Entry point, settings preload, MaterialApp
│   ├── epub/
│   │   ├── epub.dart                # Extraction, spine/TOC/cover parsing, EpubLoader
│   │   ├── epub_text.dart           # UTF-8/UTF-16 decoding for EPUB documents
│   │   ├── epub_cover.dart          # Cover lookup straight from the ZIP archive
│   │   ├── epub_metadata.dart       # Shared title/author metadata reader
│   │   ├── chapter_html.dart        # Sanitising, URL rewriting, scoped book CSS
│   │   └── href_resolver.dart       # EPUB-relative link resolution
│   ├── library/
│   │   ├── cache_maintenance.dart   # Age-based pruning of caches and incoming files
│   │   ├── cache_service.dart       # Owns extracted-book and cover caches
│   │   ├── cover_service.dart       # Lazy cover thumbnails for library cards
│   │   └── metadata_cache.dart      # JSON cache of scanned book metadata
│   ├── models/
│   │   ├── book.dart                # Path, title, author, progress, modification time
│   │   └── app_settings.dart        # All user settings + JSON serialisation
│   ├── providers/
│   │   ├── library_provider.dart    # Riverpod: folder scan, book list, saved positions
│   │   └── settings_provider.dart   # Riverpod: settings load/save (SharedPreferences)
│   ├── reader/
│   │   ├── webview_reader.dart      # Android WebView reader + JS bridge
│   │   ├── flutter_reader.dart      # Linux native reader (scroll-only fallback)
│   │   ├── reader_content_controller.dart # Chrome ↔ mounted reader backend
│   │   ├── reader_fonts.dart        # WOFF2 @font-face registration for the WebView
│   │   ├── chapter_transfer_queue.dart # Serialises chunked chapter transfers
│   │   ├── reading_position.dart    # Per-book position persistence
│   │   ├── keep_screen_on.dart      # Android window flag bridge
│   │   ├── volume_keys.dart         # Android volume-key bridge and mapping
│   │   └── webview_security.dart    # CSP and navigation policy
│   ├── screens/
│   │   ├── home_screen.dart         # Library grid with folder picker & search
│   │   ├── reader_screen.dart       # Full-screen reader with overlay UI
│   │   └── settings_screen.dart     # Font, theme, layout, behaviour controls
│   ├── utils/
│   │   ├── android_storage.dart     # Android storage permission checks
│   │   ├── book_scanner.dart        # Recursive .epub finder + isolated metadata scan
│   │   ├── open_file_service.dart   # Shared-file (content://) import
│   │   └── theme_utils.dart         # Colours, fonts, ThemeData builders
│   └── widgets/
│       └── book_card.dart           # Cover card widget (image or placeholder)
├── assets/
│   ├── reader/                      # reader.css, reader.js and WOFF2 fonts
│   └── google_fonts/                # TTF files used by the Flutter UI and Linux reader
├── test/                            # Dart/Flutter tests and JS reader tests
├── tool/                            # Scripts that fetch the bundled font files
├── docs/                            # Audit notes and implementation plans
├── pubspec.yaml
└── analysis_options.yaml
```

---

## 🚀 Getting Started

### Prerequisites

| Tool | Minimum version |
|---|---|
| Flutter SDK | 3.38.4 (CI pins 3.47.7) |
| Dart SDK | 3.11.0 |
| Android SDK | Build tools and platform required by the installed Flutter; Java/Kotlin 21 for release builds |
| CMake | 3.13 (Linux only) |
| GTK3 dev headers | `libgtk-3-dev` (Linux only) |

### 1 · Clone & fetch packages

```bash
git clone https://github.com/Soyadrul/Folio.git
cd Folio
flutter pub get
```

### 2 · Run on Android

Connect a device or start an emulator, then:

```bash
flutter run -d android
```

For a release APK:

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Release builds read `android/key.properties` and its `storeFile`. Without
that file the build falls back to the debug signing key, which is fine for
local testing but must not be published.

### 3 · Run on Linux

Install the GTK3 development package if you haven't already:

```bash
# Debian / Ubuntu
sudo apt install libgtk-3-dev
# Arch Linux
sudo pacman -S gtk3
```

Then run:

```bash
flutter run -d linux
```

For a release build:

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/folio
```

---

## 🧪 Testing

```bash
flutter analyze
flutter test
node --check assets/reader/reader.js
node --test test/js/reader_test.mjs
```

See [TESTING.md](TESTING.md) for coverage details and the Android manual
acceptance checklist.

---

## 📦 Dependencies

| Package | Purpose |
|---|---|
| `flutter_inappwebview` | Android WebView that renders chapters with `assets/reader` |
| `flutter_html` | Native HTML rendering for the Linux reader |
| `flutter_svg` | SVG images in the Linux reader |
| `archive` | EPUB ZIP extraction and cover reads |
| `xml` | Container/OPF/NCX parsing |
| `html` | HTML parsing for nav documents, chapters and covers (pinned to 0.15.6 for `flutter_html` 3.0.0) |
| `crypto` | Cache keys for extracted books and covers |
| `image` | Cover thumbnail generation |
| `file_picker` | Folder & file picker (SAF on Android, GTK on Linux) |
| `flutter_riverpod` | Reactive state management |
| `shared_preferences` | Settings, library folder and reading positions |
| `google_fonts` | Font families in the Flutter UI and native Linux reader |
| `path` / `path_provider` | Cross-platform path and directory helpers |
| `permission_handler` | Runtime storage permissions on Android |

---

## 🎨 Design Decisions

### Why a WebView on Android?
The Android reader renders each chapter in a bundled WebView. This keeps the
reading engine consistent with the CSS/JS in `assets/reader`, supports CSS
multi-column pagination, footnotes and hyphenation, and lets chapters stream in
without holding a whole book in memory. Chapters are swapped inside the same
document through a JavaScript bridge, so moving between chapters never reloads
or flashes the WebView.

### Why a native fallback on Linux?
`flutter_inappwebview` has no Linux implementation. The Linux build therefore
uses a native Flutter reader (`flutter_html` + `flutter_svg`) with the same
chrome, progress contract and auto-scroll behaviour. It is deliberately
scroll-only; Book mode does not paginate on Linux.

### Why Riverpod?
Riverpod's `Notifier`/`NotifierProvider` shares settings and library state
between screens without `InheritedWidget` boilerplate or `BuildContext`
threading. The settings notifier loads before the first frame, debounces
writes, and guards against a late load overwriting a user edit.

### Library scanning and caching
`book_scanner.dart` walks the selected folder and parses metadata in background
isolates. Unchanged files are served from a JSON metadata cache, unreadable
sub-folders are skipped and reported, and a broken book only loses its metadata.
Covers are generated lazily by `CoverService` without extracting the whole book.
`CacheService` prunes stale extracted books and thumbnails at startup and powers
the Settings "Clear cache" action.

### Reading-mode theming
Rather than switching the app's global `ThemeData`, the reading mode is applied
_locally_ inside `ReaderScreen` using a `Theme` widget. The home screen and
settings page always use the system light/dark theme, while only the reader
changes its background and text colour.

---

## 🔒 Android Permissions Explained

| Permission | Why it's needed |
|---|---|
| `READ_EXTERNAL_STORAGE` (≤ API 32) | Read `.epub` files from external storage on Android ≤ 12 |
| `MANAGE_EXTERNAL_STORAGE` (API 30+) | Browse arbitrary folders without SAF |

`MANAGE_EXTERNAL_STORAGE` is a restricted permission on Google Play. A Play
release must either justify it as a document reader or switch to SAF-only
access; see the note in `android/app/src/main/AndroidManifest.xml`.

Folio does not request `INTERNET`; the app is offline-first and all fonts and
reader assets are bundled.

---

## 🔧 Customisation Tips

**Adding more fonts** – add a [Google Fonts](https://fonts.google.com/) name to
`kAvailableFonts` in `lib/utils/theme_utils.dart`, bundle its TTF in
`assets/google_fonts/`, and add the matching WOFF2 faces to
`kReaderFontFaces` in `lib/reader/reader_fonts.dart` plus
`assets/reader/fonts/`. The helper scripts in `tool/` fetch the font files;
runtime fetching is disabled.

**Changing the accent colour** – edit `kAccentColor` in `theme_utils.dart`.

**Extending settings** – add a field to `AppSettings`, update the constructor
and defaults, `copyWith`, `==` / `hashCode`, `toJson` / `fromJson`, add a UI
control in `settings_screen.dart`, and consume it in `reader_screen.dart` and
the mounted reader backend. Saved JSON depends on per-field fallbacks and range
clamping.

---

## 📄 Licence

GPLv3 – see [LICENSE](LICENSE) for details.
