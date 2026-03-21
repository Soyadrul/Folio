import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';
import '../utils/theme_utils.dart';

/// Displays one book as a card with a cover image (or a placeholder), title,
/// author, and an optional progress indicator.
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasProgress = book.lastProgress > 0.01;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cover image ──────────────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(10)),
                child: book.coverImage != null
                    ? Image.memory(
                        book.coverImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                      )
                    : _buildPlaceholder(context),
              ),
            ),

            // ── Progress bar (thin strip) ────────────────────────────────
            if (hasProgress)
              LinearProgressIndicator(
                value: book.lastProgress,
                minHeight: 3,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(kAccentColor),
              ),

            // ── Metadata ─────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.color,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.lato(
                      fontSize: 11,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when no cover image exists – a decorative placeholder.
  Widget _buildPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2A2A3A), const Color(0xFF1A1A28)]
              : [const Color(0xFFE8E0D0), const Color(0xFFD5CABC)],
        ),
      ),
      child: Stack(
        children: [
          // Subtle decorative lines to mimic book pages.
          Positioned.fill(
            child: CustomPaint(painter: _PageLinesPainter(isDark: isDark)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                book.title,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF9090A8)
                      : const Color(0xFF6A5F50),
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints subtle horizontal lines to suggest book pages in the placeholder.
class _PageLinesPainter extends CustomPainter {
  final bool isDark;
  const _PageLinesPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 0.8;

    const spacing = 14.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(16, y),
        Offset(size.width - 16, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageLinesPainter old) => old.isDark != isDark;
}
