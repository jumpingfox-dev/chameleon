import 'package:material_ui/material_ui.dart';

import '../../core/jellyfin/jellyfin_controller.dart';
import '../../theme/theme.dart';
import '../library/genres.dart';
import '../settings/choice_picker.dart';
import '../settings/switch_setting.dart';
import 'home_layout.dart';
import 'section_settings.dart';

/// The settings for one kind of section ([type]) on Home, or for one row of a kind that can be
/// added more than once ([settingsKey]: its id). Behind a row's cog while editing Home (see
/// [showSectionSettings]).
class SectionSettingsForm extends StatelessWidget {
  const SectionSettingsForm({super.key, required this.type, required this.settingsKey});

  final HomeModuleType type;

  /// Where they're kept (see SectionSettings.keyFor).
  final String settingsKey;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sectionSettings, genreCards, jellyfin]),
    builder: (context, _) {
      final o = sectionSettings.of(type, settingsKey);
      final isProgress = type == HomeModuleType.continueWatching || type == HomeModuleType.nextUp;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          SwitchSetting(label: 'Show its title', value: o.showTitle, onChange: (v) => o.set('showTitle', v)),

          // ── How many ──
          if (type == HomeModuleType.carousel)
            _Choice<int>(
              label: 'Items to cycle through',
              value: o.limit,
              options: o.limitOptions,
              format: (n) => '$n',
              onChange: (n) => o.set('limit', n),
            )
          else if (type == HomeModuleType.genres)
            ..._genres(context, o)
          else if (type != HomeModuleType.myMedia)
            _Choice<int>(
              label: 'How many to show',
              value: o.limit,
              options: o.limitOptions,
              format: (n) => '$n',
              onChange: (n) => o.set('limit', n),
            ),

          // ── Featured ──
          if (type == HomeModuleType.carousel) ...[
            _Choice<FeaturedKinds>(
              label: 'What it features',
              value: o.featuredKinds,
              options: FeaturedKinds.values,
              format: (k) => k.label,
              onChange: (k) => o.set('kinds', k),
            ),
            _Choice<int>(
              label: 'Each one shows for',
              value: o.featuredSeconds,
              options: SectionOptions.featuredSecondsOptions,
              format: (s) => '$s seconds',
              onChange: (s) => o.set('seconds', s),
            ),
          ],

          // ── My Media, Genres ──
          if (type == HomeModuleType.myMedia || type == HomeModuleType.genres)
            SwitchSetting(
              label: 'Name each card',
              description: 'Its name under it, as Continue Watching does.',
              value: o.cardNames,
              onChange: (v) => o.set('cardNames', v),
            ),
          if (type == HomeModuleType.myMedia)
            _Choice<CardLook>(
              label: 'Look',
              value: o.look,
              options: CardLook.values,
              format: (l) => l.label,
              onChange: (l) => o.set('look', l),
            ),

          // ── Continue Watching, Next Up ──
          if (isProgress) ...[
            SwitchSetting(
              label: 'Name the episodes',
              description: 'The show under each episode.',
              value: o.episodeTitles,
              onChange: (v) => o.set('episodeTitles', v),
            ),
            _Choice<EpisodeTitleStyle>(
              label: 'And under the show',
              value: o.episodeTitleStyle,
              options: EpisodeTitleStyle.values,
              format: (s) => s.label,
              onChange: (s) => o.set('episodeTitleStyle', s),
              enabled: o.episodeTitles,
            ),
          ],
          if (type == HomeModuleType.continueWatching) ...[
            SwitchSetting(
              label: 'Name the movies',
              description: 'Their thumbnails usually show their name already.',
              value: o.movieTitles,
              onChange: (v) => o.set('movieTitles', v),
            ),
            _Choice<int?>(
              label: 'Leave out what you haven\'t touched in',
              value: o.continueCutoffDays,
              options: SectionOptions.continueCutoffOptions,
              format: (d) => d == null ? 'Never leave anything out' : _days(d),
              onChange: (d) => o.set('cutoffDays', d),
            ),
          ],
          if (type == HomeModuleType.nextUp) ...[
            _Choice<Object>(
              label: 'Leave out shows not watched in',
              value: o.nextUpCutoff,
              options: SectionOptions.nextUpCutoffOptions,
              format: (c) => switch (c) {
                'server' => 'As set in Jellyfin',
                'never' => 'Never leave anything out',
                final int d => _days(d),
                _ => '$c',
              },
              onChange: (c) => o.set('cutoff', c),
            ),
            _Choice<String>(
              label: 'Shows you\'ve watched through, again',
              value: o.nextUpRewatching,
              options: SectionOptions.nextUpRewatchingOptions,
              format: (r) => switch (r) {
                'server' => 'As set in Jellyfin',
                'on' => 'Include them',
                _ => 'Leave them out',
              },
              onChange: (r) => o.set('rewatching', r),
            ),
          ],

          // ── Favorites ──
          if (type == HomeModuleType.favorites) ...[
            _Choice<String>(
              label: 'What it shows',
              value: o.favoriteKinds.isEmpty
                  ? 'Nothing'
                  : [for (final k in o.favoriteKinds) SectionOptions.favoriteKindOptions[k] ?? k].join(', '),
              options: const [],
              format: (s) => s,
              onChange: (_) {},
              onPress: () async {
                final picked = await showMultiChoicePicker<String>(
                  context: context,
                  title: 'What it shows',
                  options: SectionOptions.favoriteKindOptions.keys.toList(),
                  label: (k) => SectionOptions.favoriteKindOptions[k]!,
                  selected: o.favoriteKinds,
                );
                if (picked != null) await o.set('kinds', picked);
              },
            ),
            // A name under each kind it shows, or not.
            for (final kind in o.favoriteKinds)
              SwitchSetting(
                label: 'Name the ${(SectionOptions.favoriteKindOptions[kind] ?? kind).toLowerCase()}',
                value: o.favoriteNamed(kind),
                onChange: (v) => o.setFavoriteNamed(kind, v),
              ),
            _Choice<FavoritesSort>(
              label: 'In order of',
              value: o.favoritesSort,
              options: FavoritesSort.values,
              format: (s) => s.label,
              onChange: (s) => o.set('sort', s),
            ),
          ],

          // ── Because You Watched ──
          if (type == HomeModuleType.becauseYouWatched)
            _Choice<BecauseBasis>(
              label: 'Based on',
              value: o.becauseBasis,
              options: BecauseBasis.values,
              format: (b) => b.label,
              onChange: (b) => o.set('basis', b),
            ),
        ],
      );
    },
  );

  static String _days(int d) => switch (d) {
    30 => 'a month',
    90 => '3 months',
    180 => '6 months',
    365 => 'a year',
    _ => '$d days',
  };

  /// The Genres section: its look (as on the Genres page), how many, and which.
  List<Widget> _genres(BuildContext context, SectionOptions o) {
    final all = jellyfin.genres;
    final count = o.genreCount;
    return [
      // (Their look is the Genres page's too, so it's set in Settings.)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'To change how genres look, go to Settings › Appearance › Genre cards.',
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ),
      _Choice<int?>(
        label: 'How many to show',
        value: count,
        // All of them, or any number short of that.
        options: [null, for (var n = 1; n < all.length; n++) n],
        format: (n) => n == null ? 'All of them' : '$n',
        onChange: (n) => o.set('genreCount', n),
      ),
      _Choice<GenrePick>(
        label: 'Which',
        value: o.genrePick,
        options: GenrePick.values,
        format: (p) => p.label,
        onChange: (p) => o.set('pick', p),
        enabled: count != null,
      ),
      if (o.genrePick == GenrePick.chosen)
        _Choice<String>(
          label: 'Chosen genres',
          value: o.chosenGenres.isEmpty ? 'None yet' : o.chosenGenres.join(', '),
          options: const [],
          format: (s) => s,
          onChange: (_) {},
          enabled: count != null,
          onPress: () async {
            final picked = await showMultiChoicePicker<String>(
              context: context,
              title: 'Chosen genres',
              options: all,
              label: (g) => g,
              selected: o.chosenGenres,
            );
            if (picked != null) await o.set('chosen', picked);
          },
        ),
      // Chosen, but not as many as it's set to show: it shows what it can, and says so.
      if (o.genrePick == GenrePick.chosen && count != null && o.chosenGenres.length != count)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            o.chosenGenres.length < count
                ? "${o.chosenGenres.length} chosen, but it's set to show $count: it shows the ${o.chosenGenres.length}."
                : "${o.chosenGenres.length} chosen, but it's set to show $count: it shows the first $count.",
            style: context.text.bodySmall?.copyWith(color: context.colors.error),
          ),
        ),
    ];
  }
}

