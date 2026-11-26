import 'package:material_ui/material_ui.dart';

import '../models/youtube_media.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'musico_widgets.dart';
import 'search_autocomplete_field.dart';

Future<void> showYouTubeDownloadDialog(
  BuildContext context, {
  required AppState appState,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => YouTubeDownloadDialog(appState: appState),
  );
}

class YouTubeDownloadDialog extends StatefulWidget {
  const YouTubeDownloadDialog({required this.appState, super.key});

  final AppState appState;

  @override
  State<YouTubeDownloadDialog> createState() => _YouTubeDownloadDialogState();
}

class _YouTubeDownloadDialogState extends State<YouTubeDownloadDialog> {
  final _queryController = TextEditingController();
  final _nameController = TextEditingController();
  YouTubeSearchResult? _selected;
  YouTubeDownloadFormat _format = YouTubeDownloadFormat.mp3;
  String? _qualityLabel;
  List<YouTubeQuality> _qualities = const [];
  bool _loadingQualities = false;
  String? _qualitiesError;

  @override
  void dispose() {
    _queryController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  AppState get _appState => widget.appState;

  String _progressKey() =>
      '${_selected!.videoId}:${_format.name}:${_qualityLabel ?? 'audio'}';

  Future<void> _search([String? submitted]) async {
    final query = (submitted ?? _queryController.text).trim();
    if (query.isEmpty || _appState.isSearchingYouTube) return;
    FocusScope.of(context).unfocus();
    await _appState.searchYouTube(query);
  }

  void _select(YouTubeSearchResult result) {
    setState(() {
      _selected = result;
      _nameController.text = result.title;
      _format = YouTubeDownloadFormat.mp3;
      _qualityLabel = null;
      _qualities = const [];
      _qualitiesError = null;
    });
    _ensureQualities();
  }

  Future<void> _ensureQualities() async {
    final selected = _selected;
    if (selected == null || _format != YouTubeDownloadFormat.mp4) return;
    if (_qualities.isNotEmpty || _loadingQualities) return;
    setState(() {
      _loadingQualities = true;
      _qualitiesError = null;
    });
    try {
      final qualities = await _appState.youtubeQualities(selected.videoId);
      if (!mounted) return;
      setState(() {
        _qualities = qualities;
        _qualityLabel = qualities.isNotEmpty ? qualities.first.label : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _qualitiesError = switch (error) {
          FormatException() => error.message,
          _ => 'Could not load video qualities. Check your connection.',
        };
      });
    } finally {
      if (mounted) setState(() => _loadingQualities = false);
    }
  }

  void _changeFormat(YouTubeDownloadFormat format) {
    setState(() => _format = format);
    if (format == YouTubeDownloadFormat.mp4) _ensureQualities();
  }

  Future<void> _download() async {
    final selected = _selected;
    if (selected == null) return;
    final requestedName = _nameController.text.trim();
    if (requestedName.isEmpty) {
      showMusicoToast(
        context,
        message: 'Enter a name to save this download under.',
        isError: true,
        icon: Icons.error_outline,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final downloaded = await _appState.downloadYouTube(
      result: selected,
      format: _format,
      requestedName: requestedName,
      qualityLabel: _format == YouTubeDownloadFormat.mp4 ? _qualityLabel : null,
    );
    if (!mounted) return;
    showMusicoToast(
      context,
      message: downloaded
          ? 'Saved ${selected.title} on this device.'
          : _appState.youtubeDownloadError ??
                'The download could not be completed.',
      isError: !downloaded,
      icon: downloaded ? Icons.download_done_rounded : Icons.error_outline,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 17, 21, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selected == null
                          ? 'Download from YouTube'
                          : _selected!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: AnimatedBuilder(
                  animation: _appState,
                  builder: (context, _) {
                    return _selected == null
                        ? _buildSearch()
                        : SingleChildScrollView(child: _buildOptions());
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Downloads are for your personal offline listening. Respect the copyright and terms of the content you save.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchAutocompleteField(
          controller: _queryController,
          suggestions: [
            ...AppState.musicSuggestions,
            for (final track in _appState.tracks) ...[
              track.displayMetadata.title,
              track.displayMetadata.artist,
            ],
            ..._appState.youtubeSearchResults.map((result) => result.title),
          ],
          autofocus: true,
          onSubmitted: _search,
          onSelected: _search,
          decoration: InputDecoration(
            labelText: 'Search YouTube',
            hintText: 'Song, artist, or video name…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: _appState.isSearchingYouTube ? null : () => _search(),
              icon: _appState.isSearchingYouTube
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
        const SizedBox(height: 13),
        if (_appState.isSearchingYouTube)
          const _CenteredHint(
            icon: Icons.travel_explore_rounded,
            message: 'Searching YouTube…',
          )
        else if (_appState.youtubeSearchError != null)
          _CenteredHint(
            icon: Icons.error_outline_rounded,
            message: _appState.youtubeSearchError!,
            isError: true,
          )
        else if (_appState.youtubeSearchResults.isEmpty)
          const _CenteredHint(
            icon: Icons.music_video_rounded,
            message: 'Search for a song or video to download it as MP3 or MP4.',
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _appState.youtubeSearchResults.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = _appState.youtubeSearchResults[index];
                return _SearchResultTile(
                  result: result,
                  onTap: result.isLive ? null : () => _select(result),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildOptions() {
    final selected = _selected!;
    final saved = _appState.isYouTubeSaved(selected.videoId, _format);
    final key = _progressKey();
    final downloading = _appState.downloadingYouTubeIds.contains(key);
    final progress = _appState.youtubeDownloadProgress[key];
    final stage = _appState.youtubeDownloadStages[key];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to results',
              onPressed: downloading
                  ? null
                  : () => setState(() => _selected = null),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                '${selected.channel} · ${_durationText(selected.duration)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          enabled: !downloading,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Save as',
            hintText: 'Name for the file and its metadata',
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Used for the file name, embedded tags, and a .metadata.json '
          'sidecar saved next to it.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: MusicoPalette.muted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        SegmentedButton<YouTubeDownloadFormat>(
          segments: const [
            ButtonSegment(
              value: YouTubeDownloadFormat.mp3,
              label: Text('MP3 audio'),
              icon: Icon(Icons.audiotrack_rounded, size: 16),
            ),
            ButtonSegment(
              value: YouTubeDownloadFormat.mp4,
              label: Text('MP4 video'),
              icon: Icon(Icons.videocam_rounded, size: 16),
            ),
          ],
          selected: {_format},
          onSelectionChanged: downloading
              ? null
              : (selection) => _changeFormat(selection.first),
        ),
        if (_format == YouTubeDownloadFormat.mp4) ...[
          const SizedBox(height: 14),
          _buildQualityPicker(),
        ],
        const SizedBox(height: 16),
        if (_appState.youtubeDownloadError != null) ...[
          Text(
            _appState.youtubeDownloadError!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: MusicoPalette.error),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          onPressed: saved || downloading ? null : _download,
          style: saved
              ? FilledButton.styleFrom(
                  backgroundColor: MusicoPalette.moss.withValues(alpha: .16),
                  foregroundColor: MusicoPalette.olive,
                  disabledBackgroundColor: MusicoPalette.moss.withValues(
                    alpha: .16,
                  ),
                  disabledForegroundColor: MusicoPalette.olive,
                )
              : null,
          icon: downloading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MusicoPalette.white,
                  ),
                )
              : Icon(
                  saved ? Icons.check_rounded : Icons.download_rounded,
                  size: 17,
                ),
          label: Text(
            downloading
                ? 'Downloading…'
                : saved
                ? 'Already saved'
                : _format == YouTubeDownloadFormat.mp3
                ? 'Download MP3'
                : 'Download MP4',
          ),
        ),
        if (downloading) ...[
          const SizedBox(height: 10),
          Text(
            '${stage ?? 'Preparing download…'}'
            '${progress == null ? '' : ' · ${(progress * 100).round()}%'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      ],
    );
  }

  Widget _buildQualityPicker() {
    if (_loadingQualities) {
      return _QualityPickerNotice(
        icon: Icons.hourglass_top_rounded,
        message: 'Loading available qualities…',
        trailing: const SizedBox(
          width: 17,
          height: 17,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_qualitiesError != null) {
      return _QualityPickerNotice(
        icon: Icons.error_outline_rounded,
        message: _qualitiesError!,
        isError: true,
        trailing: TextButton(
          onPressed: () {
            setState(() => _qualitiesError = null);
            _ensureQualities();
          },
          child: const Text('Retry'),
        ),
      );
    }
    if (_qualities.isEmpty) {
      return const _QualityPickerNotice(
        icon: Icons.video_settings_outlined,
        message: 'No MP4 quality is available for this video.',
      );
    }
    final selectedQuality =
        _qualities
            .where((quality) => quality.label == _qualityLabel)
            .firstOrNull ??
        _qualities.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final menuItemWidth = (constraints.maxWidth - 72)
            .clamp(160.0, 255.0)
            .toDouble();
        return MenuAnchor(
          crossAxisUnconstrained: false,
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(
              MusicoPalette.surface,
            ),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(10),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 8),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                side: const BorderSide(color: MusicoPalette.line),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          menuChildren: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                'VIDEO QUALITY',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .6,
                  color: MusicoPalette.muted,
                ),
              ),
            ),
            for (final quality in _qualities)
              MenuItemButton(
                onPressed: () => setState(() => _qualityLabel = quality.label),
                leadingIcon: Icon(
                  quality.label == selectedQuality.label
                      ? Icons.check_circle_rounded
                      : Icons.video_settings_outlined,
                  color: quality.label == selectedQuality.label
                      ? MusicoPalette.olive
                      : MusicoPalette.muted,
                  size: 18,
                ),
                style: ButtonStyle(
                  foregroundColor: const WidgetStatePropertyAll(
                    MusicoPalette.ink,
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                child: SizedBox(
                  width: menuItemWidth,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              quality.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (_codecLabel(quality.codec) case final codec?)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  codec,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (quality.sizeLabel.isNotEmpty)
                        Text(
                          quality.sizeLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontFamily: 'IBM Plex Mono',
                                color: MusicoPalette.softInk,
                              ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) {
            return Semantics(
              button: true,
              expanded: controller.isOpen,
              label: 'Video quality: ${selectedQuality.label}',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  borderRadius: BorderRadius.circular(13),
                  child: Ink(
                    padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                    decoration: BoxDecoration(
                      color: MusicoPalette.glass,
                      border: Border.all(
                        color: controller.isOpen
                            ? MusicoPalette.forestLight
                            : MusicoPalette.glassStrong,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.high_quality_rounded,
                          color: MusicoPalette.muted,
                          size: 19,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Quality',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontSize: 11),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                selectedQuality.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (_qualityDetails(selectedQuality)
                                  case final details?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    details,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedRotation(
                          turns: controller.isOpen ? .5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: MusicoPalette.softInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String? _codecLabel(String? codec) {
    if (codec == null || codec.trim().isEmpty) return null;
    final normalized = codec.toLowerCase();
    if (normalized.contains('avc') || normalized.contains('h264')) {
      return 'H.264';
    }
    if (normalized.contains('vp9')) return 'VP9';
    if (normalized.contains('av01') || normalized.contains('av1')) {
      return 'AV1';
    }
    if (normalized.contains('hev') || normalized.contains('h265')) {
      return 'H.265';
    }
    return codec;
  }

  String? _qualityDetails(YouTubeQuality quality) {
    final codec = _codecLabel(quality.codec);
    final size = quality.sizeLabel;
    if (codec == null) return size.isEmpty ? null : size;
    if (size.isEmpty) return codec;
    return '$codec · $size';
  }
}

class _QualityPickerNotice extends StatelessWidget {
  const _QualityPickerNotice({
    required this.icon,
    required this.message,
    this.isError = false,
    this.trailing,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = isError ? MusicoPalette.error : MusicoPalette.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 9, 11),
      decoration: BoxDecoration(
        color: MusicoPalette.glass,
        border: Border.all(color: MusicoPalette.glassStrong),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isError ? MusicoPalette.error : MusicoPalette.softInk,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result, required this.onTap});

  final YouTubeSearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            PosterArtwork(
              imageUrl: result.thumbnailUrl,
              title: result.title,
              width: 92,
              height: 54,
              rounded: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    result.channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (result.isLive)
              const Pill(
                'LIVE',
                background: MusicoPalette.clay,
                foreground: MusicoPalette.terracotta,
              )
            else if (result.duration != null)
              Text(
                _durationText(result.duration),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontFamily: 'IBM Plex Mono', fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

String _durationText(Duration? duration) {
  if (duration == null) return 'Duration unknown';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 30,
            color: isError ? MusicoPalette.error : MusicoPalette.muted,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: isError ? MusicoPalette.error : null),
          ),
        ],
      ),
    );
  }
}
