# 📖 Folio – Distraction-free EPUB Reader

A clean, distraction-free EPUB reader for **Android** and **Linux desktop**,
built with Flutter.

---

## ✨ Features

| Feature | Detail |
|---|---|
| EPUB support | Full EPUB 2 & 3 rendering via `epub_view` |
| Library scan | Pick any folder; sub-folders are scanned automatically |
| Resume reading | Last chapter + scroll position saved per book |
| Table of contents | Slide-out drawer with all chapter links |
| Distraction-free reader | Full-screen immersive mode; tap to toggle controls |
| 4 display modes | **Auto** · **Light** · **Dark** · **Sepia** |
| Font family | 12 Google Fonts choices (Merriweather, Lora, Garamond…) |
| Font size | Adjustable from 12 px to 32 px |
| Line spacing | 1.0 – 2.5 multiplier |
| Side margins | 8 px – 60 px |
| Progress bar | Thin reading-progress strip (toggleable) |
| Keep screen on | Prevents display dimming while reading |
| Search | Filter library by title or author |
| Open from other apps | Android intent filter for `.epub` files |

---

## 🗂 Project Structure

```
folio_reader/
├── lib/
│   ├── main.dart                  # App entry point & MaterialApp
│   ├── models/
│   │   ├── book.dart              # Book data class (path, title, author, cover, progress)
│   │   └── app_settings.dart      # All user settings + JSON serialisation
│   ├── providers/
│   │   ├── library_provider.dart  # Riverpod: folder scan, book list, progress
│   │   └── settings_provider.dart # Riverpod: settings load/save (SharedPreferences)
│   ├── screens/
│   │   ├── home_screen.dart       # Library grid with folder picker & search
│   │   ├── reader_screen.dart     # Full-screen EPUB reader with overlay UI
│   │   └── settings_screen.dart   # Font, theme, layout, behaviour controls
│   ├── widgets/
│   │   └── book_card.dart         # Cover card widget (image or decorative placeholder)
│   └── utils/
│       ├── book_scanner.dart      # Recursive .epub finder + epubx metadata parser
│       └── theme_utils.dart       # Colour helpers, Google Fonts wrappers, ThemeData builders
├── pubspec.yaml                   # All dependencies (versions verified March 2026)
└── analysis_options.yaml          # Dart lint configuration
```

---

## 🚀 Getting Started

### Prerequisites

| Tool | Minimum version |
|---|---|
| Flutter SDK | 3.24.0 |
| Dart SDK | 3.4.0 |
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

### 3 · Run on Linux

Install the GTK3 development package if you haven't already:

```bash
# Debian / Ubuntu / Arch (adjust for your distro)
sudo apt install libgtk-3-dev        # Debian/Ubuntu
sudo pacman -S gtk3                  # Arch Linux
```

Then run:

```bash
flutter run -d linux
```

For a release build:

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/folio_reader
```

---

## 📦 Dependencies

All versions verified against pub.dev in **March 2026**.

| Package | Version | Purpose |
|---|---|---|
| `epub_view` | `^3.2.0` | Pure Flutter EPUB 2/3 renderer (no WebView) |
| `epubx` | `^4.0.0` | Low-level EPUB parser for metadata & cover extraction |
| `file_picker` | `^10.3.10` | Folder & file picker (SAF on Android, GTK on Linux) |
| `flutter_riverpod` | `^3.3.1` | Reactive state management |
| `shared_preferences` | `^2.3.5` | Settings & last-folder persistence |
| `google_fonts` | `^8.0.2` | Downloadable + cached font families |
| `path` | `^1.9.1` | Cross-platform path utilities |
| `path_provider` | `^2.1.5` | Platform-specific directory access |
| `permission_handler` | `^12.0.1` | Runtime storage permissions on Android |

---

## 🎨 Design Decisions

### Why `epub_view` instead of a WebView?
`epub_view` renders EPUB content as native Flutter widgets.  This means it
works on Linux desktop (which has no WebView), avoids the overhead of a
Chromium instance on Android, and gives full control over font rendering.

### Why Riverpod?
Riverpod's `StateNotifierProvider` makes it easy to share state (settings,
library list) between screens without `InheritedWidget` boilerplate or
`BuildContext` threading issues.  The `StateNotifier` pattern also maps cleanly
to the "load → mutate → persist" lifecycle of both the settings and library.

### Reading-mode theming
Rather than switching the app's global `ThemeData`, the reading mode is applied
_locally_ inside `ReaderScreen` using a `Theme` widget.  This means the home
screen and settings page always use the system light/dark theme, while only
the reader changes its background/text colour.

---

## 🔒 Android Permissions Explained

| Permission | Why it's needed |
|---|---|
| `READ_EXTERNAL_STORAGE` (≤ API 32) | Read `.epub` files from external storage on Android ≤ 12 |
| `MANAGE_EXTERNAL_STORAGE` (API 30+) | Required to browse arbitrary folders on Android 11+ without SAF |
| `WAKE_LOCK` | Honours the "keep screen on" setting |
| `INTERNET` | Google Fonts downloads font files on first use (cached offline after) |

---

## 🔧 Customisation Tips

**Adding more fonts** – open `lib/utils/theme_utils.dart` and add any
[Google Fonts](https://fonts.google.com/) name to `kAvailableFonts`.  The app
resolves font names at runtime via `google_fonts`, so no extra assets are needed.

**Changing the accent colour** – edit `kAccentColor` in `theme_utils.dart`.

**Extending settings** – add a field to `AppSettings`, update `toJson` /
`fromJson`, add a UI control in `settings_screen.dart`, and consume it in
`reader_screen.dart`.

---

## 📄 Licence

GPLv3 – see [LICENSE](LICENSE) for details.
