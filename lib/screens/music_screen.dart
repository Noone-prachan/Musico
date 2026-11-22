import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/media_download.dart';
import '../models/music_playlist.dart';
import '../models/music_track.dart';
import '../models/video_track.dart';
import '../services/synced_lyrics_parser.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';
import '../widgets/configured_downloads_dialog.dart';
import '../widgets/spotify_playlist_section.dart';
import '../widgets/youtube_download_dialog.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({
    required this.appState,
    required this.onOpenCatalog,
    super.key,
  });

  final AppState appState;
  final VoidCallback onOpenCatalog;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool _showLibrary = false;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 34 : 20, 20, wide ? 34 : 20, 0),
          child: _Header(appState: widget.appState),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Discover')),
                ButtonSegment(value: true, label: Text('Library')),
              ],
              selected: {_showLibrary},
              onSelectionChanged: (selected) {
                setState(() => _showLibrary = selected.single);
              },
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 170),
                switchInCurve: Curves.easeOutCubic,
                child: _showLibrary
                    ? _LibraryContent(
                        key: const ValueKey('library'),
                        appState: widget.appState,
                      )
                    : _DiscoverContent(
                        key: const ValueKey('discover'),
                        appState: widget.appState,
                        onOpenLibrary: () =>
                            setState(() => _showLibrary = true),
                        onOpenCatalog: widget.onOpenCatalog,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoverContent extends StatelessWidget {
  const _DiscoverContent({
    required this.appState,
    required this.onOpenLibrary,
    required this.onOpenCatalog,
    super.key,
  });

  final AppState appState;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final featuredTrack =
        appState.currentTrack ??
        appState.visibleTracks.firstOrNull ??
        appState.tracks.firstOrNull;
    final recentTracks = appState.tracks.toList()
      ..sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));

    return ListView(
      key: const PageStorageKey('music-discover'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _DiscoveryHero(
          appState: appState,
          track: featuredTrack,
          onOpenCatalog: onOpenCatalog,
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                'Playlists',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: onOpenLibrary,
              child: const Text('Your library'),
            ),
          ],
        ),
        if (appState.musicPlaylists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 19,
                  color: MusicoPalette.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    appState.tracks.isEmpty
                        ? 'Create playlists from tracks in your library.'
                        : 'Group your tracks into playlists from the Library tab.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (appState.tracks.isNotEmpty)
                  TextButton(
                    onPressed: onOpenLibrary,
                    child: const Text('Create'),
                  ),
              ],
            ),
          )
        else
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: appState.musicPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final playlist = appState.musicPlaylists[index];
                final playlistTracks = playlist.trackIds
                    .map(
                      (id) => appState.tracks
                          .where((track) => track.id == id)
                          .firstOrNull,
                    )
                    .whereType<MusicTrack>()
                    .toList();
                return _PlaylistCard(
                  playlist: playlist,
                  artwork: playlistTracks.firstOrNull,
                  onTap: () {
                    unawaited(appState.selectMusicPlaylist(playlist.id));
                    onOpenLibrary();
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recently added',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(onPressed: onOpenLibrary, child: const Text('See all')),
          ],
        ),
        if (recentTracks.isEmpty)
          _EmptyCollection(appState: appState)
        else
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: _surfaceDecoration(),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < recentTracks.length && index < 5;
                  index++
                ) ...[
                  _TrackRow(track: recentTracks[index], appState: appState),
                  if (index < recentTracks.length - 1 && index < 4)
                    const Divider(height: 1, indent: 64, endIndent: 14),
                ],
              ],
            ),
          ),
        if (appState.currentTrack != null) ...[
          const SizedBox(height: 24),
          _LyricsPanel(appState: appState),
        ],
        const SizedBox(height: 26),
        OutlinedButton.icon(
          onPressed: onOpenCatalog,
          icon: const Icon(Icons.library_music_outlined),
          label: const Text('Find free music'),
        ),
      ],
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero({
    required this.appState,
    required this.track,
    required this.onOpenCatalog,
  });

  final AppState appState;
  final MusicTrack? track;
  final VoidCallback onOpenCatalog;

  @override
  Widget build(BuildContext context) {
    final selectedTrack = track;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D2F73), Color(0xFF241D42), Color(0xFF171326)],
        ),
        border: Border.all(color: MusicoPalette.glassStrong),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: MusicoPalette.forest.withValues(alpha: .30),
            blurRadius: 46,
            offset: const Offset(0, 18),
            spreadRadius: -8,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (selectedTrack == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Your music, ready\n'),
                      TextSpan(
                        text: 'offline.',
                        style: TextStyle(
                          color: MusicoPalette.olive,
                          shadows: [
                            Shadow(
                              color: MusicoPalette.olive.withValues(alpha: .35),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Import audio from this device or browse openly licensed music.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: MusicoPalette.muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: appState.pickAudioFiles,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Import audio'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenCatalog,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Find free music'),
                    ),
                  ],
                ),
              ],
            );
          }

          final metadata = selectedTrack.displayMetadata;
          final compact = constraints.maxWidth < 450;
          final artwork = Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: MusicoPalette.forest.withValues(alpha: .45),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _PlayerArtwork(
              track: selectedTrack,
              size: compact ? 104 : 168,
            ),
          );
          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appState.currentTrack?.id == selectedTrack.id
                    ? 'NOW PLAYING'
                    : 'FROM YOUR LIBRARY',
                style: const TextStyle(
                  color: MusicoPalette.olive,
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                metadata.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                metadata.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: MusicoPalette.muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MusicoPalette.olive,
                  foregroundColor: MusicoPalette.canvas,
                  minimumSize: const Size(0, 42),
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  if (appState.currentTrack?.id == selectedTrack.id) {
                    appState.togglePlayback();
                  } else {
                    appState.playTrack(selectedTrack);
                  }
                },
                icon: Icon(
                  appState.currentTrack?.id == selectedTrack.id &&
                          appState.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  appState.currentTrack?.id == selectedTrack.id &&
                          appState.isPlaying
                      ? 'Pause'
                      : 'Play',
                ),
              ),
            ],
          );

          if (compact) {
            return Row(
              children: [
                artwork,
                const SizedBox(width: 15),
                Expanded(child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: actions),
              const SizedBox(width: 24),
              artwork,
            ],
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.artwork,
    required this.onTap,
  });

  final MusicPlaylist playlist;
  final MusicTrack? artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 144,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerArtwork(track: artwork, size: 136),
                const SizedBox(height: 8),
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${playlist.trackIds.length} ${playlist.trackIds.length == 1 ? 'track' : 'tracks'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('music-library'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _MusicLibrary(appState: appState),
        if (appState.currentTrack != null) ...[
          const SizedBox(height: 22),
          _LyricsPanel(appState: appState),
        ],
        const SizedBox(height: 28),
        SpotifyPlaylistSection(appState: appState),
        const SizedBox(height: 28),
        _VideoLibrary(appState: appState),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MUSICO · OFFLINE FIRST',
              style: TextStyle(
                color: MusicoPalette.olive.withValues(alpha: .85),
                fontFamily: 'IBM Plex Mono',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Your music,\n'),
                  TextSpan(
                    text: 'always yours.',
                    style: TextStyle(
                      color: MusicoPalette.olive,
                      shadows: [
                        Shadow(
                          color: MusicoPalette.olive.withValues(alpha: .45),
                          blurRadius: 26,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.displayLarge
                  ?.copyWith(fontSize: compact ? 29 : 38),
            ),
          ],
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 14),
            if (compact)
              IconButton.filledTonal(
                tooltip: 'Download from YouTube',
                onPressed: () =>
                    showYouTubeDownloadDialog(context, appState: appState),
                icon: const Icon(Icons.download_rounded),
              )
            else
              OutlinedButton.icon(
                onPressed: () =>
                    showYouTubeDownloadDialog(context, appState: appState),
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Download'),
              ),
            const SizedBox(width: 8),
            if (compact)
              IconButton.filledTonal(
                tooltip: 'Import audio',
                onPressed: appState.pickAudioFiles,
                icon: const Icon(Icons.add_rounded),
              )
            else
              FilledButton.icon(
                onPressed: appState.pickAudioFiles,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Import audio'),
              ),
          ],
        );
      },
    );
  }
}

