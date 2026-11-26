import 'package:material_ui/material_ui.dart';

import '../models/video_track.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/local_video_player.dart';

class LocalVideoScreen extends StatelessWidget {
  const LocalVideoScreen({
    required this.appState,
    required this.category,
    super.key,
  });

  final AppState appState;
  final VideoCategory category;

  String get _title => switch (category) {
    VideoCategory.tvShow => 'TV shows',
    VideoCategory.movie => 'Movies',
    VideoCategory.other => 'Videos',
  };

  String get _description => switch (category) {
    VideoCategory.tvShow => 'Episodes saved on this device.',
    VideoCategory.movie => 'Films saved on this device.',
    VideoCategory.other => 'Videos saved on this device.',
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    final videos = appState.videoTracks
        .where((video) => video.category == category)
        .toList();
    final uncategorized = appState.videoTracks
        .where((video) => video.category == VideoCategory.other)
        .toList();
    final current = appState.currentVideo?.category == category
        ? appState.currentVideo
        : null;
    final continueWatching = videos.where((video) => video.isResumable).toList()
      ..sort(
        (first, second) =>
            second.lastWatchedAtMs.compareTo(first.lastWatchedAtMs),
      );

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 42 : 22, 30, wide ? 42 : 22, 36),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title, style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(height: 5),
                  Text(
                    _description,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: MusicoPalette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: appState.isImportingVideos
                  ? null
                  : () => appState.pickVideoFiles(category: category),
              icon: appState.isImportingVideos
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(appState.isImportingVideos ? 'Adding' : 'Add videos'),
            ),
          ],
        ),
        if (appState.videoErrorMessage case final message?) ...[
          const SizedBox(height: 18),
          MaterialBanner(
            content: Text(message),
            leading: const Icon(Icons.error_outline_rounded),
            backgroundColor: MusicoPalette.clay,
            actions: [
              TextButton(
                onPressed: () => appState.pickVideoFiles(category: category),
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
        if (continueWatching.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Continue watching',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < continueWatching.length;
                  index++
                ) ...[
                  _ContinueWatchingRow(
                    video: continueWatching[index],
                    appState: appState,
                  ),
                  if (index < continueWatching.length - 1)
                    const Divider(height: 1, indent: 64),
                ],
              ],
            ),
          ),
        ],
        if (current != null) ...[
          const SizedBox(height: 24),
          LocalVideoPlayer(appState: appState, video: current),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (current.artist case final artist?)
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Stop video',
                onPressed: appState.stopVideo,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Text(_title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 9),
            Text(
              '${videos.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (videos.isEmpty)
          _EmptyLocalVideos(
            category: category,
            onImport: appState.isImportingVideos
                ? null
                : () => appState.pickVideoFiles(category: category),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < videos.length; index++) ...[
                  _LocalVideoRow(
                    video: videos[index],
                    appState: appState,
                    playing: current?.id == videos[index].id,
                  ),
                  if (index < videos.length - 1)
                    const Divider(height: 1, indent: 64),
                ],
              ],
            ),
          ),
        if (uncategorized.isNotEmpty) ...[
          const SizedBox(height: 26),
          Text(
            'Unsorted videos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            'Choose which library each existing video belongs in.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < uncategorized.length; index++) ...[
                  _LocalVideoRow(
                    video: uncategorized[index],
                    appState: appState,
                    playing: current?.id == uncategorized[index].id,
                    onCategorize: (value) =>
                        appState.categorizeVideo(uncategorized[index], value),
                  ),
                  if (index < uncategorized.length - 1)
                    const Divider(height: 1, indent: 64),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ContinueWatchingRow extends StatelessWidget {
  const _ContinueWatchingRow({required this.video, required this.appState});

  final VideoTrack video;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final progress = video.playbackProgress;
    final percent = (progress * 100).round();
    final remaining = Duration(
      milliseconds: video.durationMs - video.positionMs,
    );
    final minutesLeft = remaining.inMinutes;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: LocalVideoArtwork(video: video, size: 46),
      title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (video.artist case final artist?)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Text(
              '$percent% watched · ${_lastWatchedLabel(video.lastWatchedAtMs)} · $minutesLeft min left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.play_circle_outline_rounded),
      onTap: () => appState.playVideo(video),
    );
  }
}

String _lastWatchedLabel(int timestampMs) {
  if (timestampMs <= 0) return 'Previously watched';
  final elapsed = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(timestampMs),
  );
  if (elapsed.isNegative || elapsed < const Duration(minutes: 1)) {
    return 'Watched just now';
  }
  if (elapsed < const Duration(hours: 1)) {
    return 'Watched ${elapsed.inMinutes} min ago';
  }
  if (elapsed < const Duration(days: 1)) {
    return 'Watched ${elapsed.inHours} hr ago';
  }
  return 'Watched ${elapsed.inDays} days ago';
}

class _EmptyLocalVideos extends StatelessWidget {
  const _EmptyLocalVideos({required this.category, required this.onImport});

  final VideoCategory category;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final isMovie = category == VideoCategory.movie;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 18),
      child: Column(
        children: [
          Icon(
            isMovie ? Icons.movie_outlined : Icons.live_tv_outlined,
            size: 34,
            color: MusicoPalette.forest,
          ),
          const SizedBox(height: 12),
          Text(
            isMovie ? 'No movies added yet' : 'No episodes added yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose video files you own or are allowed to use. '
            'They stay on this device.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('Choose video files'),
          ),
        ],
      ),
    );
  }
}

class _LocalVideoRow extends StatelessWidget {
  const _LocalVideoRow({
    required this.video,
    required this.appState,
    required this.playing,
    this.onCategorize,
  });

  final VideoTrack video;
  final AppState appState;
  final bool playing;
  final ValueChanged<VideoCategory>? onCategorize;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: LocalVideoArtwork(video: video, size: 46),
      title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          ?video.artist,
          ?video.quality,
          '${(video.byteSize / (1024 * 1024)).toStringAsFixed(1)} MB',
          'stored on this device',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCategorize case final categorize?)
            PopupMenuButton<VideoCategory>(
              tooltip: 'Move to a library',
              onSelected: categorize,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: VideoCategory.tvShow,
                  child: Text('TV shows'),
                ),
                PopupMenuItem(
                  value: VideoCategory.movie,
                  child: Text('Movies'),
                ),
              ],
              icon: const Icon(Icons.folder_open_outlined),
            ),
          IconButton(
            tooltip: 'Remove from this device',
            onPressed: () => appState.removeVideo(video),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      onTap: () => appState.playVideo(video),
    );
  }
}
