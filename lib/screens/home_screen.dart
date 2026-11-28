import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/stream_watch_progress.dart';
import '../models/watch_media.dart';
import '../services/stream_watch_progress_service.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.appState,
    required this.onNavigate,
    super.key,
  });

  final AppState appState;
  final ValueChanged<int> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StreamWatchProgressService _progressService =
      StreamWatchProgressService();
  final WatchService _watchService = WatchService();
  List<StreamWatchProgress> _continueWatching = const [];
  List<WatchTitle> _featuredShows = const [];
  List<WatchTitle> _featuredMovies = const [];
  bool _loadingProgress = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProgress());
    unawaited(_loadFeaturedShows());
    unawaited(_loadFeaturedMovies());
  }

  @override
  void dispose() {
    _watchService.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    try {
      final entries = await _progressService.load();
      if (!mounted) return;
      setState(() {
        _continueWatching = entries.take(10).toList();
        _loadingProgress = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loadingProgress = false);
    }
  }

  Future<void> _loadFeaturedShows() async {
    try {
      final results = await Future.wait([
        _watchService.search('The Bear', series: true),
        _watchService.search('Severance', series: true),
        _watchService.search('Breaking Bad', series: true),
        _watchService.search('The Last of Us', series: true),
      ]);
      if (!mounted) return;
      final shows = <WatchTitle>[
        for (final list in results)
          if (list.isNotEmpty) list.first,
      ];
      setState(() => _featuredShows = shows);
    } on Object {
      // Ignore featured show load errors.
    }
  }

  Future<void> _loadFeaturedMovies() async {
    try {
      final results = await Future.wait([
        _watchService.search('Dune', series: false),
        _watchService.search('Inception', series: false),
        _watchService.search('Interstellar', series: false),
        _watchService.search('Oppenheimer', series: false),
      ]);
      if (!mounted) return;
      final movies = <WatchTitle>[
        for (final list in results)
          if (list.isNotEmpty) list.first,
      ];
      setState(() => _featuredMovies = movies);
    } on Object {
      // Ignore featured movie load errors.
    }
  }

  int _tabForCategory(StreamWatchCategory category) => switch (category) {
    StreamWatchCategory.anime => 2,
    StreamWatchCategory.tvShow => 3,
    StreamWatchCategory.movie => 4,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final pad = wide ? 32.0 : 18.0;
    final anime = widget.appState.seasonTitles.take(10).toList();
    final watchlist = widget.appState.watchlist.take(10).toList();
    final tracks = widget.appState.tracks.take(6).toList();
    final hero = anime.isNotEmpty ? anime.first : null;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadProgress(),
          _loadFeaturedMovies(),
          widget.appState.refreshAnime(),
        ]);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 18, pad, 32),
        children: [
          const Overline('HOME · OVERVIEW', icon: Icons.home_rounded),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Everything you love,\n'),
                TextSpan(
                  text: 'in one place.',
                  style: TextStyle(
                    color: MusicoPalette.forestLight,
                    shadows: [
                      Shadow(
                        color: MusicoPalette.forestLight.withValues(alpha: .35),
                        blurRadius: 26,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.displayLarge
                ?.copyWith(fontSize: wide ? 36 : 29),
          ),
          if (anime.isNotEmpty ||
              _featuredShows.isNotEmpty ||
              _featuredMovies.isNotEmpty) ...[
            const SizedBox(height: 18),
            AutoHeroCarousel(
              height: 220,
              items: [
                for (final item in anime.take(2))
                  HeroBannerItem(
                    title: item.title,
                    subtitle: 'Anime · ${item.format}',
                    imageUrl: item.imageUrl,
                    buttonLabel: 'Watch Anime',
                    onTap: () => widget.onNavigate(2),
                  ),
                for (final show in _featuredShows.take(2))
                  HeroBannerItem(
                    title: show.title,
                    subtitle: 'Series · ${show.subtitleLine}',
                    imageUrl: show.posterUrl,
                    buttonLabel: 'Watch Series',
                    onTap: () => widget.onNavigate(3),
                  ),
                for (final movie in _featuredMovies.take(2))
                  HeroBannerItem(
                    title: movie.title,
                    subtitle: 'Movie · ${movie.subtitleLine}',
                    imageUrl: movie.posterUrl,
                    buttonLabel: 'Watch Movie',
                    onTap: () => widget.onNavigate(4),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickNavCard(
                icon: Icons.library_music_outlined,
                label: 'Songs',
                detail: '${widget.appState.tracks.length} tracks',
                onTap: () => widget.onNavigate(1),
              ),
              _QuickNavCard(
                icon: Icons.ondemand_video_outlined,
                label: 'Anime',
                detail: '${widget.appState.seasonTitles.length} trending',
                onTap: () => widget.onNavigate(2),
              ),
              _QuickNavCard(
                icon: Icons.live_tv_outlined,
                label: 'TV Shows',
                detail: 'Stream series',
                onTap: () => widget.onNavigate(3),
              ),
              _QuickNavCard(
                icon: Icons.movie_outlined,
                label: 'Movies',
                detail: 'Stream films',
                onTap: () => widget.onNavigate(4),
              ),
            ],
          ),
          if (_loadingProgress) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(minHeight: 2),
          ] else if (_continueWatching.isNotEmpty) ...[
            const SizedBox(height: 26),
            const SectionHeading(
              title: 'Continue watching',
              detail: 'Resume where you left off across Anime, TV & Movies',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 236,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _continueWatching.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final entry = _continueWatching[index];
                  return SizedBox(
                    width: 140,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          widget.onNavigate(_tabForCategory(entry.category)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: entry.posterUrl,
                            title: entry.title,
                            width: 140,
                            height: 176,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.episodeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: MusicoPalette.muted),
                          ),
                          const SizedBox(height: 5),
                          LinearProgressIndicator(
                            value: entry.playbackProgress,
                            minHeight: 3,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (anime.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Featured anime',
              detail: 'Popular this season',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(2),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: anime.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final media = anime[index];
                  return SizedBox(
                    width: 136,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onNavigate(2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: media.imageUrl,
                            title: media.title,
                            width: 136,
                            height: 180,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            media.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_featuredShows.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Featured TV shows',
              detail: 'Popular series on demand',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(3),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _featuredShows.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final show = _featuredShows[index];
                  return SizedBox(
                    width: 136,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onNavigate(3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: show.posterUrl,
                            title: show.title,
                            width: 136,
                            height: 180,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            show.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_featuredMovies.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Featured movies',
              detail: 'Popular films on demand',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(4),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _featuredMovies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final movie = _featuredMovies[index];
                  return SizedBox(
                    width: 136,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onNavigate(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: movie.posterUrl,
                            title: movie.title,
                            width: 136,
                            height: 180,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (watchlist.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Your watchlist',
              detail: '${widget.appState.watchlist.length} saved titles',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(7),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: watchlist.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final media = watchlist[index];
                  return SizedBox(
                    width: 136,
                    child: InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onNavigate(7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: media.imageUrl,
                            title: media.title,
                            width: 136,
                            height: 180,
                          ),
                          const SizedBox(height: 7),
                          Text(
                            media.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (widget.appState.currentTrack != null) ...[
            const SizedBox(height: 28),
            const SectionHeading(
              title: 'Continue listening',
              detail: 'Pick up your current track',
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MusicoPalette.forestLight.withValues(alpha: 0.15),
                  ),
                  child:
                      widget.appState.currentTrack!.artworkPath != null &&
                          widget.appState.currentTrack!.artworkPath!.isNotEmpty
                      ? Image.file(
                          File(widget.appState.currentTrack!.artworkPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.graphic_eq_rounded,
                            color: MusicoPalette.forestLight,
                          ),
                        )
                      : const Icon(
                          Icons.graphic_eq_rounded,
                          color: MusicoPalette.forestLight,
                        ),
                ),
              ),
              title: Text(
                widget.appState.currentTrack!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                widget.appState.currentTrack!.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: IconButton(
                icon: Icon(
                  widget.appState.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                  size: 32,
                  color: MusicoPalette.forestLight,
                ),
                onPressed: () => unawaited(
                  widget.appState.isPlaying
                      ? widget.appState.player.pause()
                      : widget.appState.player.play(),
                ),
              ),
              onTap: () => widget.onNavigate(1),
            ),
          ],
          if (widget.appState.musicPlaylists.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Your playlists',
              detail: '${widget.appState.musicPlaylists.length} playlists',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(5),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.appState.musicPlaylists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = widget.appState.musicPlaylists[index];
                  return InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => widget.onNavigate(5),
                    child: Container(
                      width: 170,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MusicoPalette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: MusicoPalette.glassStrong),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${playlist.trackIds.length} songs',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: MusicoPalette.muted),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeading(
              title: 'Your music',
              detail: '${widget.appState.tracks.length} songs in library',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(1),
                child: const Text('Open Songs'),
              ),
            ),
            const SizedBox(height: 10),
            for (final track in tracks)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MusicoPalette.canvasAlt,
                      border: Border.all(color: MusicoPalette.glassStrong),
                    ),
                    child:
                        track.artworkPath != null &&
                            track.artworkPath!.isNotEmpty
                        ? Image.file(
                            File(track.artworkPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.music_note_rounded,
                              color: MusicoPalette.forestLight,
                            ),
                          )
                        : const Icon(
                            Icons.music_note_rounded,
                            color: MusicoPalette.forestLight,
                          ),
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => unawaited(widget.appState.playTrack(track)),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuickNavCard extends StatelessWidget {
  const _QuickNavCard({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MusicoPalette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MusicoPalette.glassStrong),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: MusicoPalette.forestLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: MusicoPalette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
