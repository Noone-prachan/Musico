import 'package:material_ui/material_ui.dart';

import '../models/media_download.dart';
import '../models/spotify_playlist.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'configured_downloads_dialog.dart';
import 'musico_widgets.dart';

Future<void> importSpotifyPlaylistMetadata(
  BuildContext context,
  AppState appState,
) async {
  final count = await appState.importSpotifyPlaylistMetadata();
  if (!context.mounted || count == null) return;
  final error = appState.spotifyPlaylistImportErrorMessage;
  showMusicoToast(
    context,
    message:
        error ??
        'Imported $count Spotify playlist${count == 1 ? '' : 's'}. Downloads use your configured direct links.',
    isError: error != null,
    icon: error == null ? Icons.playlist_add_check_rounded : null,
  );
}

class SpotifyPlaylistSection extends StatelessWidget {
  const SpotifyPlaylistSection({required this.appState, super.key});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final playlists = appState.spotifyPlaylists;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              title: 'Spotify playlists',
              detail: 'Metadata only · downloads use your direct links.',
              trailing: TextButton.icon(
                onPressed: () =>
                    importSpotifyPlaylistMetadata(context, appState),
                icon: const Icon(Icons.file_open_outlined, size: 16),
                label: const Text('Import JSON'),
              ),
            ),
            const SizedBox(height: 10),
            if (playlists.isEmpty)
              _EmptySpotifyPlaylists(
                onImport: () =>
                    importSpotifyPlaylistMetadata(context, appState),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: MusicoPalette.paper,
                  border: Border.all(color: MusicoPalette.line),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    for (var index = 0; index < playlists.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      _SpotifyPlaylistTile(
                        playlist: playlists[index],
                        appState: appState,
                      ),
                    ],
                  ],
                ),
              ),
            if (appState.spotifyPlaylistImportErrorMessage case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: MusicoPalette.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptySpotifyPlaylists extends StatelessWidget {
  const _EmptySpotifyPlaylists({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MusicoPalette.paper,
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.library_music_outlined,
            color: MusicoPalette.forest,
            size: 21,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Import a Spotify playlist JSON export to see its track metadata here. Add authorized direct file links in Settings to download matching tracks inside Musico.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Import Spotify playlist JSON',
            onPressed: onImport,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
    );
  }
}

class _SpotifyPlaylistTile extends StatelessWidget {
  const _SpotifyPlaylistTile({required this.playlist, required this.appState});

  final SpotifyPlaylist playlist;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final matches = playlist.tracks
        .map(appState.configuredDownloadForSpotifyTrack)
        .whereType<MediaDownloadLink>()
        .length;
    return ExpansionTile(
      key: PageStorageKey<String>(playlist.id),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(
        '${playlist.tracks.length} tracks · $matches direct links available',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        if (playlist.tracks.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No tracks in this playlist export.'),
          )
        else
          for (final track in playlist.tracks)
            _SpotifyTrackRow(track: track, appState: appState),
      ],
    );
  }
}

class _SpotifyTrackRow extends StatelessWidget {
  const _SpotifyTrackRow({required this.track, required this.appState});

  final SpotifyPlaylistTrack track;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final download = appState.configuredDownloadForSpotifyTrack(track);
    final saved =
        download != null && appState.isConfiguredDownloadSaved(download);
    final downloading =
        download != null &&
        appState.downloadingConfiguredIds.contains(download.progressKey);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 12, 5),
      child: Row(
        children: [
          const Icon(
            Icons.music_note_rounded,
            size: 16,
            color: MusicoPalette.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (track.artist case final artist?) ...[
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: MusicoPalette.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 7),
          if (download == null)
            TextButton(
              onPressed: () => showConfiguredDownloadsDialog(
                context,
                appState: appState,
                category: MediaDownloadCategory.music,
                initialQuery: track.title,
              ),
              child: const Text('Find link'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: saved || downloading
                  ? null
                  : () => _download(context, download),
              icon: downloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      saved ? Icons.check_rounded : Icons.download_rounded,
                      size: 15,
                    ),
              label: Text(saved ? 'Saved' : 'Download'),
            ),
        ],
      ),
    );
  }

  Future<void> _download(
    BuildContext context,
    MediaDownloadLink download,
  ) async {
    final success = await appState.downloadConfiguredMedia(download);
    if (!context.mounted) return;
    final error = appState.configuredDownloadErrorMessage;
    showMusicoToast(
      context,
      message: success
          ? 'Saved ${download.title} on this device.'
          : error ?? 'The download could not be completed.',
      isError: !success,
      icon: success ? Icons.download_done_rounded : Icons.error_outline,
    );
  }
}
