import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/media_download.dart';
import '../models/media_title.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';
import '../widgets/configured_downloads_dialog.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 52 : 26, 33, wide ? 52 : 26, 35),
      children: [
        _WatchlistHeading(appState: appState),
        const SizedBox(height: 22),
        _ReminderCard(appState: appState),
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
        SectionHeading(
          title: 'What’s on your list',
          detail: '${appState.watchlist.length} saved movies and series',
          trailing: Icon(
            Icons.bookmarks_outlined,
            color: MusicoPalette.terracotta,
            size: 20,
          ),
        ),
        const SizedBox(height: 13),
        if (appState.watchlist.isEmpty)
          const _EmptyWatchlist()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 980
                  ? 3
                  : width >= 650
                  ? 2
                  : 1;
              const gap = 11.0;
              final itemWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final title in appState.watchlist)
                    SizedBox(
                      width: itemWidth,
                      child: _WatchlistItem(title: title, appState: appState),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

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
    final compact = MediaQuery.sizeOf(context).width < 560;
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
                'A place for the next episode, season or premiere.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: MusicoPalette.muted),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 14),
          FilledButton.tonalIcon(
            onPressed: () => _toggleAiringNotifications(context, appState),
            icon: Icon(
              appState.notificationsEnabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_rounded,
              size: 17,
            ),
            label: Text(
              appState.notificationsEnabled
                  ? 'Alerts on'
                  : 'Get release alerts',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: appState.notificationsEnabled
                  ? MusicoPalette.olive
                  : MusicoPalette.canvasAlt,
              foregroundColor: MusicoPalette.ink,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isAndroid ? 'Android' : 'Windows';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MusicoPalette.sky.withValues(alpha: .85),
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: MusicoPalette.white,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              size: 17,
              color: MusicoPalette.forest,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appState.notificationsEnabled
                      ? 'Release reminders are on.'
                      : 'A little reminder when it’s time.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  appState.notificationsEnabled
                      ? 'Musico can notify you of scheduled episodes and premieres.'
                      : 'Turn on $platform notifications for scheduled episode and movie-premiere reminders.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (MediaQuery.sizeOf(context).width >= 500)
            appState.notificationsEnabled
                ? Switch.adaptive(
                    value: true,
                    activeTrackColor: MusicoPalette.moss,
                    onChanged: (_) =>
                        _toggleAiringNotifications(context, appState),
                  )
                : FilledButton(
                    onPressed: () =>
                        _toggleAiringNotifications(context, appState),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 37),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                    ),
                    child: const Text('Enable'),
                  ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MusicoPalette.paper,
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          PosterArtwork(
            imageUrl: title.imageUrl,
            title: title.title,
            width: 71,
            height: 99,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 99),
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
                          : MusicoPalette.forest,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    title.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontSize: 13, height: 1.35),
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
                  SplitFlapLabel(value: scheduleLabel),
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
              if (action == 'download-anime') {
                await showConfiguredDownloadsDialog(
                  context,
                  appState: appState,
                  category: MediaDownloadCategory.anime,
                  initialQuery: title.title,
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove from list'),
              ),
              if (appState.mediaDownloadConfig
                      ?.forCategory(MediaDownloadCategory.anime)
                      .isNotEmpty ??
                  false)
                const PopupMenuItem(
                  value: 'download-anime',
                  child: Text('Download configured episodes'),
                ),
            ],
            icon: const Icon(
              Icons.more_horiz_rounded,
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'Space Grotesk',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
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
