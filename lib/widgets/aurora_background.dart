import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// A quiet, solid canvas that keeps album art and controls in focus.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MusicoPalette.canvas,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-.95, -1.05),
                    radius: 1.05,
                    colors: [
                      MusicoPalette.forest.withValues(alpha: .16),
                      MusicoPalette.canvas.withValues(alpha: 0),
                    ],
                    stops: const [0, .62],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.15, 1.15),
                    radius: .95,
                    colors: [
                      MusicoPalette.terracotta.withValues(alpha: .10),
                      MusicoPalette.canvas.withValues(alpha: 0),
                    ],
                    stops: const [0, .55],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// A translucent, blurred surface used for the rail, top bar and player dock.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    super.key,
    this.radius = 24,
    this.padding,
    this.tint,
    this.borderColor,
    this.blur = 22,
    this.shadows,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final Color? borderColor;
  final double blur;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint ?? MusicoPalette.glass,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor ?? MusicoPalette.glass),
            ),
            child: padding == null
                ? child
                : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}
