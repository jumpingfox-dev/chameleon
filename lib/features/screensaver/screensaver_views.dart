part of 'screensaver.dart';

// The screensaver styles. Everything moves or changes now and then, so nothing sits on one
// spot of the screen for long (TVs, OLED ones especially, can keep a ghost of a still image).

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

/// The screensaver in [style], fading in over the app, with [ScreensaverSettings.dim] on top.
class _Screensaver extends StatefulWidget {
  const _Screensaver({required this.style, required this.settings});

  final ScreensaverStyle style;
  final ScreensaverSettings settings;

  @override
  State<_Screensaver> createState() => _ScreensaverState();
}

class _ScreensaverState extends State<_Screensaver> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    // Artwork needs someone signed in; without, the clock instead.
    final signedIn = jellyfin.client != null;
    final style = !signedIn && (widget.style == ScreensaverStyle.backdrops || widget.style == ScreensaverStyle.posters)
        ? ScreensaverStyle.clock
        : widget.style;

    // Off: the app stays in view, just dimmed.
    if (style == ScreensaverStyle.off) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
        child: const ColoredBox(color: Color(0xBF000000)),
      );
    }

    return FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
      child: ColoredBox(
        color: _black,
        child: DefaultTextStyle(
          style: context.text.bodyLarge!.copyWith(color: _white),
          child: Stack(
            fit: StackFit.expand,
            children: [
              switch (style) {
                ScreensaverStyle.backdrops => _Backdrops(settings: s),
                ScreensaverStyle.posters => _PosterWall(settings: s),
                ScreensaverStyle.clock => _ClockScreen(settings: s),
                ScreensaverStyle.logo || ScreensaverStyle.off => _FloatingLogo(settings: s),
              },
              if (s.dim > 0) IgnorePointer(child: ColoredBox(color: _black.withValues(alpha: s.dim / 100))),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Artwork ─────────────────────────────────────────────────────────────────

/// A random set of [content] that has [imageType] art (a backdrop, or a poster).
Future<List<JellyfinItem>> _artwork(ScreensaverContent content, String imageType) async {
  final client = jellyfin.client;
  if (client == null) return const [];
  try {
    final items = await client.items.listEach(
      types: content.itemTypes,
      sortBy: const ['Random'],
      limit: 80, // more than needed, since some won't have the art
      fields: const ['Genres'],
    );
    return items.where((item) {
      if (imageType == JellyfinImagesApi.typeBackdrop) {
        return (item.raw['BackdropImageTags'] as List?)?.isNotEmpty ?? false;
      }
      return item.imageTags.containsKey(imageType);
    }).toList();
  } catch (e) {
    debugPrint('Screensaver artwork: $e');
    return const [];
  }
}

String _backdropUrl(JellyfinItem item) => jellyfin.client!.images.url(
  itemId: item.id,
  type: JellyfinImagesApi.typeBackdrop,
  tag: (item.raw['BackdropImageTags'] as List).first as String,
  fillWidth: 1920,
  quality: 90,
);

/// The color for [ScreensaverColor]: [phase] (0–1) moves [ScreensaverColor.changing] round the
/// color wheel, starting from the theme's color.
Color _tint(BuildContext context, ScreensaverColor color, double phase) => switch (color) {
  ScreensaverColor.white => _white,
  ScreensaverColor.theme => context.colors.primary,
  ScreensaverColor.changing => () {
    final start = HSVColor.fromColor(context.colors.primary);
    return HSVColor.fromAHSV(1, (start.hue + phase * 360) % 360, 0.55, 1).toColor();
  }(),
};

// ─── Clock text ──────────────────────────────────────────────────────────────

/// The time (and date), updated on the minute.
class _Clock extends StatefulWidget {
  const _Clock({required this.format, this.date = false, this.size = 1, this.color = _white});

  final ClockFormat format;
  final bool date;
  final double size;
  final Color color;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _tick = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final twentyFour = switch (widget.format) {
      ClockFormat.device => MediaQuery.alwaysUse24HourFormatOf(context),
      ClockFormat.twelve => false,
      ClockFormat.twentyFour => true,
    };
    final minutes = _now.minute.toString().padLeft(2, '0');
    final String time;
    String? suffix;
    if (twentyFour) {
      time = '${_now.hour.toString().padLeft(2, '0')}:$minutes';
    } else {
      final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
      time = '$hour:$minutes';
      suffix = _now.hour < 12 ? 'am' : 'pm';
    }
    final shadow = [const Shadow(blurRadius: 12, color: Color(0x99000000))];
    final big = context.text.displayLarge!.copyWith(
      fontSize: 72 * widget.size,
      height: 1,
      color: widget.color,
      fontWeight: FontWeight.w300,
      shadows: shadow,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: time,
            children: [
              if (suffix != null)
                TextSpan(text: ' $suffix', style: big.copyWith(fontSize: 28 * widget.size)),
            ],
          ),
          style: big,
        ),
        if (widget.date)
          Padding(
            padding: EdgeInsets.only(top: 8 * widget.size),
            child: Text(
              '${_days[_now.weekday - 1]}, ${_months[_now.month - 1]} ${_now.day}',
              style: context.text.titleLarge!.copyWith(
                fontSize: 22 * widget.size,
                color: widget.color.withValues(alpha: 0.8),
                shadows: shadow,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Backdrops ───────────────────────────────────────────────────────────────

/// Library artwork, one at a time, with a slow zoom: every few seconds the picture fades to black
/// and the next fades in. The title's logo sits bottom left and the clock top right.
class _Backdrops extends StatefulWidget {
  const _Backdrops({required this.settings});

  final ScreensaverSettings settings;

  @override
  State<_Backdrops> createState() => _BackdropsState();
}

class _BackdropsState extends State<_Backdrops> {
  List<JellyfinItem>? _items; // null while loading
  int _index = 0;
  Timer? _next;

  /// False while fading to black between pictures.
  bool _shown = true;
  static const _fade = Duration(milliseconds: 900);

  ScreensaverSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _artwork(_s.backdropContent, JellyfinImagesApi.typeBackdrop).then((items) {
      if (!mounted) return;
      setState(() => _items = items);
      _schedule();
    });
  }

  void _schedule() {
    _next?.cancel();
    final items = _items ?? const [];
    if (items.length < 2) return;
    _next = Timer(Duration(seconds: _s.backdropSeconds), () async {
      final upcoming = (_index + 1) % items.length;
      // Loaded first, so it fades in whole rather than drawing in strips.
      try {
        await precacheImage(NetworkImage(_backdropUrl(items[upcoming])), context);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _shown = false);
      await Future<void>.delayed(_fade);
      if (!mounted) return;
      setState(() {
        _index = upcoming;
        _shown = true;
      });
      _schedule();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const SizedBox.expand(); // black until the artwork's in
    if (items.isEmpty) return _FloatingLogo(settings: _s);
    final item = items[_index];
    final edge = ScreenType.of(context).isPhone ? 24.0 : 48.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The picture and its details fade out to black together, and the next fade in.
        AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: _fade,
          curve: Curves.easeInOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _KenBurns(
                key: ValueKey(item.id),
                moving: _s.backdropMotion,
                seconds: _s.backdropSeconds + 2,
                // Each picture drifts a different way.
                from: Alignment(_index.isEven ? -0.4 : 0.4, -0.2),
                child: Image.network(
                  _backdropUrl(item),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              // Shade under the details, so they read over a bright picture.
              if (_s.backdropDetails)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.center,
                      colors: [Color(0xAA000000), Color(0x00000000)],
                    ),
                  ),
                ),
              if (_s.backdropDetails)
                Positioned(left: edge, bottom: edge, child: _TitleArt(item: item)),
            ],
          ),
        ),
        // The clock stays put, over a shade of its own.
        if (_s.backdropClock) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 0.9,
                colors: [Color(0x88000000), Color(0x00000000)],
              ),
            ),
          ),
          Positioned(right: edge, top: edge, child: _Clock(format: _s.clockFormat, size: 0.6)),
        ],
      ],
    );
  }
}

