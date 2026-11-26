import 'package:material_ui/material_ui.dart';

import '../models/media_title.dart';
import '../theme/app_theme.dart';

void showMusicoToast(
  BuildContext context, {
  required String message,
  bool isError = false,
  IconData? icon,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: isError ? MusicoPalette.error : MusicoPalette.surface,
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(
            icon ??
                (isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded),
            color: isError ? MusicoPalette.white : MusicoPalette.olive,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? MusicoPalette.white : MusicoPalette.ink,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class Overline extends StatelessWidget {
  const Overline(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? MusicoPalette.muted,
        fontFamily: 'IBM Plex Mono',
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: .55,
        height: 1.2,
      ),
    );
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? MusicoPalette.muted),
        const SizedBox(width: 6),
        Flexible(child: text),
      ],
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    required this.detail,
    super.key,
    this.trailing,
  });

  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: MusicoPalette.muted),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.background,
    this.foreground,
    this.dot,
  });

  final String label;
  final Color? background;
  final Color? foreground;
  final bool? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background ?? MusicoPalette.canvasAlt,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot ?? false) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground ?? MusicoPalette.forestLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground ?? MusicoPalette.softInk,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class SplitFlapLabel extends StatelessWidget {
  const SplitFlapLabel({required this.value, super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 29,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: MusicoPalette.forest,
        border: Border.all(color: MusicoPalette.forestLight),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ClipRect(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.7),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
            ),
            child: Text(
              value,
              key: ValueKey<String>(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MusicoPalette.white,
                fontFamily: 'IBM Plex Mono',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? prettyFormat(String value) {
  switch (value) {
    case 'TV':
      return 'Series';
    case 'TV_SHORT':
      return 'Short series';
    case 'MOVIE':
      return 'Movie';
    case 'ONA':
      return 'Web series';
    case 'OVA':
      return 'OVA';
    case 'SPECIAL':
      return 'Special';
    case 'MUSIC':
      return 'Music';
    default:
      return null;
  }
}

String schedulePhrase(MediaTitle title) {
  final airing = title.nextAiring;
  if (airing != null) {
    final local = airing.airingAt;
    final formattedTime = TimeOfDay.fromDateTime(local).format24h;
    final sameDay =
        DateTime.now().year == local.year &&
        DateTime.now().month == local.month &&
        DateTime.now().day == local.day;
    final day = sameDay
        ? 'Today'
        : local.day == DateTime.now().add(const Duration(days: 1)).day
        ? 'Tomorrow'
        : _shortDate(local);
    return '$day · Episode ${airing.episode} · $formattedTime';
  }
  if (title.startDate != null) {
    return '${_shortDate(title.startDate!)} · Premiere';
  }
  return 'Release date not announced';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

extension _TimeOfDayFormat on TimeOfDay {
  String get format24h {
    final minuteValue = minute.toString().padLeft(2, '0');
    final hourValue = hour.toString().padLeft(2, '0');
    return '$hourValue:$minuteValue';
  }
}

String countdown(DateTime dateTime) {
  final difference = dateTime.difference(DateTime.now());
  if (difference.isNegative) return 'Expected';
  if (difference.inDays > 0) {
    final remainderHours = difference.inHours % 24;
    return 'In ${difference.inDays}d ${remainderHours}h';
  }
  if (difference.inHours > 0) {
    return 'In ${difference.inHours}h ${difference.inMinutes % 60}m';
  }
  if (difference.inMinutes > 0) return 'In ${difference.inMinutes} min';
  return 'Airing shortly';
}

class PosterArtwork extends StatelessWidget {
  const PosterArtwork({
    required this.imageUrl,
    required this.title,
    super.key,
    this.width,
    this.height,
    this.rounded = 11,
  });

  final String? imageUrl;
  final String title;
  final double? width;
  final double? height;
  final double rounded;

  @override
  Widget build(BuildContext context) {
    final clip = BorderRadius.circular(rounded);
    return ClipRRect(
      borderRadius: clip,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: MusicoPalette.canvasAlt),
          child: imageUrl == null
              ? _PosterFallback(title: title)
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) {
                    return _PosterFallback(title: title);
                  },
                ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(decoration: BoxDecoration(color: MusicoPalette.sky)),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: Container(width: 7, color: MusicoPalette.terracotta),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Text(
              title.split(RegExp(r'\s+')).take(3).join('\n'),
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MusicoPalette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AnimatedPress extends StatefulWidget {
  const AnimatedPress({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
