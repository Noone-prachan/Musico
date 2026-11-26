import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class AnimeScreen extends StatelessWidget {
  const AnimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 52 : 26, 33, wide ? 52 : 26, 35),
      children: [
        Text('Anime', style: Theme.of(context).textTheme.displayLarge),
        const SizedBox(height: 6),
        Text(
          'Anime streaming needs a supported, licensed provider.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: MusicoPalette.muted),
        ),
      ],
    );
  }
}
