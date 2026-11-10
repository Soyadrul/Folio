import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/book.dart';
import '../providers/library_provider.dart';
import '../utils/android_storage.dart';
import '../utils/theme_utils.dart';
import '../widgets/book_card.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Folder picker ──────────────────────────────────────────────────────

  /// Checks storage access and asks for it when Android has not granted it.
  Future<bool> _ensureStoragePermission() async {
    return requestStorageAccess();
  }

  Future<void> _pickFolder() async {
    if (!await _ensureStoragePermission()) {
      if (mounted) _showPermissionDeniedSnackbar();
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your books folder',
    );
    if (path != null && mounted) {
      await ref.read(libraryProvider.notifier).scanFolder(path);
    }
  }

  Future<void> _grantPermissionAndRescan() async {
    if (!await _ensureStoragePermission()) {
      if (mounted) _showPermissionDeniedSnackbar();
      return;
    }
    if (!mounted) return;
    final folder = ref.read(libraryProvider).folderPath;
    if (folder != null) {
      await ref.read(libraryProvider.notifier).refresh();
    } else {
      await _pickFolder();
    }
  }

  void _showPermissionDeniedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Storage permission is required to access your books.'),
        action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
      ),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _openBook(Book book) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);

    final filteredBooks = _searchQuery.isEmpty
        ? library.books
        : library.books.where((b) {
            final q = _searchQuery.toLowerCase();
            return b.title.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(library),
          if (library.folderPath != null) _buildSearchBar(),
          if (library.warningMessage != null) _buildWarning(library),
          _buildBody(library, filteredBooks),
        ],
      ),
    );
  }

  // ── Sliver app bar ─────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(LibraryState library) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 130,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
        title: Text(
          'Folio',
          style: GoogleFonts.playfairDisplay(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF2EFE8),
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1A2E), Color(0xFF2A2040)],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 48),
              child: Text(
                'Your Library',
                style: GoogleFonts.lato(
                  fontSize: 13,
                  color: const Color(0xFF9090B0),
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (library.folderPath != null)
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh library',
            onPressed: library.isLoading
                ? null
                : () => ref.read(libraryProvider.notifier).refresh(),
          ),
        IconButton(
          icon: const Icon(Icons.folder_open_rounded),
          tooltip: 'Change library folder',
          onPressed: _pickFolder,
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          onPressed: _openSettings,
        ),
      ],
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────

  SliverToBoxAdapter _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
          decoration: InputDecoration(
            hintText: 'Search title or author…',
            hintStyle: GoogleFonts.lato(fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Theme.of(context).cardTheme.color,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  // ── Main content ────────────────────────────────────────────────────────

  Widget _buildWarning(LibraryState library) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kAccentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAccentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: kAccentColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                library.warningMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
            if (library.needsPermission)
              TextButton(
                onPressed: _grantPermissionAndRescan,
                child: const Text('Grant'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LibraryState library, List<Book> books) {
    // ① Loading
    if (library.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // ② Error
    if (library.errorMessage != null) {
      return SliverFillRemaining(
        child: _buildMessage(
          icon: Icons.error_outline_rounded,
          title: 'Could not load books',
          subtitle: library.errorMessage!,
          action: TextButton.icon(
            onPressed: library.needsPermission
                ? _grantPermissionAndRescan
                : _pickFolder,
            icon: Icon(
              library.needsPermission
                  ? Icons.lock_open_rounded
                  : Icons.folder_open_rounded,
            ),
            label: Text(
              library.needsPermission ? 'Grant permission' : 'Choose folder',
            ),
          ),
        ),
      );
    }

    // ③ No folder selected yet
    if (library.folderPath == null) {
      return SliverFillRemaining(child: _buildWelcome());
    }

    // ④ Folder selected but empty
    if (books.isEmpty) {
      return SliverFillRemaining(
        child: _buildMessage(
          icon: Icons.menu_book_rounded,
          title: _searchQuery.isEmpty ? 'No books found' : 'No results',
          subtitle: _searchQuery.isEmpty
              ? 'Add .epub files to\n${library.folderPath}'
              : 'Try a different search term.',
          action: _searchQuery.isEmpty
              ? TextButton.icon(
                  onPressed: () => ref.read(libraryProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                )
              : null,
        ),
      );
    }

    // ⑤ Book grid
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.58,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => BookCard(
            key: ValueKey(books[index].path),
            book: books[index],
            onTap: () => _openBook(books[index]),
          ),
          childCount: books.length,
        ),
      ),
    );
  }

  // ── Empty states ────────────────────────────────────────────────────────

  Widget _buildWelcome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: kAccentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 48,
                color: kAccentColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Folio',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Select a folder that contains your EPUB files to get started. '
              'Sub-folders are scanned automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAccentColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(
                'Choose Library Folder',
                style: GoogleFonts.lato(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: kAccentColor.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}
