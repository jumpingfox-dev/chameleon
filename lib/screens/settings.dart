import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController(
    text: '''{
  "background": "#0d1117",
  "foreground": "#e6edf3",
  "primary": "#238636",
  "muted": "#161b22"
}''',
  );

  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FTextField.multiline(
            label: const Text('Paste Custom Theme JSON'),
            hint: '{"background": "#121212", ...}',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FButton(
            onPress: (){},
            child: const Text('Apply Theme'),
          ),
        ],
      ),
    );
  }
}