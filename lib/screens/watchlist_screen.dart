import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/media_title.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    final datedTitles =
        appState.watchlist
            .where((title) => _watchlistDate(title) != null)
            .toList()
          ..sort((first, second) {
            return _watchlistDate(first)!.compareTo(_watchlistDate(second)!);
          });
    final undatedTitles = appState.watchlist
        .where((title) => _watchlistDate(title) == null)
        .toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 52 : 26, 33, wide ? 52 : 26, 35),
      children: [
        _WatchlistHeading(appState: appState),
        const SizedBox(height: 22),
        _ReminderRow(appState: appState),
        if (appState.errorMessage != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: MusicoPalette.error,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appState.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: MusicoPalette.error),
                ),
              ),
              TextButton(
                onPressed: appState.dismissError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 29),
        if (appState.watchlist.isEmpty)
          const _EmptyWatchlist()
        else ...[
          if (datedTitles.isNotEmpty) ...[
            SectionHeading(
              title: 'Dates announced',
              detail:
                  '${datedTitles.length} ${datedTitles.length == 1 ? 'title' : 'titles'} sorted by next release',
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < datedTitles.length; index++) ...[
              _WatchlistItem(title: datedTitles[index], appState: appState),
              if (index < datedTitles.length - 1)
                const Divider(height: 1, indent: 74),
            ],
          ],
          if (undatedTitles.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionHeading(
              title: 'Waiting for a date',
              detail:
                  '${undatedTitles.length} ${undatedTitles.length == 1 ? 'title' : 'titles'} without a published schedule',
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < undatedTitles.length; index++) ...[
              _WatchlistItem(title: undatedTitles[index], appState: appState),
              if (index < undatedTitles.length - 1)
                const Divider(height: 1, indent: 74),
            ],
          ],
        ],
      ],
    );
  }
}

DateTime? _watchlistDate(MediaTitle title) =>
    title.nextAiring?.airingAt ?? title.startDate;

Future<void> _toggleAiringNotifications(
  BuildContext context,
  AppState appState,
) async {
  final enabled = !appState.notificationsEnabled;
  if (enabled) {
    await appState.requestAiringNotifications();
  } else {
    await appState.disableAiringNotifications();
  }
  if (!context.mounted) return;
  final error = appState.errorMessage;
  showMusicoToast(
    context,
    message:
        error ??
        (enabled ? 'Release reminders are on.' : 'Release reminders are off.'),
    isError: error != null,
    icon: Icons.notifications_active_outlined,
  );
}

class _WatchlistHeading extends StatelessWidget {
  const _WatchlistHeading({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your watchlist',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width > 600 ? 43 : 36,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${appState.watchlist.length} saved titles, ordered by when they return.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: MusicoPalette.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isAndroid ? 'Android' : 'Windows';
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              size: 18,
              color: MusicoPalette.forestLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !appState.notificationsAvailable
                        ? 'Release reminders unavailable'
                        : appState.notificationsEnabled
                        ? 'Release reminders are on'
                        : 'Release reminders are off',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    !appState.notificationsAvailable
                        ? 'Notifications are not available on this device.'
                        : appState.notificationsEnabled
                        ? 'New episodes and premieres can notify you.'
                        : 'Enable $platform notifications for episodes and premieres.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: appState.notificationsEnabled,
              onChanged: appState.notificationsAvailable
                  ? (_) => _toggleAiringNotifications(context, appState)
                  : null,
            ),
          ],
        ),
        const Divider(height: 22),
      ],
    );
  }
}

class _WatchlistItem extends StatelessWidget {
  const _WatchlistItem({required this.title, required this.appState});

  final MediaTitle title;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final airing = title.nextAiring;
    final upcoming = title.startDate;
    final format = prettyFormat(title.format);
    final latestProgress = airing == null
        ? title.status == 'NOT_YET_RELEASED'
              ? 'Waiting for its premiere'
              : 'No upcoming episode published'
        : 'Episode ${airing.episode} is next';
    final scheduleLabel = airing != null
        ? schedulePhrase(title)
        : upcoming != null
        ? '${_formatDate(upcoming)} · premiere'
        : 'Release date not announced';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          PosterArtwork(
            imageUrl: title.imageUrl,
            title: title.title,
            width: 62,
            height: 86,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 86),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (format != null)
                    Pill(
                      format,
                      background: title.isMovie
                          ? MusicoPalette.clay
                          : MusicoPalette.canvasAlt,
                      foreground: title.isMovie
                          ? MusicoPalette.terracotta
                          : MusicoPalette.forestLight,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    title.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontSize: 14, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestProgress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MusicoPalette.moss,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: MusicoPalette.softInk,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          scheduleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: MusicoPalette.softInk),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Watchlist actions',
            onSelected: (action) async {
              if (action == 'remove') {
                await appState.removeFromWatchlist(title);
                if (context.mounted) {
                  showMusicoToast(
                    context,
                    message: 'Removed ${title.title} from your watchlist.',
                  );
                }
                return;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from list'),
              ),
            ],
            icon: const Icon(
              Icons.more_horiz_outlined,
              color: MusicoPalette.muted,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _EmptyWatchlist extends StatelessWidget {
  const _EmptyWatchlist();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 31),
      decoration: BoxDecoration(
        color: MusicoPalette.paper,
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MusicoPalette.clay,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.bookmark_add_outlined,
                  color: MusicoPalette.terracotta,
                  size: 22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Save something for later.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                'Browse the anime calendar for upcoming series, films and episodes you want to follow.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
