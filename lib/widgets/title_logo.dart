import 'package:dart_jellyfin/dart_jellyfin.dart';
import 'package:material_ui/material_ui.dart';

import '../core/jellyfin/jellyfin_controller.dart';

/// A title's logo, as large as fits in [width] by [height]: a typical wide logo fills the width,
/// a squarer one the height. Whatever size the file is (a small one is enlarged, rather than
/// drawn small), it sits at the box's bottom left. [fallback] (the name) shows if it won't load.
///
/// The sizes in use: [screensaver], [hero] (a title's page), [banner] (Home's carousel). Most
/// logos are about three times as wide as they're tall, so they use the full width.
class TitleLogo extends StatelessWidget {
  const TitleLogo({
    super.key,
    required this.itemId,
    required this.tag,
    required this.size,
    required this.fallback,
  });

  final String itemId;
  final String tag;
  final Size size;
  final Widget fallback;

  static Size screensaver(bool isPhone) => isPhone ? const Size(200, 90) : const Size(320, 140);
  static Size hero(bool isPhone) => isPhone ? const Size(190, 80) : const Size(340, 140);
  static Size banner(bool isPhone) => isPhone ? const Size(160, 64) : const Size(280, 110);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: Image.network(
      jellyfin.client!.images.url(
        itemId: itemId,
        type: JellyfinImagesApi.typeLogo,
        tag: tag,
        fillWidth: (size.width * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
      fit: BoxFit.contain, // enlarged or shrunk to the box, whichever it needs
      alignment: Alignment.bottomLeft,
      errorBuilder: (_, _, _) => Align(alignment: Alignment.bottomLeft, child: fallback),
    ),
  );
}
