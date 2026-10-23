import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme.dart';
import 'trailers.dart';

/// Says that trailers from YouTube play in YouTube's own player, under YouTube's Terms of
/// Service and Google's Privacy Policy, with a link to each (as YouTube requires of apps that
/// embed its player). Where a link can't be opened (a TV without a browser), its address shows.
class YouTubeNotice extends StatelessWidget {
  const YouTubeNotice({super.key});

  static Future<void> _open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open $url on another device.')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(
        'Trailers from YouTube play in YouTube\'s own player. By playing them you agree to the '
        'YouTube Terms of Service, and Google\'s Privacy Policy applies.',
        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => _open(context, youTubeTermsUrl),
            child: const Text('YouTube Terms of Service'),
          ),
          TextButton(
            onPressed: () => _open(context, googlePrivacyUrl),
            child: const Text('Google Privacy Policy'),
          ),
        ],
      ),
    ],
  );
}