/// A slow zoom and drift across [child], over [seconds].
class _KenBurns extends StatelessWidget {
  const _KenBurns({super.key, required this.moving, required this.seconds, required this.from, required this.child});

  final bool moving;
  final int seconds;
  final Alignment from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!moving) return SizedBox.expand(child: child);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(seconds: seconds),
      curve: Curves.linear,
      child: SizedBox.expand(child: child),
      builder: (context, t, child) => Transform.scale(
        scale: 1.04 + 0.1 * t,
        alignment: Alignment.lerp(from, -from, t),
        child: child,
      ),
    );
  }
}

/// The title's logo (or name) and its genres, centred on each other: as wide as the logo's box.
class _TitleArt extends StatelessWidget {
  const _TitleArt({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final logoTag = item.imageTags[JellyfinImagesApi.typeLogo];
    final genres = ((item.raw['Genres'] as List?) ?? const []).whereType<String>().take(3).join('  ·  ');
    const shadow = [Shadow(blurRadius: 12, color: Color(0x99000000))];
    final name = Text(
      item.name,
      textAlign: TextAlign.center,
      style: context.text.headlineMedium!.copyWith(color: _white, shadows: shadow),
    );
    final size = TitleLogo.screensaver(ScreenType.of(context).isPhone);
    return SizedBox(
      width: size.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 10,
        children: [
          if (logoTag == null)
            name
          else
            TitleLogo(
              itemId: item.id,
              tag: logoTag,
              size: size,
              fallback: name,
              alignment: Alignment.bottomCenter,
            ),
          if (genres.isNotEmpty)
            Text(
              genres,
              textAlign: TextAlign.center,
              style: context.text.titleMedium!.copyWith(color: const Color(0xDDFFFFFF), shadows: shadow),
            ),
        ],
      ),
    );
  }
}

