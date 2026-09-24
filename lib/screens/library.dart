import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

/// Shows one library, or everything in one genre.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.libraryId, this.genre});

  final String? libraryId;
  final String? genre;

  @override
  Widget build(BuildContext context) => FScaffold(
    child: Center(child: Text(genre != null ? 'Genre: $genre' : 'Library: $libraryId')),
  );
}