import 'package:material_ui/material_ui.dart';

import '../../core/platform/screen_type.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_presets.dart';
import '../../theme/app_icons.dart';
import '../../theme/font_controller.dart';
import '../library/genres.dart';
import '../../core/theming/server_themes.dart';
import 'choice_picker.dart';
import '../../theme/theme.dart';
import '../../widgets/remote_text_field.dart';

String _pad3(int n) => n.toString().padLeft(3, '0');

/// Custom, in Settings › Appearance › Theme: one of the server's themes, if it has any, or
/// your own, from a base hue, an accent hue, vibrance and depth (or a theme code).
class CustomThemeEditor extends StatelessWidget {
  const CustomThemeEditor({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([themeController, serverThemes]),
    builder: (context, _) {
      final servers = themeController.serverPresets;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (servers.isNotEmpty) _ServerThemes(themes: servers),
          // Your own colors: only while no server theme is picked.
          if (!ThemeController.isServerTheme(themeController.value)) ...[
            if (servers.isNotEmpty) const SizedBox(height: 12),
            _SeedEditor(seed: themeController.seed),
          ],
        ],
      );
    },
  );
}

/// The server's themes (see docs/themes.md), or none: your own colors, set below.
class _ServerThemes extends StatelessWidget {
  const _ServerThemes({required this.themes});

  final List<ThemePreset> themes;

  @override
  Widget build(BuildContext context) {
    final current = themeController.value;
    final selected = ThemeController.isServerTheme(current) ? themes.where((t) => t.id == current.id).firstOrNull : null;
    return ChoiceField(
      label: 'Server Themes',
      value: selected?.label ?? 'None',
      onPress: () async {
        // Each theme by its id, in a one-item record, so "None" (null) can be told apart from
        // closing the list (and the one in use matched, though the server's themes are read
        // afresh as it opens).
        final picked = await showChoicePicker<(String?,)>(
          context: context,
          title: 'Server Themes',
          selected: (selected?.id,),
          // The server asked first (a few seconds at most), so themes added or changed since it
          // was last read are listed as they are now.
          search: (_) async {
            await serverThemes.refresh().timeout(const Duration(seconds: 4), onTimeout: () {});
            return [(null,), for (final t in themeController.serverPresets) (t.id,)];
          },
          itemBuilder: (context, t) =>
              _ServerThemeItem(theme: themeController.serverPresets.where((p) => p.id == t.$1).firstOrNull),
        );
        if (picked == null) return;
        final theme = themeController.serverPresets.where((p) => p.id == picked.$1).firstOrNull;
        // Its looks replace any you chose yourself: say which, first.
        final changes = _lookChanges(serverThemes.sheet.themeNamed(theme?.label));
        if (changes.isNotEmpty && context.mounted && !await _confirmLooks(context, theme!.label, changes)) return;
        await themeController.select(theme ?? themeController.custom);
        for (final change in changes) {
          await change.apply();
        }
      },
    );
  }

  /// Asks before [theme]'s looks replace yours. True to go ahead.
  static Future<bool> _confirmLooks(BuildContext context, String theme, List<_LookChange> changes) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Use $theme\'s settings?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('$theme sets these, and will replace what you chose:'),
              for (final c in changes) Text('${c.what}: ${c.yours} → ${c.theirs}'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Use theme')),
          ],
        ),
      ) ??
      false;
}

/// One of a server theme's looks (see themeLookSettings) that's different from what you chose
/// yourself: what it is, yours, the theme's, and how to make the theme's yours.
typedef _LookChange = ({String what, String yours, String theirs, Future<void> Function() apply});

/// [theme]'s looks that differ from ones you chose yourself. (Ones you never changed follow the
/// theme as it is.)
List<_LookChange> _lookChanges(ServerTheme? theme) {
  if (theme == null) return const [];
  String? value(String key) => theme.settings[key]?.trim().replaceAll(RegExp(r'''^["']|["']$'''), '').trim();
  final changes = <_LookChange>[];
  if (value('headingFont') case final font? when FontController.exists(font)) {
    if (fontController.ownDisplay case final mine? when mine != font) {
      changes.add((what: 'Heading font', yours: mine, theirs: font, apply: () => fontController.setDisplay(font)));
    }
  }
  if (value('bodyFont') case final font? when FontController.exists(font)) {
    if (fontController.ownBody case final mine? when mine != font) {
      changes.add((what: 'Body font', yours: mine, theirs: font, apply: () => fontController.setBody(font)));
    }
  }
  if (IconStyle.values.asNameMap()[value('icons')] case final style?) {
    if (iconController.own case final mine? when mine != style) {
      changes.add((what: 'Icons', yours: mine.label, theirs: style.label, apply: () => iconController.select(style)));
    }
  }
  if (GenreCardStyle.values.asNameMap()[value('genreCards')] case final style?) {
    if (genreCards.own case final mine? when mine != style) {
      changes.add((what: 'Genre cards', yours: mine.label, theirs: style.label, apply: () => genreCards.select(style)));
    }
  }
  return changes;
}

