import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/font_controller.dart';
import '../utils/theme_controller.dart';
import '../utils/theme_presets.dart';
import '../widgets/custom_theme_editor.dart';

/// One entry per settings tab. Add a line here to add a tab.
typedef _SettingsTab = ({String label, Widget Function() build});

final _tabs = <_SettingsTab>[
  (label: 'Appearance', build: () => const _AppearanceCard()),
  // (label: 'Account', build: () => const _AccountCard()),
  // (label: 'Playback', build: () => const _PlaybackCard()),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => FScaffold(
    header: FHeader(
      title: Row(
        children: [
          const Text('Settings'),
          const SizedBox(width: 16),
          Expanded(
            // Scrolls sideways if there are more pills than fit.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    FButton(
                      variant: i == _index ? .primary : .outline,
                      size: .sm,
                      mainAxisSize: .min,
                      onPress: () => setState(() => _index = i),
                      child: Text(_tabs[i].label),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [_tabs[_index].build()],
    ),
  );
}

/// A bordered settings section with a title and subtitle, like the forui example.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => FCard(
    builder: (context, style, _) => Padding(
      padding: style.padding,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text(title, style: style.titleTextStyle),
          const SizedBox(height: 2),
          Text(subtitle, style: style.subtitleTextStyle),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

/// A font selector FSelect reusable widget
class _FontSelect extends StatelessWidget {
  const _FontSelect({required this.label, required this.value, required this.onChange});

  final String label;
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => FSelect<String>.searchBuilder(
    label: Text(label),
    format: (font) => font,
    filter: searchFonts,
    searchFieldProperties: const FSelectSearchFieldProperties(hint: 'Search Google Fonts'),
    contentBuilder: (context, _, fonts) => [
      for (final font in fonts)
            .item(
          // Each option is drawn in its own font as a live preview.
          title: Text(font, style: GoogleFonts.getFont(font)),
          value: font,
        ),
    ],
    control: FSelectControl.lifted(
      value: value,
      onChange: (font) {
        if (font != null) onChange(font);
      },
    ),
  );
}

/// Appearance Settings
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, fontController]),
    builder: (context, _) {
      final preset = themeController.value;

      return _SettingsCard(
        title: 'Appearance',
        subtitle: 'Choose a theme and fonts, or pick Custom to build your own colors.',
        children: [
          /// START: Font Picker
          _FontSelect(
            label: 'Heading Font',
            value: fontController.display,
            onChange: fontController.setDisplay,
          ),
          const SizedBox(height: 16),
          _FontSelect(
            label: 'Body Font',
            value: fontController.body,
            onChange: fontController.setBody,
          ),
          /// START: Font Picker
          const SizedBox(height: 16),
          /// START: Theme Select
          FSelect<ThemePreset>(
            label: const Text('Theme'),
            hint: 'Default',
            items: {for (final p in themeController.allPresets) p.label: p},
            control: FSelectControl.lifted(
              value: preset,
              onChange: (selected) {
                if (selected != null) themeController.select(selected);
              },
            ),
          ),
          if (preset.id == customThemeId) ...[
            const SizedBox(height: 16),
            const CustomThemeEditor(),
          ],
          /// END: Theme Select
        ],
      );
    },
  );
}