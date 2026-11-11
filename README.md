# 📖 Folio – Distraction-free EPUB Reader

A clean, distraction-free EPUB reader for **Android** and **Linux desktop**,
built with Flutter.

---

## ✨ Features

| Feature | Detail |
|---|---|
| EPUB support | EPUB 2 & 3, including nested NCX/nav tables of contents |
| Rendering | Android uses a bundled WebView reader; Linux uses a native Flutter reader (scroll mode) |
| Library scan | Pick any folder; sub-folders are scanned automatically |
| Resume reading | Last chapter + scroll position saved per book |
| Table of contents | Slide-out drawer with all chapter links |
| In-book links | Footnotes and same-chapter links stay inside the reader |
| Distraction-free reader | Full-screen immersive mode; tap to toggle controls |
| 3 display modes | **Light** · **Dark** · **Sepia** (the old Auto value is kept only for saved settings) |
| Font family | 12 font families bundled for offline use (Latin + Latin-ext) |
| Font size | Adjustable from 10 px to 40 px |
| Line spacing | 1.0 – 2.2 multiplier |
| Side margins | 0 px – 48 px |
| Reading modes | Book (paginated, Android) and Scroll (continuous, Android + Linux) |
| Auto-scroll | Adjustable speed with tap-to-start/stop |
| Progress bar | Thin reading-progress strip (toggleable) |
| Keep screen on | Prevents display dimming while reading (Android) |
| Search | Filter library by title or author |
| Open from other apps | Android intent filter for `.epub` files |

---

## 🗂 Project Structure

```
Folio/
├── lib/
│   ├── main.dart                    # Entry point, settings preload, MaterialApp
│   ├── epub/
│   │   ├── epub.dart                # Extraction, spine/TOC/cover parsing
│   │   ├── epub_cover.dart          # Lightweight cover lookup for the library
│   │   ├── epub_metadata.dart       # Shared title/author metadata reader
│   │   ├── chapter_html.dart        # Chapter sanitising and URL rewriting
│   │   └── href_resolver.dart       # EPUB-relative link resolution
│   ├── library/
│   │   ├── cover_service.dart       # Cover thumbnails for library cards
│   │   └── metadata_cache.dart      # JSON cache of scanned book metadata
│   ├── models/
│   │   ├── book.dart                # Book data (path, title, author, cover, progress)
│   │   └── app_settings.dart        # All user settings + JSON serialisation
│   ├── providers/
│   │   ├── library_provider.dart    # Riverpod: folder scan, book list, progress
│   │   └── settings_provider.dart   # Riverpod: settings load/save (SharedPreferences)
│   ├── reader/
│   │   ├── webview_reader.dart      # Android WebView reader + JS bridge
│   │   ├── flutter_reader.dart      # Linux Flutter reader fallback
│   │   ├── reader_content_controller.dart
│   │   ├── reading_position.dart    # Per-book position persistence
│   │   ├── reader_fonts.dart        # Bundled font registration
│   │   ├── keep_screen_on.dart      # Android window flag bridge
│   │   ├── volume_keys.dart         # Android volume-key bridge
│   │   └── webview_security.dart    # Navigation/CSP policy
│   ├── screens/
│   │   ├── home_screen.dart         # Library grid with folder picker & search
│   │   ├── reader_screen.dart       # Full-screen reader with overlay UI
│   │   └── settings_screen.dart     # Font, theme, layout, behaviour controls
│   ├── utils/
│   │   ├── book_scanner.dart        # Recursive .epub finder
│   │   ├── open_file_service.dart   # Shared-file (content://) import
│   │   └── theme_utils.dart         # Colours, fonts, ThemeData builders
│   └── widgets/
│       └── book_card.dart           # Cover card widget (image or placeholder)
├── assets/reader/                   # reader.css, reader.js and WOFF2 fonts
├── test/                            # Dart/Flutter tests and JS reader tests
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
| Android Studio / SDK | API 35 (Android 15) |
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

Without `android/key.properties` the release build falls back to the debug
signing key, which is fine for local testing but must not be published.

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
| `archive` | EPUB ZIP extraction |
| `xml` | Container/OPF/NCX parsing |
| `html` | HTML parsing for nav documents and cover pages |
| `crypto` | Cache keys for extracted books |
| `image` | Cover thumbnail generation |
| `file_picker` | Folder & file picker (SAF on Android, GTK on Linux) |
| `flutter_riverpod` | Reactive state management |
| `shared_preferences` | Settings & last-folder persistence |
| `google_fonts` | Font families in the native Linux reader |
| `path` / `path_provider` | Cross-platform path and directory helpers |
| `permission_handler` | Runtime storage permissions on Android |

---

## 🎨 Design Decisions

### Why a WebView on Android?
The Android reader renders each chapter in a bundled WebView. This keeps the
reading engine consistent with the CSS/JS in `assets/reader`, supports
pagination, footnotes and hyphenation, and lets chapters stream in without
holding a whole book in memory. Linux has no WebView dependency, so it uses
the native Flutter reader with the same chrome and progress contract.

### Why Riverpod?
Riverpod's `Notifier`/`NotifierProvider` shares settings and library state
between screens without `InheritedWidget` boilerplate or `BuildContext`
threading. The settings notifier loads before the first frame, debounces
writes, and guards against a late load overwriting a user edit.

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

---

## 🔧 Customisation Tips

**Adding more fonts** – add a [Google Fonts](https://fonts.google.com/) name to
`kAvailableFonts` in `lib/utils/theme_utils.dart` and bundle its
`<Family>-Regular.ttf` in `assets/google_fonts/` (runtime fetching is
disabled). The Android WebView uses the separate WOFF2 files in
`assets/reader/fonts`.

**Changing the accent colour** – edit `kAccentColor` in `theme_utils.dart`.

**Extending settings** – add a field to `AppSettings`, update `toJson` /
`fromJson`, add a UI control in `settings_screen.dart`, and consume it in
`reader_screen.dart`.

---

## 📄 Licence

GPLv3 – see [LICENSE](LICENSE) for details.
