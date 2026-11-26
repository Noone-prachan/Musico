import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: MusicoPalette.canvas, child: child);
  }
}