// ─── Poster wall ─────────────────────────────────────────────────────────────

/// Rows of posters sliding sideways, each row the other way from the one above.
class _PosterWall extends StatefulWidget {
  const _PosterWall({required this.settings});

  final ScreensaverSettings settings;

  @override
  State<_PosterWall> createState() => _PosterWallState();
}

class _PosterWallState extends State<_PosterWall> with SingleTickerProviderStateMixin {
  List<JellyfinItem>? _items; // null while loading
  late final Ticker _ticker;
  final _offset = ValueNotifier<double>(0); // seconds since it started, times the speed

  ScreensaverSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _offset.value = elapsed.inMicroseconds / 1e6 * _s.posterSpeed.factor);
    _artwork(_s.posterContent, JellyfinImagesApi.typePrimary).then((items) {
      if (!mounted) return;
      setState(() => _items = items);
      if (items.isNotEmpty) _ticker.start();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const SizedBox.expand(); // black until the artwork's in
    if (items.isEmpty) return _FloatingLogo(settings: _s);
    final rows = _s.posterRows;
    const gap = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = (constraints.maxHeight - gap * (rows + 1)) / rows;
        final posterWidth = rowHeight * 2 / 3;
        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                for (var r = 0; r < rows; r++)
                  Padding(
                    padding: const EdgeInsets.only(top: gap),
                    child: SizedBox(
                      height: rowHeight,
                      child: _PosterRow(
                        // Each row its own share of the posters, starting at a different one.
                        items: [for (var i = r; i < items.length; i += rows) items[i]],
                        posterWidth: posterWidth,
                        gap: gap,
                        offset: _offset,
                        reverse: r.isOdd,
                        // Rows move at slightly different speeds, so they don't line up.
                        speed: 40 * (1 + r * 0.15),
                      ),
                    ),
                  ),
              ],
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(radius: 1.2, colors: [Color(0x00000000), Color(0x99000000)]),
              ),
            ),
            if (_s.posterClock)
              Align(
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
                    child: _Clock(format: _s.clockFormat, date: true, size: 0.9),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One row of the poster wall, sliding by [speed] pixels per unit of [offset], and wrapping
/// round so it never runs out.
class _PosterRow extends StatelessWidget {
  const _PosterRow({
    required this.items,
    required this.posterWidth,
    required this.gap,
    required this.offset,
    required this.reverse,
    required this.speed,
  });

  final List<JellyfinItem> items;
  final double posterWidth;
  final double gap;
  final ValueListenable<double> offset;
  final bool reverse;
  final double speed;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final step = posterWidth + gap;
    final length = step * items.length; // one full pass of the row
    return LayoutBuilder(
      builder: (context, constraints) {
        // Enough copies of the row to cover the screen while one slides off.
        final copies = (constraints.maxWidth / length).ceil() + 1;
        final posters = [for (var c = 0; c < copies; c++) ...items];
        return ClipRect(
          child: ValueListenableBuilder<double>(
            valueListenable: offset,
            builder: (context, value, child) {
              final shift = (value * speed) % length;
              return Transform.translate(offset: Offset(reverse ? shift - length : -shift, 0), child: child);
            },
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in posters)
                    Padding(
                      padding: EdgeInsets.only(right: gap),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          jellyfin.client!.images.url(
                            itemId: item.id,
                            type: JellyfinImagesApi.typePrimary,
                            tag: item.imageTags[JellyfinImagesApi.typePrimary]!,
                            fillWidth: 400,
                          ),
                          width: posterWidth,
                          height: posterWidth * 3 / 2,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              SizedBox(width: posterWidth, height: posterWidth * 3 / 2, child: const ColoredBox(color: Color(0xFF1A1A1A))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Clock ───────────────────────────────────────────────────────────────────

/// A large clock that fades to a new spot every minute.
class _ClockScreen extends StatefulWidget {
  const _ClockScreen({required this.settings});

  final ScreensaverSettings settings;

  @override
  State<_ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<_ClockScreen> with SingleTickerProviderStateMixin {
  final _random = math.Random();
  Alignment _spot = Alignment.center;
  bool _visible = true;
  Timer? _move;
  String? _background;
  double _phase = 0; // for changing colors

  ScreensaverSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _move = Timer.periodic(const Duration(seconds: 60), (_) => _relocate());
    if (_s.clockArtwork) {
      _artwork(_s.backdropContent, JellyfinImagesApi.typeBackdrop).then((items) {
        if (mounted && items.isNotEmpty) setState(() => _background = _backdropUrl(items.first));
      });
    }
  }

  Future<void> _relocate() async {
    setState(() => _visible = false);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _spot = Alignment(_random.nextDouble() * 1.4 - 0.7, _random.nextDouble() * 1.4 - 0.7);
      _phase = (_phase + 0.08) % 1;
      _visible = true;
    });
  }

  @override
  void dispose() {
    _move?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_background case final url?)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.decal),
          child: Image.network(url, fit: BoxFit.cover, color: const Color(0x80000000), colorBlendMode: BlendMode.darken),
        ),
      AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 800),
        child: Align(
          alignment: _spot,
          child: _Clock(
            format: _s.clockFormat,
            date: _s.clockDate,
            size: _s.clockSize.scale * (ScreenType.of(context).isPhone ? 0.8 : 1.4),
            color: _tint(context, _s.clockColor, _phase),
          ),
        ),
      ),
    ],
  );
}

