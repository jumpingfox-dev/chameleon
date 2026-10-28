import 'package:material_ui/material_ui.dart';

import 'screen_type.dart';

/// On wider screens, extra room on each side.
const _wideInset = 20.0;

/// Side padding for page content: [extra] (16 by default) plus room for a camera cutout
/// or rounded corners, which is 0 on most screens. Wider screens get [_wideInset] more on both
/// sides, so the page sits evenly between them.
///
/// Put it *inside* scroll views (as their `padding`) rather than around them, so content
/// starts clear of the edge but can still scroll right up to it.
EdgeInsets pageSides(BuildContext context, {double extra = 16}) {
  final insets = MediaQuery.paddingOf(context);
  final wide = ScreenType.of(context).isPhone ? 0.0 : _wideInset;
  return EdgeInsets.only(left: insets.left + extra + wide, right: insets.right + extra + wide);
}
/// The room the app's top bar takes at the top of the page right now: all of it at the page's
/// top, less as it moves up with the page, down to just the status bar's (the page runs up
/// under it). A page's fixed parts (Search's box, the A–Z column) keep clear by
/// this much, moving up as the bar goes.
final topBarRoom = ValueNotifier<double>(0);

/// [child], kept clear of the app's top bar, moving up with it as the page scrolls ([topBarRoom]).
class ClearOfHiddenTopBar extends StatelessWidget {
  const ClearOfHiddenTopBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: topBarRoom,
    // Moving with the bar as the page scrolls (see AppShell), so not animated.
    builder: (context, room, child) => Padding(padding: EdgeInsets.only(top: room), child: child),
    child: child,
  );
}

/// The room the app's top bar takes when it shows, given to the pages under it: it floats over
/// them, and they start their content below it (see [pageTop]). Its hiding then doesn't change
/// a page's size, so nothing on the page moves.
class TopBarSpace extends InheritedWidget {
  const TopBarSpace({super.key, required this.height, required super.child});

  final double height;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopBarSpace>()?.height ?? 0;

  @override
  bool updateShouldNotify(TopBarSpace old) => old.height != height;
}

/// Room above a page's content: clear of the app's top bar (which floats over the page), and a
/// little more.
///
/// Like [pageSides], put it inside scroll views (in their `padding`) where there is one, so the
/// content scrolls up under the bar once it's gone. A page's fixed parts take [pageTopGap]
/// instead, inside a [ClearOfHiddenTopBar].
double pageTop(BuildContext context) => TopBarSpace.of(context) + pageTopGap(context);

/// The little room between the top bar and a page's content.
double pageTopGap(BuildContext context) => ScreenType.of(context).isPhone ? 8 : 16;

/// Room below a page's content: [extra], plus whatever floats over the bottom of the page (the
/// bottom bar on phones), so the last of it can scroll clear.
double pageBottom(BuildContext context, [double extra = 16]) => MediaQuery.paddingOf(context).bottom + extra;