/// A server theme in the list: its name, who made it, and whether its pictures load.
class _ServerThemeItem extends StatelessWidget {
  const _ServerThemeItem({required this.theme});

  final ThemePreset? theme;

  @override
  Widget build(BuildContext context) {
    final preset = theme;
    if (preset == null) return const Text('None');
    final server = serverThemes.sheet.themeNamed(preset.label);
    final broken = server == null ? 0 : serverThemes.brokenLinks(server).length;
    final notes = [
      if (server?.author case final author?) 'by $author',
      if (broken > 0) '$broken ${broken == 1 ? "picture doesn't" : "pictures don't"} load',
    ];
    if (notes.isEmpty) return Text(preset.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(preset.label),
        Text(
          notes.join(' · '),
          style: context.text.bodySmall?.copyWith(color: broken > 0 ? context.colors.error : context.colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Your own ────────────────────────────────────────────────────────────────

class _SeedEditor extends StatefulWidget {
  const _SeedEditor({required this.seed});

  final ThemeSeed seed;

  @override
  State<_SeedEditor> createState() => _SeedEditorState();
}

class _SeedEditorState extends State<_SeedEditor> {
  final _code = TextEditingController();
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _set(ThemeSeed seed) => themeController.applySeed(seed);

  void _loadCode() {
    final seed = ThemeSeed.parse(_code.text);
    if (seed == null) {
      setState(() => _codeError = 'Enter 8 digits, e.g. 28533082');
      return;
    }
    setState(() => _codeError = null);
    _code.clear();
    _set(seed);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.seed;
    Color hueSwatch(int hue) =>
        HSLColor.fromAHSL(1, hue.toDouble(), 0.8, 0.55).toColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stepper(
          label: 'Base Hue',
          value: _pad3(s.baseHue),
          swatch: hueSwatch(s.baseHue),
          onPrev: () => _set(s.copyWith(baseHue: (s.baseHue - 15) % 360)),
          onNext: () => _set(s.copyWith(baseHue: (s.baseHue + 15) % 360)),
        ),
        _Stepper(
          label: 'Accent Hue',
          value: _pad3(s.accentHue),
          swatch: hueSwatch(s.accentHue),
          onPrev: () => _set(s.copyWith(accentHue: (s.accentHue - 15) % 360)),
          onNext: () => _set(s.copyWith(accentHue: (s.accentHue + 15) % 360)),
        ),
        _Stepper(
          label: 'Vibrance',
          value: '${s.vibrance}',
          onPrev: s.vibrance > 0
              ? () => _set(s.copyWith(vibrance: s.vibrance - 1))
              : null,
          onNext: s.vibrance < 9
              ? () => _set(s.copyWith(vibrance: s.vibrance + 1))
              : null,
        ),
        _Stepper(
          label: 'Depth',
          value: '${s.depth}',
          onPrev: s.depth > 0
              ? () => _set(s.copyWith(depth: s.depth - 1))
              : null,
          onNext: s.depth < 9
              ? () => _set(s.copyWith(depth: s.depth + 1))
              : null,
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            text: 'Theme Code: ',
            children: [
              TextSpan(
                text:
                    '${_pad3(s.baseHue)}-${_pad3(s.accentHue)}-${s.vibrance}-${s.depth}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            RemoteTextField(
              builder: (context, focusNode, highlighted) => TextField(
                controller: _code,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _loadCode(),
                decoration: InputDecoration(
                  hintText: 'Enter a code, e.g. 28533082',
                  error: _codeError == null ? null : Text(_codeError!),
                  enabledBorder: highlighted ? remoteFieldBorder(context) : null,
                ),
              ),
            ),
            FilledButton(
              onPressed: _loadCode,
              child: const Text('Load'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onPrev,
    required this.onNext,
    this.swatch,
  });

  final String label;
  final String value;
  final VoidCallback?
  onPrev; // null disables the button at the ends of the range
  final VoidCallback? onNext;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final isPhone = ScreenType.of(context).isPhone;
    final density = isPhone ? VisualDensity.standard : VisualDensity.compact;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (swatch != null)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
          IconButton(
            visualDensity: density,
            onPressed: onPrev,
            icon: Icon(appIcons.stepBack, fill: 1),
          ),
          SizedBox(width: isPhone ? 48 : 40,
              child: Text(value, textAlign: TextAlign.center)),
          IconButton(
            visualDensity: density,
            onPressed: onNext,
            icon: Icon(appIcons.stepForward, fill: 1),
          ),
        ],
      ),
    );
  }
}
