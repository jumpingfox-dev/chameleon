import 'package:material_ui/material_ui.dart';

import '../utils/orientation.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.itemId});

  final String itemId;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    AppOrientation.player();
  }

  @override
  void dispose() {
    AppOrientation.menus(); // back to portrait menus, whichever way the player was closed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFF000000),
    child: Center(child: Text('Video goes here')), // your video player widget
  );
}