// ─── Floating logo ───────────────────────────────────────────────────────────

/// The logo gliding around and bouncing off the edges, changing color at each bounce.
class _FloatingLogo extends StatefulWidget {
  const _FloatingLogo({required this.settings});

  final ScreensaverSettings settings;

  @override
  State<_FloatingLogo> createState() => _FloatingLogoState();
}

class _FloatingLogoState extends State<_FloatingLogo> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _random = math.Random();
  Offset _position = const Offset(40, 40);
  late Offset _direction;
  Duration _last = Duration.zero;
  Size _area = Size.zero;
  Size _logo = Size.zero;
  double _phase = 0;

  ScreensaverSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    final angle = math.pi / 6 + _random.nextDouble() * math.pi / 6; // never straight across
    _direction = Offset(math.cos(angle), math.sin(angle));
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_area.isEmpty || _logo.isEmpty) return;
    final speed = 90 * _s.logoSpeed.factor;
    var next = _position + _direction * speed * seconds;
    var bounced = false;
    final maxX = _area.width - _logo.width, maxY = _area.height - _logo.height;
    if (next.dx <= 0 || next.dx >= maxX) {
      _direction = Offset(-_direction.dx, _direction.dy);
      next = Offset(next.dx.clamp(0, math.max(0, maxX)), next.dy);
      bounced = true;
    }
    if (next.dy <= 0 || next.dy >= maxY) {
      _direction = Offset(_direction.dx, -_direction.dy);
      next = Offset(next.dx, next.dy.clamp(0, math.max(0, maxY)));
      bounced = true;
    }
    setState(() {
      _position = next;
      if (bounced) _phase = (_phase + 0.17) % 1;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = 320 * _s.logoSize.scale * (ScreenType.of(context).isPhone ? 0.6 : 1);
    // The wordmark is about 5.5 times as wide as it's tall.
    _logo = Size(width, width / 5.47);
    final Widget logo = switch (_s.logoColor) {
      ScreensaverColor.theme => AppLogo(
        asset: 'assets/images/text_logo.svg',
        colorAsset: 'assets/images/text_logo_color.svg',
        height: _logo.height,
      ),
      final color => AppLogo.picture(
        'assets/images/text_logo.svg',
        height: _logo.height,
        tint: _tint(context, color, _phase),
      ),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        _area = constraints.biggest;
        return Stack(
          children: [
            Positioned(left: _position.dx, top: _position.dy, child: logo),
          ],
        );
      },
    );
  }
}
