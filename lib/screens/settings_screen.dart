import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../utils/theme_utils.dart';

/// Settings grouped exactly like section 8 of the specification: the reading
/// mode, options for both modes, Book mode and Scroll mode.
///
/// Every change is written to [SharedPreferences] immediately by
/// [SettingsNotifier], so there is no Save button and closing the app keeps
/// the latest values.
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
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildPreviewCard(context, settings, brightness),

          // ── Mode ─────────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Mode',
            children: [_buildReaderModeSelector(context, settings, notifier)],
          ),

          // ── Both modes ───────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Both modes',
            children: [
              _buildSliderTile(
                context,
                label: 'Font size',
                value: settings.fontSize,
                min: AppSettings.minFontSize,
                max: AppSettings.maxFontSize,
                divisions: (AppSettings.maxFontSize - AppSettings.minFontSize)
                    .round(),
                displayValue: '${settings.fontSize.round()} px',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(fontSize: v)),
              ),
              _buildSliderTile(
                context,
                label: 'Line spacing',
                value: settings.lineHeight,
                min: AppSettings.minLineHeight,
                max: AppSettings.maxLineHeight,
                divisions:
                    ((AppSettings.maxLineHeight - AppSettings.minLineHeight) *
                            10)
                        .round(),
                displayValue: settings.lineHeight.toStringAsFixed(1),
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(lineHeight: v)),
              ),
              _buildSliderTile(
                context,
                label: 'Margins',
                value: settings.marginHorizontal,
                min: AppSettings.minMargin,
                max: AppSettings.maxMargin,
                divisions: (AppSettings.maxMargin - AppSettings.minMargin)
                    .round(),
                displayValue: '${settings.marginHorizontal.round()} px',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(marginHorizontal: v)),
              ),
              _buildThemeSelector(context, settings, notifier),
              _buildSwitchTile(
                context,
                title: 'Keep screen on',
                subtitle: 'Prevents the display from sleeping while reading.',
                value: settings.keepScreenOn,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(keepScreenOn: v)),
              ),
              _buildFontFamilyTile(context, settings, notifier),
              _buildTextAlignmentSelector(context, settings, notifier),
              _buildSwitchTile(
                context,
                title: 'Hyphenation',
                subtitle: 'Hyphenate justified text automatically.',
                value: settings.hyphenation,
                onChanged: settings.textAlign == TextAlign.justify
                    ? (v) => notifier.update((s) => s.copyWith(hyphenation: v))
                    : null,
              ),
              _buildHyphenationLanguageSelector(context, settings, notifier),
              _buildSwitchTile(
                context,
                title: 'Progress bar',
                subtitle: 'Show reading progress in the reader menu.',
                value: settings.showProgressBar,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(showProgressBar: v)),
              ),
            ],
          ),

          // ── Book mode ────────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Book mode',
            children: [
              _buildSwitchTile(
                context,
                title: 'Volume buttons turn pages',
                subtitle: 'Volume down goes forward, volume up goes back.',
                value: settings.volumeButtonsTurnPages,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(volumeButtonsTurnPages: v),
                ),
              ),
              _buildSwitchTile(
                context,
                title: 'Invert volume buttons',
                subtitle: 'Make volume up go forward instead.',
                value: settings.invertVolumeButtons,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(invertVolumeButtons: v)),
              ),
              _buildSwitchTile(
                context,
                title: 'Tap zones',
                subtitle:
                    'Tap the left edge to go back, the right edge forward.',
                value: settings.tapZones,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(tapZones: v)),
              ),
              _buildSliderTile(
                context,
                label: 'Tap zone width',
                value: settings.tapZoneWidth,
                min: AppSettings.minTapZoneWidth,
                max: AppSettings.maxTapZoneWidth,
                divisions:
                    (AppSettings.maxTapZoneWidth - AppSettings.minTapZoneWidth)
                        .round(),
                displayValue: '${settings.tapZoneWidth.round()}%',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(tapZoneWidth: v)),
              ),
              _buildSwitchTile(
                context,
                title: 'Swipe to turn page',
                subtitle:
                    'Swipe left for the next page, right for the previous.',
                value: settings.swipeToTurnPage,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(swipeToTurnPage: v)),
              ),
              _buildSwitchTile(
                context,
                title: 'Page animation',
                subtitle: 'Slide the page into place when turning.',
                value: settings.pageAnimation,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(pageAnimation: v)),
              ),
            ],
          ),

          // ── Scroll mode ──────────────────────────────────────────────
          _buildSection(
            context,
            title: 'Scroll mode',
            children: [
              _buildSliderTile(
                context,
                label: 'Scroll speed',
                value: settings.autoScrollSpeed,
                min: AppSettings.minScrollSpeed,
                max: AppSettings.maxScrollSpeed,
                divisions:
                    ((AppSettings.maxScrollSpeed - AppSettings.minScrollSpeed) /
                            5)
                        .round(),
                displayValue: '${settings.autoScrollSpeed.round()} px/s',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(autoScrollSpeed: v)),
              ),
              _buildSwitchTile(
                context,
                title: 'Tap to start or stop',
                subtitle:
                    'A tap starts automatic scrolling, another pauses it.',
                value: settings.tapToStartStop,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(tapToStartStop: v)),
              ),
              _buildSwitchTile(
                context,
                title: 'Volume buttons change speed',
                subtitle: 'Volume up is faster, volume down is slower.',
                value: settings.volumeButtonsChangeSpeed,
                onChanged: (v) => notifier.update(
                  (s) => s.copyWith(volumeButtonsChangeSpeed: v),
                ),
              ),
              _buildSwitchTile(
                context,
                title: 'Start automatically when book opens',
                subtitle: 'Begin scrolling as soon as a book is opened.',
                value: settings.scrollAutoStart,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(scrollAutoStart: v)),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              'Changes apply immediately and are saved automatically.',
              style: _subtitleStyle(context),
            ),
          ),
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
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: EdgeInsets.symmetric(
        horizontal: settings.marginHorizontal,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.10), width: 1),
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

  // ── Mode selectors ──────────────────────────────────────────────────────

  Widget _buildReaderModeSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final options = [
      (
        ReaderMode.book,
        'Book',
        Icons.auto_stories_rounded,
        'One page at a time',
      ),
      (
        ReaderMode.scroll,
        'Scroll',
        Icons.vertical_align_bottom_rounded,
        'Continuous text',
      ),
    ];
    return _buildChipRow(
      context,
      options.map((entry) {
        final (mode, label, icon, description) = entry;
        return _OptionChip(
          icon: icon,
          label: label,
          description: description,
          selected: settings.readerMode == mode,
          onTap: () => notifier.update((s) => s.copyWith(readerMode: mode)),
        );
      }).toList(),
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final options = [
      (ReadingMode.light, 'Light', Icons.light_mode_rounded),
      (ReadingMode.sepia, 'Sepia', Icons.tonality_rounded),
      (ReadingMode.dark, 'Dark', Icons.dark_mode_rounded),
    ];
    return _buildChipRow(
      context,
      options.map((entry) {
        final (mode, label, icon) = entry;
        return _OptionChip(
          icon: icon,
          label: label,
          selected: settings.readingMode == mode,
          onTap: () => notifier.update((s) => s.copyWith(readingMode: mode)),
        );
      }).toList(),
    );
  }

  Widget _buildTextAlignmentSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final options = [
      (TextAlign.left, 'Left', Icons.format_align_left_rounded),
      (TextAlign.justify, 'Justify', Icons.format_align_justify_rounded),
      (TextAlign.right, 'Right', Icons.format_align_right_rounded),
    ];
    return _buildChipRow(
      context,
      options.map((entry) {
        final (align, label, icon) = entry;
        return _OptionChip(
          icon: icon,
          label: label,
          selected: settings.textAlign == align,
          onTap: () => notifier.update((s) => s.copyWith(textAlign: align)),
        );
      }).toList(),
    );
  }

  Widget _buildChipRow(BuildContext context, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: chips
            .map(
              (chip) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: chip,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Font family picker ──────────────────────────────────────────────────

  Widget _buildFontFamilyTile(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    return ListTile(
      title: Text('Font family', style: _tileTextStyle(context)),
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
                (font) => DropdownMenuItem(
                  value: font,
                  child: Text(
                    font,
                    style: GoogleFonts.getFont(font, fontSize: 13),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  // ── Hyphenation language selector ───────────────────────────────────────

  Widget _buildHyphenationLanguageSelector(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    const languages = [
      ('en_us', 'English (US)'),
      ('it', 'Italian'),
      ('de_1996', 'German'),
      ('fr', 'French'),
      ('es', 'Spanish'),
      ('pt', 'Portuguese'),
    ];

    final isEnabled =
        settings.hyphenation && settings.textAlign == TextAlign.justify;

    return ListTile(
      title: Text('Hyphenation language', style: _tileTextStyle(context)),
      subtitle: Text(
        languages
            .firstWhere(
              (lang) => lang.$1 == settings.hyphenationLanguage,
              orElse: () => ('en_us', 'English (US)'),
            )
            .$2,
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

  // ── Shared rows ─────────────────────────────────────────────────────────

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: _tileTextStyle(context)),
      subtitle: Text(subtitle, style: _subtitleStyle(context)),
      value: value,
      activeThumbColor: kAccentColor,
      onChanged: onChanged,
    );
  }

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
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
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: kAccentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ── Section builder ─────────────────────────────────────────────────────

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
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  TextStyle _tileTextStyle(BuildContext context) =>
      GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w500);

  TextStyle _subtitleStyle(BuildContext context) => GoogleFonts.lato(
    fontSize: 12,
    color: Theme.of(context).textTheme.bodyMedium?.color,
  );
}

// ── Option chip ────────────────────────────────────────────────────────────

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? kAccentColor
        : Theme.of(context).textTheme.bodyMedium?.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
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
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 2),
              Text(
                description!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.lato(
                  fontSize: 9,
                  color: color?.withValues(alpha: 0.65),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
