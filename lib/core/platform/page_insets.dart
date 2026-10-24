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
/// Room above a page's content, below the app's top bar.
///
/// Like [pageSides], put it inside scroll views (in their `padding`) where there is one.
double pageTop(BuildContext context) => ScreenType.of(context).isPhone ? 8 : 16;

/// Room below a page's content: [extra], plus whatever floats over the bottom of the page (the
/// bottom bar on phones), so the last of it can scroll clear.
double pageBottom(BuildContext context, [double extra = 16]) => MediaQuery.paddingOf(context).bottom + extra;
