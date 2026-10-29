part of 'settings.dart';

/// The screensaver's settings (Appearance › Screensaver): which one, when, and each style's own options.
class _ScreensaverCard extends StatelessWidget {
  const _ScreensaverCard();

  static const _gap = SizedBox(height: 16);

  static String _minutes(int n) => switch (n) {
    1 => '1 minute',
    < 60 => '$n minutes',
    60 => '1 hour',
    _ => '${n ~/ 60} hours',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: screensaverSettings,
    builder: (context, _) {
      final s = screensaverSettings;
      void update(void Function(ScreensaverSettings s) edit) => s.change(edit);

      Widget contentPicker(ScreensaverContent value, void Function(ScreensaverSettings s, ScreensaverContent c) set) =>
          _PickerSetting<ScreensaverContent>(
            label: 'Artwork from',
            value: value,
            options: ScreensaverContent.values,
            format: (c) => c.label,
            onChange: (c) => update((s) => set(s, c)),
          );

      Widget clockFormatPicker() => _PickerSetting<ClockFormat>(
        label: 'Clock',
        value: s.clockFormat,
        options: ClockFormat.values,
        format: (f) => f.label,
        onChange: (f) => update((s) => s.clockFormat = f),
      );

      Widget speedPicker(ScreensaverSpeed value, void Function(ScreensaverSettings s, ScreensaverSpeed v) set) =>
          _PickerSetting<ScreensaverSpeed>(
            label: 'Speed',
            value: value,
            options: ScreensaverSpeed.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => set(s, v)),
          );

      Widget sizePicker(ScreensaverSize value, void Function(ScreensaverSettings s, ScreensaverSize v) set) =>
          _PickerSetting<ScreensaverSize>(
            label: 'Size',
            value: value,
            options: ScreensaverSize.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => set(s, v)),
          );

      Widget colorPicker(ScreensaverColor value, void Function(ScreensaverSettings s, ScreensaverColor v) set) =>
          _PickerSetting<ScreensaverColor>(
            label: 'Color',
            value: value,
            options: ScreensaverColor.values,
            format: (v) => v.label,
            onChange: (v) => update((s) => set(s, v)),
          );

      // Its settings for the Screensaver page under Appearance (which has the heading): the
      // style's own options under headings of their own, on the same page.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PickerSetting<ScreensaverStyle>(
            label: 'Style',
            value: s.style,
            options: ScreensaverStyle.values,
            format: (v) => v.label,
            itemBuilder: (context, v) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.label),
                Text(
                  v.description,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
            onChange: (v) => update((s) => s.style = v),
          ),
          // Off: the screen dims instead, after its own wait.
          if (s.style == ScreensaverStyle.off) ...[
            _gap,
            _PickerSetting<int>(
              label: 'Dim the screen after',
              value: s.dimAfter,
              options: screensaverDimAfterOptions,
              format: (n) => n == 0 ? 'Never' : _minutes(n),
              onChange: (n) => update((s) => s.dimAfter = n),
            ),
            if (s.dimAfter > 0) ...[
              _gap,
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => showScreensaver(ScreensaverStyle.off),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Preview'),
                ),
              ),
            ],
          ],
          if (s.style != ScreensaverStyle.off) ...[
            _gap,
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => showScreensaver(s.style),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview'),
              ),
            ),
            _gap,
            _PickerSetting<int>(
              label: 'Start after',
              value: s.startAfter,
              options: screensaverStartOptions,
              format: _minutes,
              onChange: (n) => update((s) => s.startAfter = n),
            ),
            _gap,
            _gap,
            _PickerSetting<int>(
              label: 'Dim',
              value: s.dim,
              options: screensaverDimOptions,
              format: (v) => v == 0 ? 'Off' : '$v% darker',
              onChange: (v) => update((s) => s.dim = v),
            ),

            // ── The chosen style's own options ──
            ...switch (s.style) {
              ScreensaverStyle.backdrops => [
                const _SectionTitle('Backdrops', description: 'Artwork from your libraries, one at a time.', inline: true),
                contentPicker(s.backdropContent, (s, c) => s.backdropContent = c),
                _gap,
                _PickerSetting<int>(
                  label: 'Change every',
                  value: s.backdropSeconds,
                  options: backdropSecondsOptions,
                  format: (n) => n < 60 ? '$n seconds' : '${n ~/ 60} minute',
                  onChange: (n) => update((s) => s.backdropSeconds = n),
                ),
                _gap,
                SwitchSetting(
                  label: 'Slow zoom',
                  description: 'Each picture drifts and zooms in a little.',
                  value: s.backdropMotion,
                  onChange: (v) => update((s) => s.backdropMotion = v),
                ),
                SwitchSetting(
                  label: 'Show the title',
                  description: 'Its logo or name, and genres.',
                  value: s.backdropDetails,
                  onChange: (v) => update((s) => s.backdropDetails = v),
                ),
                SwitchSetting(
                  label: 'Show the time',
                  value: s.backdropClock,
                  onChange: (v) => update((s) => s.backdropClock = v),
                ),
                if (s.backdropClock) ...[_gap, clockFormatPicker()],
              ],
              ScreensaverStyle.posters => [
                const _SectionTitle('Poster wall', description: 'Rows of posters drifting across the screen.', inline: true),
                contentPicker(s.posterContent, (s, c) => s.posterContent = c),
                _gap,
                _SliderSetting(
                  label: 'Rows',
                  value: s.posterRows,
                  min: 2,
                  max: 5,
                  format: (v) => '$v',
                  onChange: (v) => update((s) => s.posterRows = v),
                ),
                _gap,
                speedPicker(s.posterSpeed, (s, v) => s.posterSpeed = v),
                _gap,
                SwitchSetting(
                  label: 'Show the time',
                  description: 'In the middle, with the date.',
                  value: s.posterClock,
                  onChange: (v) => update((s) => s.posterClock = v),
                ),
                if (s.posterClock) ...[_gap, clockFormatPicker()],
              ],
              ScreensaverStyle.clock => [
                const _SectionTitle('Clock', description: 'Moves to a new spot every minute.', inline: true),
                clockFormatPicker(),
                _gap,
                sizePicker(s.clockSize, (s, v) => s.clockSize = v),
                _gap,
                colorPicker(s.clockColor, (s, v) => s.clockColor = v),
                _gap,
                SwitchSetting(
                  label: 'Show the date',
                  value: s.clockDate,
                  onChange: (v) => update((s) => s.clockDate = v),
                ),
                SwitchSetting(
                  label: 'Artwork behind',
                  description: 'A blurred backdrop from your libraries instead of black.',
                  value: s.clockArtwork,
                  onChange: (v) => update((s) => s.clockArtwork = v),
                ),
              ],
              ScreensaverStyle.logo => [
                const _SectionTitle('Floating logo', description: 'Bounces off the edges of the screen.', inline: true),
                sizePicker(s.logoSize, (s, v) => s.logoSize = v),
                _gap,
                speedPicker(s.logoSpeed, (s, v) => s.logoSpeed = v),
                _gap,
                colorPicker(s.logoColor, (s, v) => s.logoColor = v),
              ],
              ScreensaverStyle.off => const <Widget>[],
            },
          ],
        ],
      );
    },
  );
}