class _MusicLibrary extends StatelessWidget {
  const _MusicLibrary({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final tracks = appState.visibleTracks;
    final allEmpty = appState.tracks.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Library',
          detail:
              '${appState.tracks.length} ${appState.tracks.length == 1 ? 'track' : 'tracks'}',
        ),
        if (appState.musicErrorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            appState.musicErrorMessage!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: MusicoPalette.error),
          ),
        ],
        const SizedBox(height: 13),
        _PlaylistSelector(appState: appState),
        const SizedBox(height: 10),
        TextField(
          textInputAction: TextInputAction.search,
          onChanged: appState.setTrackQuery,
          decoration: InputDecoration(
            hintText: 'Search your library',
            prefixIcon: const Icon(Icons.search_rounded, size: 17),
            suffixIcon: appState.trackQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear music search',
                    onPressed: () => appState.setTrackQuery(''),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
          ),
        ),
        const SizedBox(height: 11),
        if (allEmpty)
          _EmptyCollection(appState: appState)
        else if (tracks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: _surfaceDecoration(),
            child: Text(
              appState.selectedMusicPlaylistId == null
                  ? 'No tracks match that search.'
                  : 'This playlist is empty. Choose All music to see your tracks.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          Container(
            decoration: _surfaceDecoration(),
            child: Column(
              children: [
                for (var index = 0; index < tracks.length; index++) ...[
                  _TrackRow(track: tracks[index], appState: appState),
                  if (index != tracks.length - 1)
                    const Divider(height: 1, indent: 64, endIndent: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PlaylistSelector extends StatelessWidget {
  const _PlaylistSelector({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final selectedPlaylist = appState.musicPlaylists
        .where((playlist) => playlist.id == appState.selectedMusicPlaylistId)
        .firstOrNull;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: appState.selectedMusicPlaylistId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Playlist',
              prefixIcon: Icon(Icons.queue_music_rounded, size: 18),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All music'),
              ),
              for (final playlist in appState.musicPlaylists)
                DropdownMenuItem<String?>(
                  value: playlist.id,
                  child: Text(
                    '${playlist.name} · ${playlist.trackIds.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id != appState.selectedMusicPlaylistId) {
                unawaited(appState.selectMusicPlaylist(id));
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Create playlist',
          onPressed: () => _showCreatePlaylistDialog(context, appState),
          icon: const Icon(Icons.playlist_add_rounded),
        ),
        if (selectedPlaylist != null)
          PopupMenuButton<String>(
            tooltip: 'Manage ${selectedPlaylist.name}',
            onSelected: (action) {
              if (action == 'rename') {
                _showRenamePlaylistDialog(context, appState, selectedPlaylist);
              } else if (action == 'delete') {
                _confirmDeletePlaylist(context, appState, selectedPlaylist);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename playlist'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete playlist'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

BoxDecoration _surfaceDecoration() => BoxDecoration(
  color: MusicoPalette.surface,
  border: Border.all(color: MusicoPalette.glassStrong),
  borderRadius: BorderRadius.circular(12),
);

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _surfaceDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 400;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: MusicoPalette.canvasAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.library_music_outlined,
                  color: MusicoPalette.forest,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No tracks yet',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Import audio from your device or find free music.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 13),
                    FilledButton.icon(
                      onPressed: appState.pickAudioFiles,
                      icon: const Icon(Icons.library_music_outlined, size: 16),
                      label: Text(narrow ? 'Import' : 'Import audio'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final loaded = appState.lyricsStatus == LyricsStatus.loaded;
    final loading = appState.lyricsStatus == LyricsStatus.loading;
    final message = switch (appState.lyricsStatus) {
      LyricsStatus.networkRequired =>
        'Connect to the internet to look up lyrics.',
      LyricsStatus.loading => 'Looking up lyrics…',
      LyricsStatus.loaded => 'Lyrics found',
      LyricsStatus.notFound => 'No lyrics were found for this track.',
      LyricsStatus.error =>
        appState.lyricsErrorMessage ?? 'Lyrics could not be loaded.',
      LyricsStatus.idle => 'Lyrics are ready when you are.',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
      decoration: BoxDecoration(
        color: MusicoPalette.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lyrics_outlined,
                size: 16,
                color: MusicoPalette.terracotta,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lyrics',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (appState.lyricsStatus == LyricsStatus.networkRequired ||
                  appState.lyricsStatus == LyricsStatus.notFound ||
                  appState.lyricsStatus == LyricsStatus.error)
                TextButton(
                  onPressed: appState.fetchLyricsForCurrent,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                  ),
                  child: Text('Try again'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (loading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 7),
          ],
          if (loaded)
            appState.syncedLyricLines.isEmpty
                ? Text(
                    appState.lyrics!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: MusicoPalette.softInk, height: 1.65),
                  )
                : _SyncedLyricsPreview(appState: appState)
          else
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: appState.lyricsStatus == LyricsStatus.error
                    ? MusicoPalette.error
                    : MusicoPalette.muted,
                height: 1.45,
              ),
            ),
          if (loaded && (appState.lyrics?.length ?? 0) > 160)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: MusicoPalette.paper,
                  showDragHandle: true,
                  builder: (context) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: .75,
                    builder: (context, controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 25),
                      children: [
                        Text(
                          'Lyrics',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 14),
                        if (appState.syncedLyricLines.isEmpty)
                          SelectableText(
                            appState.lyrics!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(height: 1.8),
                          )
                        else
                          _SyncedLyricsDocument(
                            lines: appState.syncedLyricLines,
                            activeIndex: appState.activeLyricIndex,
                          ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Read full lyrics'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncedLyricsPreview extends StatelessWidget {
  const _SyncedLyricsPreview({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final lines = appState.syncedLyricLines;
    final activeIndex = appState.activeLyricIndex;
    const windowSize = 5;
    final maxStart = lines.length > windowSize ? lines.length - windowSize : 0;
    final start = activeIndex < 0
        ? 0
        : (activeIndex - 2).clamp(0, maxStart).toInt();
    final end = (start + windowSize).clamp(0, lines.length).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (start > 0)
          const Text('…', style: TextStyle(color: MusicoPalette.muted)),
        for (var index = start; index < end; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: index == activeIndex
                    ? MusicoPalette.olive
                    : MusicoPalette.softInk,
                fontWeight: index == activeIndex
                    ? FontWeight.w700
                    : FontWeight.normal,
                height: 1.65,
              ),
              child: Text(lines[index].text, maxLines: 2),
            ),
          ),
        if (end < lines.length)
          const Text('…', style: TextStyle(color: MusicoPalette.muted)),
      ],
    );
  }
}

class _SyncedLyricsDocument extends StatefulWidget {
  const _SyncedLyricsDocument({required this.lines, required this.activeIndex});

  final List<SyncedLyricLine> lines;
  final int activeIndex;

  @override
  State<_SyncedLyricsDocument> createState() => _SyncedLyricsDocumentState();
}

class _SyncedLyricsDocumentState extends State<_SyncedLyricsDocument> {
  late List<GlobalKey> _lineKeys;

  @override
  void initState() {
    super.initState();
    _createLineKeys();
    _scrollToActiveLine();
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    final linesChanged = oldWidget.lines.length != widget.lines.length;
    if (linesChanged) _createLineKeys();
    if (linesChanged || oldWidget.activeIndex != widget.activeIndex) {
      _scrollToActiveLine();
    }
  }

  void _createLineKeys() {
    _lineKeys = List.generate(widget.lines.length, (_) => GlobalKey());
  }

  void _scrollToActiveLine() {
    final activeIndex = widget.activeIndex;
    if (activeIndex < 0 || activeIndex >= widget.lines.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.activeIndex != activeIndex) return;
      final targetContext = _lineKeys[activeIndex].currentContext;
      if (targetContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: .45,
          duration: MediaQuery.disableAnimationsOf(targetContext)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < widget.lines.length; index++)
            Padding(
              key: _lineKeys[index],
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: index == widget.activeIndex
                      ? MusicoPalette.olive
                      : MusicoPalette.softInk,
                  fontWeight: index == widget.activeIndex
                      ? FontWeight.w700
                      : FontWeight.normal,
                  height: 1.8,
                ),
                child: Text(widget.lines[index].text),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoLibrary extends StatelessWidget {
  const _VideoLibrary({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final current = appState.currentVideo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Video library',
          detail:
              '${appState.videoTracks.length} ${appState.videoTracks.length == 1 ? 'video' : 'videos'} saved on this device',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: 'Download configured videos',
                onPressed: () => showConfiguredDownloadsDialog(
                  context,
                  appState: appState,
                  category: MediaDownloadCategory.video,
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: appState.isImportingVideos
                    ? null
                    : appState.pickVideoFiles,
                icon: appState.isImportingVideos
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.video_library_outlined, size: 16),
                label: Text(
                  appState.isImportingVideos ? 'Adding' : 'Add videos',
                ),
              ),
            ],
          ),
        ),
        if (appState.videoErrorMessage != null) ...[
          const SizedBox(height: 9),
          _InlineState(
            icon: Icons.error_outline_rounded,
            message: appState.videoErrorMessage!,
            error: true,
            onRetry: appState.pickVideoFiles,
          ),
        ],
        const SizedBox(height: 12),
        if (current != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: appState.videoController),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Stop video',
                onPressed: appState.stopVideo,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _LyricsPanel(appState: appState),
        ] else if (appState.videoTracks.isEmpty)
          _VideoEmptyState(appState: appState)
        else
          Container(
            decoration: _surfaceDecoration(),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < appState.videoTracks.length;
                  index++
                ) ...[
                  _VideoRow(
                    video: appState.videoTracks[index],
                    appState: appState,
                  ),
                  if (index != appState.videoTracks.length - 1)
                    const Divider(height: 1, indent: 54, endIndent: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.video, required this.appState});

  final VideoTrack video;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: MusicoPalette.canvasAlt,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: MusicoPalette.forest,
        ),
      ),
      title: Text(
        video.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        '${(video.byteSize / (1024 * 1024)).toStringAsFixed(1)} MB · ${video.rights ?? 'available offline'}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (video.sourceUrl != null)
            IconButton(
              tooltip: 'View source and rights',
              onPressed: () => _showVideoDetails(context, video),
              icon: const Icon(Icons.info_outline_rounded, size: 17),
            ),
          IconButton(
            tooltip: 'Remove video from this device',
            onPressed: () => appState.removeVideo(video),
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
      onTap: () => appState.playVideo(video),
    );
  }
}

class _VideoEmptyState extends StatelessWidget {
  const _VideoEmptyState({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
      decoration: _surfaceDecoration(),
      child: Row(
        children: [
          const Icon(
            Icons.movie_outlined,
            color: MusicoPalette.terracotta,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Play videos stored on your device. Musico keeps them offline and private.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: appState.pickVideoFiles,
            child: const Text('Choose'),
          ),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.message,
    required this.error,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: error ? MusicoPalette.error : MusicoPalette.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: error ? MusicoPalette.error : null),
          ),
        ),
        if (error) TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.appState});

  final MusicTrack track;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final active = appState.currentTrack?.id == track.id;
    final metadata = track.displayMetadata;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            onTap: () => appState.playTrack(track),
            mouseCursor: SystemMouseCursors.click,
            child: _TrackArtwork(track: track, appState: appState),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: active ? MusicoPalette.forest : MusicoPalette.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    track.license == null
                        ? '${metadata.artist} · on this device'
                        : '${metadata.artist} · ${track.license}',
                    if (track.clipStartMs != null || track.clipEndMs != null)
                      'trimmed',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (track.sourceUrl != null || track.artworkPath != null)
            IconButton(
              tooltip: 'View source and rights',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showTrackDetails(context, track),
              icon: const Icon(Icons.info_outline_rounded, size: 16),
            ),
          PopupMenuButton<String>(
            tooltip: 'Track options',
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  _showRenameTrackDialog(context, appState, track);
                  break;
                case 'artwork':
                  unawaited(_findLicensedArtwork(context, appState, track));
                  break;
                case 'playlist':
                  _showTrackPlaylistsDialog(context, appState, track);
                  break;
                case 'trim':
                  _showTrackTrimDialog(context, appState, track);
                  break;
                case 'remove':
                  _confirmRemoveTrack(context, appState, track);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined),
                    SizedBox(width: 12),
                    Text('Rename song'),
                  ],
                ),
              ),
              if (track.artworkPath == null)
                const PopupMenuItem(
                  value: 'artwork',
                  child: Row(
                    children: [
                      Icon(Icons.image_search_outlined),
                      SizedBox(width: 12),
                      Text('Find licensed artwork'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'playlist',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add_rounded),
                    SizedBox(width: 12),
                    Text('Add to playlist'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'trim',
                child: Row(
                  children: [
                    Icon(Icons.content_cut_rounded),
                    SizedBox(width: 12),
                    Text('Trim playback'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded),
                    SizedBox(width: 12),
                    Text('Remove from device'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _findLicensedArtwork(
  BuildContext context,
  AppState appState,
  MusicTrack track,
) async {
  await appState.retryArtworkLookup(track.id);
  if (!context.mounted) return;

  final updatedTrack = appState.tracks
      .where((item) => item.id == track.id)
      .firstOrNull;
  final error = appState.artworkErrors[track.id];
  if (error != null) {
    showMusicoToast(context, message: error, isError: true);
  } else if (updatedTrack?.artworkPath != null) {
    showMusicoToast(
      context,
      message: 'Licensed artwork added.',
      icon: Icons.image_rounded,
    );
  } else if (appState.artworkLookupsInProgress.contains(track.id)) {
    showMusicoToast(
      context,
      message: 'An artwork search is already in progress.',
      icon: Icons.hourglass_top_rounded,
    );
  } else if (!appState.isOnline) {
    showMusicoToast(
      context,
      message: 'Connect to the internet to search licensed artwork.',
      isError: true,
    );
  } else {
    showMusicoToast(
      context,
      message: 'No matching open-license artwork was found.',
      icon: Icons.image_not_supported_outlined,
    );
  }
}

Future<void> _showRenameTrackDialog(
  BuildContext context,
  AppState appState,
  MusicTrack track,
) async {
  final metadata = track.displayMetadata;
  final titleController = TextEditingController(text: metadata.title);
  final artistController = TextEditingController(text: metadata.artist);
  final formKey = GlobalKey<FormState>();

  try {
    final renamed = await showDialog<({String title, String artist})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename song'),
        content: Form(
          key: formKey,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleController,
                  autofocus: true,
                  maxLength: 160,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Song title'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a song title.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: artistController,
                  maxLength: 160,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Artist'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an artist.'
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  'Only the library details change. Your audio file stays untouched.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, (
                title: titleController.text.trim(),
                artist: artistController.text.trim(),
              ));
            },
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
    if (renamed == null) return;
    await appState.renameTrack(
      track.id,
      title: renamed.title,
      artist: renamed.artist,
    );
  } finally {
    titleController.dispose();
    artistController.dispose();
  }
}

Future<void> _showTrackTrimDialog(
  BuildContext context,
  AppState appState,
  MusicTrack track,
) async {
  final durationMs = track.durationMs > 0
      ? track.durationMs
      : appState.currentTrack?.id == track.id
      ? appState.duration.inMilliseconds
      : 0;
  if (durationMs <= 0) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Track length unavailable'),
        content: const Text(
          'Play this track once so Musico can read its duration, then set the trim.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }

  final startValue = (track.clipStartMs ?? 0)
      .clamp(0, durationMs - 1)
      .toDouble();
  final endValue = (track.clipEndMs ?? durationMs)
      .clamp(startValue.round() + 1, durationMs)
      .toDouble();
  var selectedRange = RangeValues(startValue, endValue);
  final playingTrackId = appState.currentTrack?.id;
  final playingPosition = appState.player.position;
  final wasPlaying = appState.player.playing;
  if (wasPlaying) await appState.player.pause();
  if (!context.mounted) {
    if (wasPlaying) await appState.player.play();
    return;
  }

  RangeValues? result;
  try {
    result = await showDialog<RangeValues>(
      context: context,
      builder: (context) => _TrackTrimDialog(
        track: track,
        durationMs: durationMs,
        initialRange: selectedRange,
      ),
    );
  } finally {
    if (wasPlaying &&
        playingTrackId != null &&
        appState.currentTrack?.id == playingTrackId) {
      try {
        await appState.player.seek(playingPosition);
        await appState.player.play();
      } on Object catch (error, stackTrace) {
        debugPrint(
          'Playback could not resume after trim preview: $error\n$stackTrace',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Playback could not be resumed.')),
          );
        }
      }
    }
  }
  if (result == null) return;
  final isFullTrack =
      result.start.round() == 0 && result.end.round() >= durationMs;
  await appState.setTrackTrim(
    track.id,
    start: Duration(milliseconds: result.start.round()),
    end: isFullTrack ? null : Duration(milliseconds: result.end.round()),
  );
}

class _TrackTrimDialog extends StatefulWidget {
  const _TrackTrimDialog({
    required this.track,
    required this.durationMs,
    required this.initialRange,
  });

  final MusicTrack track;
  final int durationMs;
  final RangeValues initialRange;

  @override
  State<_TrackTrimDialog> createState() => _TrackTrimDialogState();
}

class _TrackTrimDialogState extends State<_TrackTrimDialog> {
  late final AudioPlayer _previewPlayer;
  late RangeValues _selectedRange;
  bool _previewLoading = true;
  bool _previewReady = false;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _previewPlayer = AudioPlayer();
    _selectedRange = widget.initialRange;
    unawaited(_preparePreview());
  }

  Future<void> _preparePreview() async {
    try {
      await _previewPlayer.setAudioSource(AudioSource.file(widget.track.path));
      await _applyPreviewClip();
      if (mounted) {
        setState(() {
          _previewReady = true;
          _previewLoading = false;
        });
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Trim preview could not be loaded: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _previewLoading = false;
          _previewError = 'This audio file could not be previewed.';
        });
      }
    }
  }

  Future<void> _applyPreviewClip() async {
    final startMs = _selectedRange.start.round();
    final endMs = _selectedRange.end.round();
    await _previewPlayer.setClip(
      start: startMs == 0 ? null : Duration(milliseconds: startMs),
      end: endMs >= widget.durationMs ? null : Duration(milliseconds: endMs),
    );
    await _previewPlayer.seek(Duration.zero);
  }

  Future<void> _finishRangeChange() async {
    try {
      await _previewPlayer.pause();
      await _applyPreviewClip();
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Trim preview range could not be updated: $error\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _previewError = 'The preview could not use this trim range.';
        });
      }
    }
  }

  Future<void> _togglePreview() async {
    try {
      if (_previewPlayer.playing) {
        await _previewPlayer.pause();
        return;
      }
      final clipLengthMs = (_selectedRange.end - _selectedRange.start).round();
      if (_previewPlayer.position.inMilliseconds >= clipLengthMs) {
        await _previewPlayer.seek(Duration.zero);
      }
      await _previewPlayer.play();
    } on Object catch (error, stackTrace) {
      debugPrint('Trim preview playback failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _previewError = 'The selected section could not be played.';
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_previewPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.durationMs.toDouble();
    return AlertDialog(
      title: const Text('Trim playback'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preview and choose the exact section to play. The original file stays unchanged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            StreamBuilder<Duration>(
              stream: _previewPlayer.positionStream,
              initialData: Duration.zero,
              builder: (context, snapshot) {
                final clipLengthMs = (_selectedRange.end - _selectedRange.start)
                    .round()
                    .clamp(1, widget.durationMs);
                final clipPositionMs = (snapshot.data ?? Duration.zero)
                    .inMilliseconds
                    .clamp(0, clipLengthMs);
                final playheadMs =
                    _selectedRange.start.round() + clipPositionMs.toInt();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 38,
                      child: CustomPaint(
                        painter: _TrimTimelinePainter(
                          durationMs: widget.durationMs,
                          selectedRange: _selectedRange,
                          playheadMs: playheadMs,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    RangeSlider(
                      min: 0,
                      max: duration,
                      values: _selectedRange,
                      labels: RangeLabels(
                        _formatTimelineTime(_selectedRange.start.round()),
                        _formatTimelineTime(_selectedRange.end.round()),
                      ),
                      onChanged: _previewLoading
                          ? null
                          : (range) {
                              final start = range.start
                                  .clamp(0.0, duration - 1)
                                  .toDouble();
                              final end = range.end
                                  .clamp(start + 1, duration)
                                  .toDouble();
                              setState(
                                () => _selectedRange = RangeValues(start, end),
                              );
                            },
                      onChangeEnd: (_) => unawaited(_finishRangeChange()),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'IN  ${_formatTimelineTime(_selectedRange.start.round())}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          'OUT  ${_formatTimelineTime(_selectedRange.end.round())}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        StreamBuilder<PlayerState>(
                          stream: _previewPlayer.playerStateStream,
                          initialData: _previewPlayer.playerState,
                          builder: (context, stateSnapshot) {
                            final isPlaying =
                                stateSnapshot.data?.playing ?? false;
                            return IconButton.filled(
                              tooltip: isPlaying
                                  ? 'Pause trim preview'
                                  : 'Play trim preview',
                              onPressed: _previewReady ? _togglePreview : null,
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: clipLengthMs.toDouble(),
                            value: clipPositionMs.toDouble(),
                            onChanged: !_previewReady
                                ? null
                                : (value) => _previewPlayer.seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PLAYHEAD  ${_formatTimelineTime(playheadMs)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          'DURATION  ${_formatTimelineTime(clipLengthMs)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (_previewLoading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (_previewError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _previewError!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: MusicoPalette.error),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => _selectedRange = RangeValues(0, duration));
            unawaited(_finishRangeChange());
          },
          child: const Text('Reset trim'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedRange),
          child: const Text('Apply trim'),
        ),
      ],
    );
  }
}

class _TrimTimelinePainter extends CustomPainter {
  const _TrimTimelinePainter({
    required this.durationMs,
    required this.selectedRange,
    required this.playheadMs,
  });

  final int durationMs;
  final RangeValues selectedRange;
  final int playheadMs;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalInset = 7.0;
    const lineY = 8.0;
    final width = size.width - horizontalInset * 2;
    final intervalMs = durationMs <= 60000
        ? 10000
        : durationMs <= 600000
        ? 30000
        : durationMs <= 3600000
        ? 60000
        : 300000;
    final labelIntervalMs = durationMs <= 60000
        ? 10000
        : durationMs <= 600000
        ? 60000
        : durationMs <= 3600000
        ? 300000
        : 600000;
    double xFor(int milliseconds) =>
        horizontalInset + width * milliseconds / durationMs;

    canvas.drawLine(
      Offset(horizontalInset, lineY),
      Offset(size.width - horizontalInset, lineY),
      Paint()
        ..color = MusicoPalette.canvasAlt
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(xFor(selectedRange.start.round()), lineY),
      Offset(xFor(selectedRange.end.round()), lineY),
      Paint()
        ..color = MusicoPalette.forest
        ..strokeWidth = 3,
    );

    for (var tick = 0; tick <= durationMs; tick += intervalMs) {
      final x = xFor(tick);
      final major = tick % labelIntervalMs == 0;
      canvas.drawLine(
        Offset(x, lineY),
        Offset(x, lineY + (major ? 10 : 5)),
        Paint()
          ..color = MusicoPalette.muted
          ..strokeWidth = 1,
      );
      if (major) {
        final label = TextPainter(
          text: TextSpan(
            text: _formatDuration(Duration(milliseconds: tick)),
            style: const TextStyle(color: MusicoPalette.muted, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (x - label.width / 2)
            .clamp(horizontalInset, size.width - horizontalInset - label.width)
            .toDouble();
        label.paint(canvas, Offset(labelX, lineY + 12));
      }
    }

    final playheadX = xFor(playheadMs.clamp(0, durationMs));
    canvas.drawLine(
      Offset(playheadX, 1),
      Offset(playheadX, lineY + 2),
      Paint()
        ..color = MusicoPalette.olive
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TrimTimelinePainter oldDelegate) =>
      durationMs != oldDelegate.durationMs ||
      selectedRange != oldDelegate.selectedRange ||
      playheadMs != oldDelegate.playheadMs;
}

String _formatTimelineTime(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final millis = (milliseconds % 1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$millis';
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track, required this.appState});

  final MusicTrack track;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final artworkPath = track.artworkPath;
    final error = appState.artworkErrors[track.id];
    final noLicensedMatch =
        artworkPath == null &&
        error == null &&
        appState.artworkLookupAttempts.contains(track.id) &&
        !appState.artworkLookupsInProgress.contains(track.id);
    final content = artworkPath != null
        ? Image.file(
            File(artworkPath),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _trackArtworkFallback(track, appState),
          )
        : _trackArtworkFallback(track, appState);
    return Tooltip(
      message:
          error ??
          (noLicensedMatch
              ? 'No open-license artwork match. Use track options to retry.'
              : 'Play ${track.displayMetadata.title}'),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(11), child: content),
            if (appState.artworkLookupsInProgress.contains(track.id))
              const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (artworkPath != null &&
                !appState.artworkLookupsInProgress.contains(track.id))
              Center(
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.black.withValues(alpha: .58),
                  child: Icon(
                    appState.currentTrack?.id == track.id && appState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
            if (error != null)
              Align(
                alignment: Alignment.topRight,
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: MusicoPalette.error,
                  shadows: const [Shadow(blurRadius: 2, color: Colors.white)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _trackArtworkFallback(MusicTrack track, AppState appState) => Container(
  width: 44,
  height: 44,
  decoration: BoxDecoration(
    color: MusicoPalette.canvasAlt,
    borderRadius: BorderRadius.circular(11),
  ),
  child: Center(
    child: Icon(
      appState.currentTrack?.id == track.id && appState.isPlaying
          ? Icons.pause_rounded
          : Icons.play_arrow_rounded,
      size: 21,
      color: appState.currentTrack?.id == track.id
          ? MusicoPalette.forest
          : MusicoPalette.muted,
    ),
  ),
);

Future<void> _showCreatePlaylistDialog(
  BuildContext context,
  AppState appState, {
  MusicTrack? trackToAdd,
}) async {
  final controller = TextEditingController();
  try {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(trackToAdd == null ? 'Create playlist' : 'Create playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trackToAdd != null) ...[
              Text(
                '"${trackToAdd.title}" will be added to this playlist.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 48,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Playlist name'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(trackToAdd == null ? 'Create' : 'Create & add track'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final created = await appState.createMusicPlaylist(name);
    if (created && trackToAdd != null) {
      final playlist = appState.musicPlaylists
          .where((item) => item.id == appState.selectedMusicPlaylistId)
          .firstOrNull;
      if (playlist != null) {
        await appState.addTrackToPlaylist(playlist.id, trackToAdd.id);
      }
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _showRenamePlaylistDialog(
  BuildContext context,
  AppState appState,
  MusicPlaylist playlist,
) async {
  final controller = TextEditingController(text: playlist.name);
  try {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    final normalizedName = name?.trim() ?? '';
    if (normalizedName.isEmpty || normalizedName == playlist.name) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm playlist rename'),
        content: Text('Rename "${playlist.name}" to "$normalizedName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await appState.renameMusicPlaylist(playlist.id, normalizedName);
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _confirmDeletePlaylist(
  BuildContext context,
  AppState appState,
  MusicPlaylist playlist,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete playlist?'),
      content: Text(
        'Delete "${playlist.name}"? Its songs will remain in All music.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MusicoPalette.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete playlist'),
        ),
      ],
    ),
  );
  if (confirmed == true) await appState.deleteMusicPlaylist(playlist.id);
}

Future<void> _confirmRemoveTrack(
  BuildContext context,
  AppState appState,
  MusicTrack track,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove track from this device?'),
      content: Text(
        '"${track.displayMetadata.title}" will be removed from your library and every playlist.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep track'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MusicoPalette.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove track'),
        ),
      ],
    ),
  );
  if (confirmed == true) await appState.removeTrack(track);
}

Future<void> _showTrackPlaylistsDialog(
  BuildContext context,
  AppState appState,
  MusicTrack track,
) async {
  final pageContext = context;
  if (appState.musicPlaylists.isEmpty) {
    await _showCreatePlaylistDialog(context, appState, trackToAdd: track);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Playlists for ${track.displayMetadata.title}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final playlist in appState.musicPlaylists)
                  CheckboxListTile(
                    value: playlist.trackIds.contains(track.id),
                    title: Text(playlist.name),
                    subtitle: Text(
                      '${playlist.trackIds.length} ${playlist.trackIds.length == 1 ? 'track' : 'tracks'}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) async {
                      if (value == null) return;
                      final isAdding = value;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (confirmationContext) => AlertDialog(
                          title: Text(
                            isAdding ? 'Add track?' : 'Remove track?',
                          ),
                          content: Text(
                            isAdding
                                ? 'Add "${track.displayMetadata.title}" to "${playlist.name}"?'
                                : 'Remove "${track.displayMetadata.title}" from "${playlist.name}"?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(confirmationContext, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(confirmationContext, true),
                              child: Text(isAdding ? 'Add track' : 'Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      final saved = isAdding
                          ? await appState.addTrackToPlaylist(
                              playlist.id,
                              track.id,
                            )
                          : await appState.removeTrackFromPlaylist(
                              playlist.id,
                              track.id,
                            );
                      if (saved && context.mounted) setDialogState(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              if (pageContext.mounted) {
                await _showCreatePlaylistDialog(pageContext, appState);
              }
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('New playlist'),
          ),
        ],
      ),
    ),
  );
}

class PlayerDock extends StatelessWidget {
  const PlayerDock({required this.appState, this.compact = false, super.key});

  final AppState appState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: appState.player.positionStream,
      initialData: appState.player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final total = appState.duration;
        final current = appState.currentTrack;
        final progress = total.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds)
                  .clamp(0, 1)
                  .toDouble();
        final playing = appState.isPlaying;

        if (compact) {
          return _CompactPlayer(
            appState: appState,
            current: current,
            playing: playing,
            progress: progress,
          );
        }

        return Container(
          height: 88,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1C1732), Color(0xFF111018)],
            ),
            border: Border(top: BorderSide(color: MusicoPalette.glassStrong)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Row(
            children: [
              SizedBox(
                width: 260,
                child: Row(
                  children: [
                    _PlayerArtwork(track: current, size: 42),
                    const SizedBox(width: 11),
                    Expanded(
                      child: _PlayerTrackInfo(track: current, playing: playing),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: appState.shuffle
                              ? 'Shuffle on'
                              : 'Shuffle off',
                          onPressed: appState.toggleShuffle,
                          icon: Icon(
                            Icons.shuffle_rounded,
                            size: 18,
                            color: appState.shuffle
                                ? MusicoPalette.terracotta
                                : MusicoPalette.muted,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Show lyrics',
                          onPressed: current == null
                              ? null
                              : () => _showLyricsSheet(context, appState),
                          icon: const Icon(Icons.lyrics_outlined, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Play previous',
                          onPressed: current == null
                              ? null
                              : appState.playPrevious,
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 22,
                          ),
                        ),
                        _PlayButton(
                          playing: playing,
                          canPlay:
                              current != null || appState.tracks.isNotEmpty,
                          onPressed: appState.togglePlayback,
                          size: 40,
                        ),
                        IconButton(
                          tooltip: 'Play next',
                          onPressed: current == null ? null : appState.playNext,
                          icon: const Icon(Icons.skip_next_rounded, size: 22),
                        ),
                        IconButton(
                          tooltip: appState.repeatOne
                              ? 'Repeat track on'
                              : 'Repeat off',
                          onPressed: appState.toggleRepeatOne,
                          icon: Icon(
                            Icons.repeat_one_rounded,
                            size: 18,
                            color: appState.repeatOne
                                ? MusicoPalette.terracotta
                                : MusicoPalette.muted,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 41,
                          child: Text(
                            _formatDuration(position),
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  fontFeatures: const [],
                                ),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              min: 0,
                              max: 1,
                              value: progress.toDouble(),
                              onChanged: total == Duration.zero
                                  ? null
                                  : (value) => appState.seek(
                                      Duration(
                                        milliseconds:
                                            (total.inMilliseconds * value)
                                                .round(),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 41,
                          child: Text(
                            _formatDuration(total),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 260,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: appState.autoplay
                          ? 'Autoplay on'
                          : 'Autoplay off',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => appState.setAutoplay(!appState.autoplay),
                      icon: Icon(
                        Icons.playlist_play_rounded,
                        size: 19,
                        color: appState.autoplay
                            ? MusicoPalette.terracotta
                            : MusicoPalette.muted,
                      ),
                    ),
                    IconButton(
                      tooltip: appState.sortAlphabetically
                          ? 'Sort A-Z'
                          : 'Sort newest first',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => appState.setSortAlphabetically(
                        !appState.sortAlphabetically,
                      ),
                      icon: Icon(
                        Icons.sort_by_alpha_rounded,
                        size: 19,
                        color: appState.sortAlphabetically
                            ? MusicoPalette.terracotta
                            : MusicoPalette.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.volume_up_outlined,
                      size: 17,
                      color: MusicoPalette.softInk,
                    ),
                    SizedBox(
                      width: 90,
                      child: Slider(
                        min: 0,
                        max: 1,
                        value: appState.volume,
                        onChanged: appState.setVolume,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _showLyricsSheet(BuildContext context, AppState appState) async {
  if (appState.currentTrack == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: MusicoPalette.paper,
    builder: (context) => AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final track = appState.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final status = appState.lyricsStatus;
        final message = switch (status) {
          LyricsStatus.networkRequired =>
            'Connect to the internet to look up lyrics.',
          LyricsStatus.loading => 'Looking up lyrics…',
          LyricsStatus.loaded => '',
          LyricsStatus.notFound => 'No lyrics were found for this track.',
          LyricsStatus.error =>
            appState.lyricsErrorMessage ?? 'Lyrics could not be loaded.',
          LyricsStatus.idle => 'Lyrics are ready when you are.',
        };

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .78,
          minChildSize: .45,
          maxChildSize: .94,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            children: [
              Text('Lyrics', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${track.displayMetadata.title} · ${track.displayMetadata.artist}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              if (status == LyricsStatus.loading) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 14),
              ],
              if (status == LyricsStatus.loaded)
                SelectableText(
                  appState.lyrics!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: MusicoPalette.ink, height: 1.8),
                )
              else ...[
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: status == LyricsStatus.error
                        ? MusicoPalette.error
                        : MusicoPalette.muted,
                    height: 1.5,
                  ),
                ),
                if (status != LyricsStatus.loading) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: appState.fetchLyricsForCurrent,
                      icon: const Icon(Icons.search_rounded, size: 17),
                      label: Text(
                        status == LyricsStatus.error ||
                                status == LyricsStatus.notFound
                            ? 'Try again'
                            : 'Find lyrics',
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _CompactPlayer extends StatelessWidget {
  const _CompactPlayer({
    required this.appState,
    required this.current,
    required this.playing,
    required this.progress,
  });

  final AppState appState;
  final MusicTrack? current;
  final bool playing;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MusicoPalette.paper,
      child: InkWell(
        onTap: () => _showNowPlaying(context, appState),
        mouseCursor: SystemMouseCursors.click,
        child: SizedBox(
          height: 61,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: progress.toDouble(),
                  child: Container(height: 2, color: MusicoPalette.terracotta),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    _PlayerArtwork(track: current, size: 37),
                    const SizedBox(width: 11),
                    Expanded(
                      child: _PlayerTrackInfo(
                        track: current,
                        playing: playing,
                        small: true,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Show lyrics',
                      visualDensity: VisualDensity.compact,
                      onPressed: current == null
                          ? null
                          : () => _showLyricsSheet(context, appState),
                      icon: const Icon(Icons.lyrics_outlined, size: 19),
                    ),
                    _PlayButton(
                      playing: playing,
                      canPlay: current != null || appState.tracks.isNotEmpty,
                      onPressed: appState.togglePlayback,
                      size: 37,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNowPlaying(BuildContext context, AppState appState) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: MusicoPalette.paper,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .62,
        maxChildSize: .96,
        builder: (context, scrollController) => AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            final track = appState.currentTrack;
            final queue = appState.visibleTracks;
            final currentIndex = queue.indexWhere(
              (item) => item.id == track?.id,
            );
            final upNext = currentIndex < 0
                ? queue.take(4).toList()
                : queue.skip(currentIndex + 1).take(4).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final artworkSize = (constraints.maxWidth - 48)
                    .clamp(0.0, 340.0)
                    .toDouble();
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Now playing',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close player',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.expand_more_rounded),
                        ),
                      ],
                    ),
                    if (track == null) ...[
                      const SizedBox(height: 42),
                      Text(
                        'Nothing is playing yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appState.tracks.isEmpty
                            ? 'Import audio or find free music to start listening.'
                            : 'Choose a track from your library to start listening.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: MusicoPalette.muted),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: appState.tracks.isEmpty
                            ? null
                            : appState.togglePlayback,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play music'),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Center(
                        child: _PlayerArtwork(track: track, size: artworkSize),
                      ),
                      const SizedBox(height: 23),
                      Row(
                        children: [
                          Expanded(
                            child: _PlayerTrackInfo(
                              track: track,
                              playing: appState.isPlaying,
                            ),
                          ),
                          if (track.license != null)
                            IconButton(
                              tooltip: 'View source and rights',
                              onPressed: () =>
                                  _showTrackDetails(context, track),
                              icon: const Icon(Icons.info_outline_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      StreamBuilder<Duration>(
                        stream: appState.player.positionStream,
                        initialData: appState.player.position,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final total = appState.duration;
                          final maxMs = total.inMilliseconds > 0
                              ? total.inMilliseconds.toDouble()
                              : 1.0;
                          final value = position.inMilliseconds
                              .clamp(0, maxMs.toInt())
                              .toDouble();
                          return Column(
                            children: [
                              Slider(
                                min: 0,
                                max: maxMs,
                                value: value,
                                onChanged: total == Duration.zero
                                    ? null
                                    : (milliseconds) => appState.seek(
                                        Duration(
                                          milliseconds: milliseconds.round(),
                                        ),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    Text(
                                      _formatDuration(total),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            tooltip: appState.shuffle
                                ? 'Shuffle on'
                                : 'Shuffle off',
                            onPressed: appState.toggleShuffle,
                            color: appState.shuffle
                                ? MusicoPalette.forest
                                : MusicoPalette.muted,
                            icon: const Icon(Icons.shuffle_rounded),
                          ),
                          IconButton(
                            tooltip: 'Play previous',
                            onPressed: appState.playPrevious,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 30,
                            ),
                          ),
                          _PlayButton(
                            playing: appState.isPlaying,
                            canPlay: true,
                            onPressed: appState.togglePlayback,
                            size: 60,
                          ),
                          IconButton(
                            tooltip: 'Play next',
                            onPressed: appState.playNext,
                            icon: const Icon(Icons.skip_next_rounded, size: 30),
                          ),
                          IconButton(
                            tooltip: appState.repeatOne
                                ? 'Repeat track on'
                                : 'Repeat off',
                            onPressed: appState.toggleRepeatOne,
                            color: appState.repeatOne
                                ? MusicoPalette.forest
                                : MusicoPalette.muted,
                            icon: const Icon(Icons.repeat_one_rounded),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _showLyricsSheet(context, appState),
                          icon: const Icon(Icons.lyrics_outlined),
                          label: const Text('Lyrics'),
                        ),
                      ),
                      if (upNext.isNotEmpty) ...[
                        const SizedBox(height: 13),
                        Text(
                          'Up next',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        for (final nextTrack in upNext)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _PlayerArtwork(track: nextTrack, size: 44),
                            title: Text(
                              nextTrack.displayMetadata.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              nextTrack.displayMetadata.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => appState.playTrack(nextTrack),
                          ),
                      ],
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({required this.track, required this.size});

  final MusicTrack? track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = track?.artworkPath;
    final fallback = Container(
      color: MusicoPalette.surface,
      alignment: Alignment.center,
      child: Icon(
        Icons.graphic_eq_rounded,
        color: MusicoPalette.olive,
        size: size * .52,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? fallback
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _PlayerTrackInfo extends StatelessWidget {
  const _PlayerTrackInfo({
    required this.track,
    required this.playing,
    this.small = false,
  });

  final MusicTrack? track;
  final bool playing;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final currentTrack = track;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentTrack?.displayMetadata.title ?? 'Nothing playing yet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontSize: small ? 12 : 14),
        ),
        if (currentTrack != null) ...[
          const SizedBox(height: 2),
          Text(
            '${currentTrack.displayMetadata.artist}${currentTrack.license == null ? '' : ' · ${currentTrack.license}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: small ? 11 : 12,
              color: playing ? MusicoPalette.moss : MusicoPalette.muted,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.canPlay,
    required this.onPressed,
    required this.size,
  });

  final bool playing;
  final bool canPlay;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: playing ? 'Pause' : 'Play',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: canPlay
              ? [
                  BoxShadow(
                    color: MusicoPalette.olive.withValues(alpha: .34),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: canPlay ? MusicoPalette.olive : MusicoPalette.canvasAlt,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: canPlay ? onPressed : null,
            mouseCursor: canPlay
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: canPlay ? MusicoPalette.canvas : MusicoPalette.muted,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

Future<void> _showTrackDetails(BuildContext context, MusicTrack track) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(track.displayMetadata.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (track.license case final license?) ...[
                Text('Rights'),
                const SizedBox(height: 3),
                Text(license),
                const SizedBox(height: 10),
              ],
              if (track.attribution case final attribution?) ...[
                Text('Attribution'),
                const SizedBox(height: 3),
                SelectableText(attribution),
                const SizedBox(height: 10),
              ],
              if (track.licenseUrl case final licenseUrl?) ...[
                Text('License details URL'),
                const SizedBox(height: 3),
                SelectableText(licenseUrl),
                const SizedBox(height: 10),
              ],
              if (track.sourceUrl case final sourceUrl?) ...[
                Text('Direct source URL'),
                const SizedBox(height: 3),
                SelectableText(sourceUrl),
              ],
              if (track.artworkPath != null) ...[
                const SizedBox(height: 12),
                const Text('Artwork'),
                const SizedBox(height: 3),
                Text(
                  '${track.artworkTitle ?? track.displayMetadata.title} · ${track.artworkLicense ?? 'license recorded'}',
                ),
                if (track.artworkAttribution case final attribution?) ...[
                  const SizedBox(height: 3),
                  SelectableText(attribution),
                ],
                if (track.artworkSourceUrl case final artworkSourceUrl?) ...[
                  const SizedBox(height: 3),
                  SelectableText(artworkSourceUrl),
                ],
                if (track.artworkLicenseUrl case final artworkLicenseUrl?) ...[
                  const SizedBox(height: 3),
                  SelectableText(artworkLicenseUrl),
                ],
              ],
              if (track.sourceUrl != null && !track.isFromCommons) ...[
                const SizedBox(height: 12),
                Text(
                  'The rights label for this configured download is user-provided and was not independently verified.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> _showVideoDetails(BuildContext context, VideoTrack video) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(video.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (video.rights case final rights?) ...[
                const Text('Rights'),
                const SizedBox(height: 3),
                Text(rights),
                const SizedBox(height: 10),
              ],
              if (video.attribution case final attribution?) ...[
                const Text('Attribution'),
                const SizedBox(height: 3),
                SelectableText(attribution),
                const SizedBox(height: 10),
              ],
              if (video.sourceUrl case final sourceUrl?) ...[
                const Text('Direct source URL'),
                const SizedBox(height: 3),
                SelectableText(sourceUrl),
                const SizedBox(height: 10),
              ],
              const Text(
                'The rights label for this configured download is user-provided and was not independently verified.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