/// One choice: shows what it's set to; selecting it opens a list to pick from ([onPress] in
/// place of that, for a list to tick). Greyed out and passed over when not [enabled].
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.format,
    required this.onChange,
    this.enabled = true,
    this.onPress,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) format;
  final ValueChanged<T> onChange;
  final bool enabled;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final field = ChoiceField(
      label: label,
      value: format(value),
      onPress: onPress ??
          () async {
            // Each choice in a one-item record, so one that's null ("All of them") can be told
            // apart from closing the list (which gives null back).
            final picked = await showChoicePicker<(T,)>(
              context: context,
              title: label,
              selected: (value,),
              search: (_) async => [for (final o in options) (o,)],
              itemBuilder: (context, o) => Text(format(o.$1)),
            );
            if (picked != null) onChange(picked.$1);
          },
    );
    if (enabled) return field;
    return ExcludeFocus(child: IgnorePointer(child: Opacity(opacity: 0.4, child: field)));
  }
}

/// A row's (or a kind of section's) settings, in a dialog: from its cog while editing Home.
Future<void> showSectionSettings(BuildContext context, HomeModule module, String title) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: SectionSettingsForm(type: module.type, settingsKey: SectionSettings.keyFor(module)),
      ),
    ),
    actions: [
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
    ],
  ),
);
