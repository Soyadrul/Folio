import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../utils/theme_utils.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final brightness = MediaQuery.of(context).platformBrightness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: const BackButton(),
        actions: [
          TextButton(
            onPressed: () => notifier.reset(),
            child: Text(
              'Reset',
              style: GoogleFonts.lato(
                color: kAccentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        children: [
          // ── Preview card ──────────────────────────────────────────────
          _buildPreviewCard(context, settings, brightness),

          const SizedBox(height: 8),

          // ── Reading mode ──────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Display Mode',
            children: [_buildReadingModeSelector(context, settings, notifier)],
          ),

          // ── Typography ────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Typography',
            children: [
              _buildFontFamilyTile(context, settings, notifier),
              _buildTextAlignmentSelector(context, settings, notifier),
              SwitchListTile(
                title: Text('Hyphenation', style: _tileTextStyle(context)),
                subtitle: Text(
                  'Enable automatic hyphenation for justified text.',
                  style: _subtitleStyle(context),
                ),
                value: settings.hyphenation,
                activeThumbColor: kAccentColor,
                onChanged: settings.textAlign == TextAlign.justify
                    ? (v) => notifier.update((s) => s.copyWith(hyphenation: v))
                    : null,
              ),
              _buildHyphenationLanguageSelector(context, settings, notifier),
              _buildSliderTile(
                context,
                label: 'Font Size',
                value: settings.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                displayValue: '${settings.fontSize.toInt()}px',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(fontSize: v)),
              ),
              _buildSliderTile(
                context,
                label: 'Line Spacing',
                value: settings.lineHeight,
                min: 1.0,
                max: 2.5,
                divisions: 15,
                displayValue: settings.lineHeight.toStringAsFixed(1),
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(lineHeight: v)),
              ),
            ],
          ),

          // ── Layout ────────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Layout',
            children: [
              _buildSliderTile(
                context,
                label: 'Side Margins',
                value: settings.marginHorizontal,
                min: 8,
                max: 60,
                divisions: 26,
                displayValue: '${settings.marginHorizontal.toInt()}px',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(marginHorizontal: v)),
              ),
            ],
          ),

          // ── Behaviour ─────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Behaviour',
            children: [
              SwitchListTile(
                title: Text('Keep screen on while reading',
                    style: _tileTextStyle(context)),
                subtitle: Text(
                  'Prevents the display from dimming.',
                  style: _subtitleStyle(context),
                ),
                value: settings.keepScreenOn,
                activeThumbColor: kAccentColor,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(keepScreenOn: v)),
              ),
              SwitchListTile(
                title: Text('Show progress bar',
                    style: _tileTextStyle(context)),
                subtitle: Text(
                  'Displays reading progress at the bottom.',
                  style: _subtitleStyle(context),
                ),
                value: settings.showProgressBar,
                activeThumbColor: kAccentColor,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showProgressBar: v)),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Live preview ────────────────────────────────────────────────────────

  Widget _buildPreviewCard(
    BuildContext context,
    AppSettings settings,
    Brightness systemBrightness,
  ) {
    final bg = readerBackground(settings.readingMode, systemBrightness);
    final fg = readerTextColor(settings.readingMode, systemBrightness);
    final bodyStyle = readerBodyTextStyle(
      settings: settings,
      systemBrightness: systemBrightness,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: EdgeInsets.symmetric(
        horizontal: settings.marginHorizontal,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fg.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: GoogleFonts.lato(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: fg.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'It was the best of times, it was the worst of times, '
            'it was the age of wisdom, it was the age of foolishness, '
            'it was the epoch of belief, it was the epoch of incredulity.',
            style: bodyStyle,
            textAlign: settings.textAlign,
            textWidthBasis: TextWidthBasis.parent,
          ),
        ],
      ),
    );
  }

  // ── Reading mode selector ────────────────────────────────────────────────

  Widget _buildReadingModeSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    const modes = [
      (ReadingMode.auto, 'Auto', Icons.brightness_auto_rounded),
      (ReadingMode.light, 'Light', Icons.light_mode_rounded),
      (ReadingMode.dark, 'Dark', Icons.dark_mode_rounded),
      (ReadingMode.sepia, 'Sepia', Icons.tonality_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: modes.map((entry) {
          final (mode, label, icon) = entry;
          final isSelected = settings.readingMode == mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ModeChip(
                icon: icon,
                label: label,
                selected: isSelected,
                onTap: () =>
                    notifier.update((s) => s.copyWith(readingMode: mode)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Font family picker ────────────────────────────────────────────────────

  Widget _buildFontFamilyTile(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    return ListTile(
      title: Text('Font Family', style: _tileTextStyle(context)),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: settings.fontFamily,
          style: GoogleFonts.lato(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
          onChanged: (font) {
            if (font != null) {
              notifier.update((s) => s.copyWith(fontFamily: font));
            }
          },
          items: kAvailableFonts
              .map(
                (f) => DropdownMenuItem(
                  value: f,
                  child: Text(
                    f,
                    style: GoogleFonts.getFont(f, fontSize: 13),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  // ── Text alignment selector ───────────────────────────────────────────────

  Widget _buildTextAlignmentSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    const alignments = [
      (TextAlign.left, 'Left', Icons.format_align_left_rounded),
      (TextAlign.justify, 'Justify', Icons.format_align_justify_rounded),
      (TextAlign.right, 'Right', Icons.format_align_right_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: alignments.map((entry) {
          final (align, label, icon) = entry;
          final isSelected = settings.textAlign == align;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _AlignmentChip(
                icon: icon,
                label: label,
                selected: isSelected,
                onTap: () =>
                    notifier.update((s) => s.copyWith(textAlign: align)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Hyphenation language selector ─────────────────────────────────────────

  Widget _buildHyphenationLanguageSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    // Available hyphenation languages
    const languages = [
      ('en_us', 'English (US)'),
      ('it', 'Italian'),
      ('de_1996', 'German'),
      ('fr', 'French'),
      ('es', 'Spanish'),
      ('pt', 'Portuguese'),
    ];

    final isEnabled = settings.hyphenation && settings.textAlign == TextAlign.justify;

    return ListTile(
      title: Text('Hyphenation Language', style: _tileTextStyle(context)),
      subtitle: Text(
        languages.firstWhere(
          (lang) => lang.$1 == settings.hyphenationLanguage,
          orElse: () => ('en_us', 'English (US)'),
        ).$2,
        style: _subtitleStyle(context),
      ),
      trailing: isEnabled
          ? PopupMenuButton<(String, String)>(
              onSelected: (lang) => notifier.update(
                (s) => s.copyWith(hyphenationLanguage: lang.$1),
              ),
              itemBuilder: (context) => languages
                  .map(
                    (lang) => PopupMenuItem<(String, String)>(
                      value: lang,
                      child: Text(lang.$2),
                    ),
                  )
                  .toList(),
            )
          : const Text('Requires justified text'),
      enabled: isEnabled,
    );
  }

  // ── Slider tile ───────────────────────────────────────────────────────────

  Widget _buildSliderTile(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(label, style: _tileTextStyle(context)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: kAccentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayValue,
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kAccentColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: kAccentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ── Section builder ───────────────────────────────────────────────────────

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.lato(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: kAccentColor,
            ),
          ),
        ),
        ...children,
        Divider(
          height: 1,
          color: Theme.of(context)
              .dividerColor
              .withValues(alpha: 0.5),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TextStyle _tileTextStyle(BuildContext context) =>
      GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w500);

  TextStyle _subtitleStyle(BuildContext context) => GoogleFonts.lato(
        fontSize: 12,
        color: Theme.of(context).textTheme.bodyMedium?.color,
      );
}

// ── Mode chip widget ───────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? kAccentColor.withValues(alpha: 0.15)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kAccentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? kAccentColor
                  : Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? kAccentColor
                    : Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Alignment chip widget ───────────────────────────────────────────────────

class _AlignmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AlignmentChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? kAccentColor.withValues(alpha: 0.15)
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? kAccentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected
                  ? kAccentColor
                  : Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? kAccentColor
                    : Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
