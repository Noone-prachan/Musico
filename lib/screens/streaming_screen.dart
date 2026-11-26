import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/anime_stream.dart';
import '../models/media_title.dart';
import '../models/stream_watch_progress.dart';
import '../models/watch_media.dart';
import '../services/anime_stream_service.dart';
import '../services/stream_watch_progress_service.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';
import '../widgets/search_autocomplete_field.dart';
import 'stream_player_page.dart';

class StreamingScreen extends StatelessWidget {
  const StreamingScreen({
    required this.appState,
    this.showBackButton = false,
    this.initialTab = 0,
    this.seedQuery,
    this.onOpenTvShows,
    super.key,
  });

  final AppState appState;
  final bool showBackButton;

  final int initialTab;

  final String? seedQuery;

  final ValueChanged<String>? onOpenTvShows;

  @override
  Widget build(BuildContext context) {
    final tab = initialTab.clamp(0, 2).toInt();
    final Widget body = switch (tab) {
      0 => AnimeTab(appState: appState, onFallback: onOpenTvShows),
      1 => ImdbTab(
        key: ValueKey<String>('series-$seedQuery'),
        appState: appState,
        series: true,
        seedQuery: seedQuery,
      ),
      _ => ImdbTab(
        key: ValueKey<String>('movies-$seedQuery'),
        appState: appState,
        series: false,
        seedQuery: seedQuery,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBackButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
        Expanded(child: body),
      ],
    );
  }
}

class AnimeTab extends StatefulWidget {
  const AnimeTab({required this.appState, this.onFallback, super.key});

  final AppState appState;

  final void Function(String query)? onFallback;

  @override
  State<AnimeTab> createState() => _AnimeTabState();
}

class _AnimeTabState extends State<AnimeTab> {
  static const _suggestions = [
    'One Piece',
    'Jujutsu Kaisen',
    'Attack on Titan',
    'Frieren',
    'Demon Slayer',
    'Dandadan',
  ];

  final AnimeStreamService _service = AnimeStreamService();
  final StreamWatchProgressService _progressService =
      StreamWatchProgressService();
  final TextEditingController _searchController = TextEditingController();

  List<AnimeSearchResult> _results = const [];
  List<StreamWatchProgress> _continueWatching = const [];
  bool _loadingContinueWatching = true;
  String? _continueWatchingError;
  bool _searching = false;
  String? _searchError;
  String _lastQuery = '';

  AnimeSearchResult? _show;
  List<AnimeSeasonOption> _seasons = const [];
  List<AnimeEpisode> _episodes = const [];
  bool _loadingShow = false;
  bool _loadingSeasons = false;
  String? _showError;
  String _mode = 'sub';
  String? _openingEpisodeId;
  bool _autoPlayConsumed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContinueWatching());
    final seeded = Platform.environment['MUSICO_STREAM_QUERY']?.trim();
    if (seeded != null && seeded.isNotEmpty) {
      _searchController.text = seeded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runSearch(seeded));
      });
    }
  }

  Future<void> _loadContinueWatching() async {
    try {
      final entries = await _progressService.load(
        category: StreamWatchCategory.anime,
      );
      if (!mounted) return;
      setState(() {
        _continueWatching = entries;
        _loadingContinueWatching = false;
        _continueWatchingError = null;
      });
    } on Exception catch (error, stackTrace) {
      debugPrint('Anime watch progress could not load: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadingContinueWatching = false;
        _continueWatchingError = 'Continue watching could not be loaded.';
      });
    }
  }

  Future<void> _resumeContinueWatching(StreamWatchProgress progress) async {
    final resume = await _askResumeChoice(context, progress);
    if (resume == null) return;
    try {
      final results = await _service.search(progress.title);
      if (!mounted) return;
      AnimeSearchResult? show;
      for (final result in results) {
        if (result.slug == progress.catalogId) {
          show = result;
          break;
        }
      }
      show ??= results.isEmpty ? null : results.first;
      if (show == null) {
        setState(() {
          _continueWatchingError =
              'This anime is no longer available in the catalog.';
        });
        return;
      }

      await _openShow(show);
      if (!mounted) return;
      if (_showError != null) {
        setState(() => _continueWatchingError = _showError);
        return;
      }
      AnimeEpisode? episode;
      for (final candidate in _episodes) {
        if (candidate.id == progress.episodeId ||
            candidate.number == progress.episodeNumber) {
          episode = candidate;
          break;
        }
      }
      if (episode == null) {
        setState(() {
          _continueWatchingError =
              'The saved episode is no longer available for this anime.';
        });
        return;
      }
      await _openEpisode(
        episode,
        resumePositionMs: resume ? progress.positionMs : 0,
      );
    } on AnimeStreamException catch (error, stackTrace) {
      debugPrint('Anime resume lookup failed: $error\n$stackTrace');
      if (mounted) setState(() => _continueWatchingError = error.message);
    } on Exception catch (error, stackTrace) {
      debugPrint('Anime resume lookup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _continueWatchingError =
              'This anime could not be resumed. Check your connection.';
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _runSearch([String? query]) => _performSearch(query);

  Future<void> _runSearchAndOpenMedia(MediaTitle media) =>
      _performSearch(media.title, openMedia: media);

  Future<void> _performSearch(String? query, {MediaTitle? openMedia}) async {
    final cleaned = (query ?? _searchController.text).trim();
    if (cleaned.isEmpty) {
      setState(() {
        _searchError = 'Type an anime title to search the catalog.';
        _results = const [];
      });
      return;
    }
    if (query != null) _searchController.text = query;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _lastQuery = cleaned;
      _show = null;
    });
    try {
      final results = await _service.search(cleaned);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) {
          _searchError = 'No titles matched "$cleaned". Try a shorter title.';
        }
      });
      if (results.isNotEmpty && openMedia != null) {
        final title = openMedia.title.trim().toLowerCase();
        var selected = results.first;
        for (final result in results) {
          if (result.title.trim().toLowerCase() == title ||
              result.japaneseTitle?.trim().toLowerCase() == title) {
            selected = result;
            break;
          }
        }
        await _openShow(selected);
      } else if (results.isNotEmpty &&
          _show == null &&
          Platform.environment['MUSICO_STREAM_AUTOPLAY'] == '1') {
        unawaited(_openShow(results.first));
      }
    } on AnimeStreamException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'The anime catalog could not be reached. ($error)';
      });
    }
  }

  Future<void> _openShow(AnimeSearchResult show) async {
    setState(() {
      _show = show;
      _episodes = const [];
      _seasons = const [];
      _showError = null;
      _loadingShow = true;
      _loadingSeasons = true;
    });
    unawaited(_loadSeasons(show));
    try {
      final episodes = await _service.episodes(show);
      if (!mounted || _show?.slug != show.slug) return;
      setState(() {
        _episodes = episodes;
        _loadingShow = false;
      });
      if (!_autoPlayConsumed &&
          Platform.environment['MUSICO_STREAM_AUTOPLAY'] == '1' &&
          episodes.isNotEmpty) {
        _autoPlayConsumed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openEpisode(episodes.first));
        });
      }
    } on AnimeStreamException catch (error) {
      if (!mounted || _show?.slug != show.slug) return;
      setState(() {
        _showError = error.message;
        _loadingShow = false;
      });
    } on Object catch (error) {
      if (!mounted || _show?.slug != show.slug) return;
      setState(() {
        _showError = 'The episode list could not be loaded. ($error)';
        _loadingShow = false;
      });
    }
  }

  Future<void> _loadSeasons(AnimeSearchResult show) async {
    try {
      final seasons = await _service.relatedSeasons(show.title);
      if (!mounted || _show?.slug != show.slug) return;
      setState(() {
        _seasons = seasons;
        _loadingSeasons = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loadingSeasons = false);
    }
  }

  Future<void> _openSeason(AnimeSeasonOption season) async {
    setState(() => _searching = true);
    try {
      final results = await _service.search(season.title);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _searching = false;
          _showError = 'No episodes were found for "${season.title}".';
        });
        return;
      }
      setState(() => _searching = false);
      await _openShow(results.first);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _showError = 'That season could not be opened. ($error)';
      });
    }
  }

  Future<void> _openEpisode(
    AnimeEpisode episode, {
    int resumePositionMs = 0,
  }) async {
    final show = _show;
    if (show == null) return;
    setState(() => _openingEpisodeId = episode.id);
    try {
      await widget.appState.player.pause();
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Music playback could not be paused before opening an episode: '
        '$error\n$stackTrace',
      );
    }
    if (!mounted) return;
    setState(() => _openingEpisodeId = null);
    final initialIndex = _episodes.indexOf(episode);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StreamPlayerPage(
          title: show.title,
          badge: _mode.toUpperCase(),
          initialIndex: initialIndex,
          category: StreamWatchCategory.anime,
          catalogId: show.slug,
          posterUrl: show.posterUrl,
          initialPositionMs: resumePositionMs,
          episodes: [
            for (final entry in _episodes)
              PlayerEpisode(
                label: 'Episode ${entry.number}',
                title: entry.title,
                id: entry.id,
                episodeNumber: entry.number,
                resolve: () => _service.resolveStream(entry, mode: _mode),
              ),
          ],
        ),
      ),
    );
    await _loadContinueWatching();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 0),
          child: _buildHeader(context, wide),
        ),
        Expanded(
          child: _show == null ? _buildResults(context) : _buildShow(context),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Overline('WATCH · STREAM', icon: Icons.live_tv_rounded),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Every season,\n'),
              TextSpan(
                text: 'any episode.',
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SearchAutocompleteField(
                controller: _searchController,
                suggestions: [
                  ..._suggestions,
                  ..._results.map((result) => result.title),
                  ...widget.appState.seasonTitles.map((title) => title.title),
                  ...widget.appState.upcomingTitles.map((title) => title.title),
                ],
                onSubmitted: (_) => _runSearch(),
                onSelected: (suggestion) {
                  final media = [
                    ...widget.appState.seasonTitles,
                    ...widget.appState.upcomingTitles,
                  ].where((title) => title.title == suggestion).firstOrNull;
                  if (media == null) {
                    unawaited(_runSearch(suggestion));
                  } else {
                    unawaited(_runSearchAndOpenMedia(media));
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Search anime, e.g. "Frieren"',
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _searching ? null : () => _runSearch(),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Third-party streams · watch progress stays on this device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null && _results.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: MusicoPalette.muted.withValues(alpha: .7),
              ),
              const SizedBox(height: 12),
              Text(
                _searchError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => _runSearch(_lastQuery),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Try again'),
                  ),
                  if (widget.onFallback != null && _lastQuery.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => widget.onFallback!(_lastQuery),
                      icon: const Icon(Icons.live_tv_rounded, size: 17),
                      label: const Text('Try TV & movies'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      if (_lastQuery.isEmpty) {
        return _AnimeDiscovery(
          appState: widget.appState,
          suggestions: _suggestions,
          continueWatching: _continueWatching,
          isLoadingContinueWatching: _loadingContinueWatching,
          continueWatchingError: _continueWatchingError,
          onRetryContinueWatching: () => unawaited(_loadContinueWatching()),
          onResume: _resumeContinueWatching,
          onSearch: _runSearch,
          onOpen: (media) => unawaited(_runSearchAndOpenMedia(media)),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 30),
        children: [
          Text(
            'Start with a search',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Search for any series and Musico lists every season and episode it can find.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in _suggestions)
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () => _runSearch(suggestion),
                ),
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
      children: [
        SectionHeading(
          title: 'Results for "$_lastQuery"',
          detail: '${_results.length} titles',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 22,
          children: [
            for (final result in _results)
              SizedBox(
                width: 156,
                child: _ResultCard(
                  result: result,
                  onTap: () => _openShow(result),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildShow(BuildContext context) {
    final show = _show!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MusicoPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MusicoPalette.glassStrong),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PosterArtwork(
                  imageUrl: show.posterUrl,
                  title: show.title,
                  width: 92,
                  height: 128,
                  rounded: 12,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _show = null;
                          _showError = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Back to search'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        show.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (show.japaneseTitle != null &&
                          show.japaneseTitle != show.title) ...[
                        const SizedBox(height: 2),
                        Text(
                          show.japaneseTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (show.subtitleLine.isNotEmpty) show.subtitleLine,
                          if (!_loadingShow) '${_episodes.length} episodes',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_seasons.isNotEmpty || _loadingSeasons) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 32,
                          child: _loadingSeasons
                              ? const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('Finding seasons…'),
                                )
                              : ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _seasons.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 7),
                                  itemBuilder: (context, index) {
                                    final season = _seasons[index];
                                    return ActionChip(
                                      label: Text(season.label),
                                      onPressed: () => _openSeason(season),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _loadingShow ? 'Loading episodes…' : 'Episodes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'sub', label: Text('Sub')),
                  ButtonSegment(value: 'dub', label: Text('Dub')),
                ],
                selected: {_mode},
                onSelectionChanged: (selected) {
                  setState(() => _mode = selected.single);
                },
              ),
            ],
          ),
        ),
        Expanded(child: _buildEpisodeList(context)),
      ],
    );
  }

  Widget _buildEpisodeList(BuildContext context) {
    if (_loadingShow) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _showError;
    if (error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _openShow(_show!),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Reload episodes'),
              ),
            ],
          ),
        ),
      );
    }
    if (_episodes.isEmpty) {
      return const Center(child: Text('No episodes are available yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
      itemCount: _episodes.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 54),
      itemBuilder: (context, index) {
        final episode = _episodes[index];
        final opening = _openingEpisodeId == episode.id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MusicoPalette.canvasAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: MusicoPalette.glassStrong),
            ),
            child: Text(
              '${episode.number}',
              style: const TextStyle(
                color: MusicoPalette.softInk,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            episode.title ?? episode.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            'Episode ${episode.number}${episode.filler ? ' · filler' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: opening
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Play ${episode.label}',
                  onPressed: () => _openEpisode(episode),
                  icon: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: MusicoPalette.forestLight,
                    size: 24,
                  ),
                ),
          onTap: opening ? null : () => _openEpisode(episode),
        );
      },
    );
  }
}

class _AnimeDiscovery extends StatelessWidget {
  const _AnimeDiscovery({
    required this.appState,
    required this.suggestions,
    required this.continueWatching,
    required this.isLoadingContinueWatching,
    required this.continueWatchingError,
    required this.onRetryContinueWatching,
    required this.onResume,
    required this.onSearch,
    required this.onOpen,
  });

  final AppState appState;
  final List<String> suggestions;
  final List<StreamWatchProgress> continueWatching;
  final bool isLoadingContinueWatching;
  final String? continueWatchingError;
  final VoidCallback onRetryContinueWatching;
  final ValueChanged<StreamWatchProgress> onResume;
  final ValueChanged<String> onSearch;
  final ValueChanged<MediaTitle> onOpen;

  @override
  Widget build(BuildContext context) {
    final currentSeason = appState.seasonTitles;
    final upcoming = appState.upcomingTitles;
    final error = appState.errorMessage;
    return RefreshIndicator(
      onRefresh: () => appState.refreshAnime(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
        children: [
          _ContinueWatchingRail(
            entries: continueWatching,
            isLoading: isLoadingContinueWatching,
            error: continueWatchingError,
            onRetry: onRetryContinueWatching,
            onResume: onResume,
          ),
          SectionHeading(
            title: 'Anime releases',
            detail: 'Current-season titles and upcoming premieres from AniList',
            trailing: IconButton(
              tooltip: 'Refresh anime schedule',
              onPressed: appState.isLoadingSchedule
                  ? null
                  : () => unawaited(appState.refreshAnime()),
              icon: appState.isLoadingSchedule
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: MusicoPalette.error),
            ),
          ],
          if (currentSeason.isEmpty && upcoming.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: appState.isLoadingSchedule
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 34,
                          color: MusicoPalette.muted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Anime releases will appear here',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Connect to the internet, then refresh the schedule.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
            ),
          ],
          if (currentSeason.isNotEmpty) ...[
            const SizedBox(height: 20),
            _AnimeTitleSection(
              title: 'Popular now',
              detail:
                  '${currentSeason.length} current-season titles, ranked by popularity',
              titles: currentSeason,
              appState: appState,
              onOpen: onOpen,
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 28),
            _AnimeTitleSection(
              title: 'New seasons & premieres',
              detail: '${upcoming.length} announced premieres',
              titles: upcoming,
              appState: appState,
              onOpen: onOpen,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Looking for a title?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in suggestions)
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () => onSearch(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingRail extends StatelessWidget {
  const _ContinueWatchingRail({
    required this.entries,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.onResume,
  });

  final List<StreamWatchProgress> entries;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<StreamWatchProgress> onResume;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && !isLoading && error == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Continue watching',
          detail:
              error ??
              (isLoading
                  ? 'Loading saved progress'
                  : 'Resume streamed titles on this device'),
          trailing: error == null
              ? null
              : IconButton(
                  tooltip: 'Retry loading watch progress',
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                ),
        ),
        const SizedBox(height: 11),
        if (entries.isNotEmpty)
          SizedBox(
            height: 246,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final detail = entry.episodeTitle == null
                    ? entry.episodeLabel
                    : '${entry.episodeLabel} · ${entry.episodeTitle}';
                return SizedBox(
                  width: 142,
                  child: Semantics(
                    button: true,
                    label:
                        'Continue ${entry.title}, $detail, '
                        '${(entry.playbackProgress * 100).round()} percent watched',
                    child: InkWell(
                      onTap: () => onResume(entry),
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: entry.posterUrl,
                            title: entry.title,
                            width: 142,
                            height: 180,
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
                            detail,
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
                  ),
                );
              },
            ),
          )
        else if (isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (error != null)
          Text(
            error!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: MusicoPalette.error),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onTap});

  final AnimeSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (result.subtitleLine.isNotEmpty) result.subtitleLine,
      if (result.episodeCount != null) '${result.episodeCount} eps',
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              PosterArtwork(
                imageUrl: result.posterUrl,
                title: result.title,
                width: 156,
                height: 216,
                rounded: 14,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: MusicoPalette.forestLight,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: MusicoPalette.canvas,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _AnimeTitleSection extends StatelessWidget {
  const _AnimeTitleSection({
    required this.title,
    required this.detail,
    required this.titles,
    required this.appState,
    required this.onOpen,
  });

  final String title;
  final String detail;
  final List<MediaTitle> titles;
  final AppState appState;
  final ValueChanged<MediaTitle> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title: title, detail: detail),
        const SizedBox(height: 12),
        SizedBox(
          height: 312,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: titles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final media = titles[index];
              final isSaved = appState.watchlist.any(
                (saved) => saved.id == media.id,
              );
              final airing = media.nextAiring;
              final subtitle = airing != null
                  ? 'Episode ${airing.episode} · ${schedulePhrase(media)}'
                  : media.isUpcoming
                  ? media.startDate == null
                        ? 'Premiere date not announced'
                        : '${media.startDate!.year}-${media.startDate!.month.toString().padLeft(2, '0')}-${media.startDate!.day.toString().padLeft(2, '0')} · premiere'
                  : '${media.seasonYear ?? ''} ${prettyFormat(media.format) ?? ''}'
                        .trim();

              return SizedBox(
                width: 142,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => onOpen(media),
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PosterArtwork(
                            imageUrl: media.imageUrl,
                            title: media.title,
                            width: 142,
                            height: 190,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            media.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle.isEmpty
                                ? 'Release details pending'
                                : subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: MusicoPalette.muted),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 48,
                      child: TextButton.icon(
                        onPressed: () => unawaited(
                          isSaved
                              ? appState.removeFromWatchlist(media)
                              : appState.addToWatchlist(media),
                        ),
                        icon: Icon(
                          isSaved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_add_outlined,
                          size: 16,
                        ),
                        label: Text(isSaved ? 'Saved' : 'Watchlist'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

const _tvSuggestions = [
  'The Bear',
  'Breaking Bad',
  'Game of Thrones',
  'Severance',
  'The Last of Us',
];

const _movieSuggestions = [
  'Inception',
  'Dune',
  'Interstellar',
  'Oppenheimer',
  'Spider-Man',
];

List<WatchTitle> _fallbackWatchTitles(
  List<String> suggestions, {
  required bool series,
}) {
  return [
    for (final title in suggestions)
      WatchTitle(imdbId: '', title: title, kind: series ? 'tvSeries' : 'movie'),
  ];
}

Future<List<WatchTitle>> _loadWatchSuggestions(
  WatchService service,
  List<String> suggestions, {
  required bool series,
}) async {
  final resultSets = await Future.wait(
    suggestions.map((query) => service.search(query, series: series)),
  );
  final byId = <String, WatchTitle>{};
  for (final results in resultSets) {
    if (results.isNotEmpty) {
      byId.putIfAbsent(results.first.imdbId, () => results.first);
    }
  }
  return byId.values.toList();
}

class _WatchTitleRail extends StatelessWidget {
  const _WatchTitleRail({
    required this.title,
    required this.detail,
    required this.titles,
    required this.isLoading,
    required this.onOpen,
    this.trailing,
  });

  final String title;
  final String detail;
  final List<WatchTitle> titles;
  final bool isLoading;
  final ValueChanged<WatchTitle> onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(title: title, detail: detail, trailing: trailing),
        const SizedBox(height: 11),
        if (titles.isNotEmpty)
          SizedBox(
            height: 246,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: titles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = titles[index];
                return SizedBox(
                  width: 142,
                  child: InkWell(
                    onTap: () => onOpen(item),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PosterArtwork(
                          imageUrl: item.posterUrl,
                          title: item.title,
                          width: 142,
                          height: 180,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: MusicoPalette.muted),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              isLoading
                  ? 'Refreshing title suggestions…'
                  : 'No titles are available right now.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (isLoading) ...[
          const SizedBox(height: 4),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }
}

class _SeasonPremiereRail extends StatelessWidget {
  const _SeasonPremiereRail({
    required this.premieres,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final List<WatchSeasonPremiere> premieres;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<WatchTitle> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'New seasons',
          detail: 'Season premieres in the next 7 days · TVMaze',
          trailing: IconButton(
            tooltip: 'Refresh season premieres',
            onPressed: isLoading ? null : onRetry,
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 11),
        if (premieres.isNotEmpty)
          SizedBox(
            height: 246,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: premieres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final premiere = premieres[index];
                final airdate = DateTime.parse(premiere.episode.airdate!);
                return SizedBox(
                  width: 142,
                  child: InkWell(
                    onTap: () => onOpen(premiere.show),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PosterArtwork(
                          imageUrl: premiere.show.posterUrl,
                          title: premiere.show.title,
                          width: 142,
                          height: 180,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          premiere.show.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Season ${premiere.season} · ${_shortDate(airdate)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: MusicoPalette.muted),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              error ??
                  (isLoading
                      ? 'Checking the schedule for returning seasons…'
                      : 'No returning-season premieres are listed this week.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: error == null
                    ? MusicoPalette.muted
                    : MusicoPalette.error,
              ),
            ),
          ),
      ],
    );
  }
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

class ImdbTab extends StatefulWidget {
  const ImdbTab({
    required this.appState,
    required this.series,
    this.seedQuery,
    super.key,
  });

  final AppState appState;
  final bool series;

  final String? seedQuery;

  @override
  State<ImdbTab> createState() => _ImdbTabState();
}

class _ImdbTabState extends State<ImdbTab> {
  final WatchService _service = WatchService();
  final StreamWatchProgressService _progressService =
      StreamWatchProgressService();
  final TextEditingController _searchController = TextEditingController();

  List<WatchTitle> _results = const [];
  List<StreamWatchProgress> _continueWatching = const [];
  bool _loadingContinueWatching = true;
  String? _continueWatchingError;
  bool _searching = false;
  String? _error;
  String _lastQuery = '';

  WatchTitle? _selected;
  List<WatchEpisode> _episodes = const [];
  bool _loadingTitle = false;
  String? _titleError;
  int? _season;
  String? _openingId;
  bool _autoPlayConsumed = false;
  List<WatchTitle> _featuredTitles = const [];
  bool _loadingFeatured = false;
  String? _featuredError;
  List<WatchSeasonPremiere> _seasonPremieres = const [];
  bool _loadingPremieres = false;
  String? _premiereError;

  List<WatchEpisode> get _seasonEpisodes => _season == null
      ? const []
      : _episodes.where((episode) => episode.season == _season).toList();

  List<int> get _seasons {
    final set = <int>{for (final episode in _episodes) episode.season};
    final list = set.toList()..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadContinueWatching());
    _featuredTitles = _fallbackWatchTitles(
      widget.series ? _tvSuggestions : _movieSuggestions,
      series: widget.series,
    );
    if (widget.series) unawaited(_loadSeasonPremieres());
    final seeded =
        widget.seedQuery?.trim() ??
        Platform.environment['MUSICO_WATCH_QUERY']?.trim();
    final tab = Platform.environment['MUSICO_WATCH_TAB'] ?? 'tv';
    final wanted = widget.series ? 'tv' : 'movie';
    if (seeded != null &&
        seeded.isNotEmpty &&
        (widget.seedQuery != null || tab == wanted)) {
      _searchController.text = seeded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_runSearch(seeded));
      });
    } else {
      unawaited(_loadFeatured());
    }
  }

  Future<void> _loadContinueWatching() async {
    try {
      final entries = await _progressService.load(
        category: widget.series
            ? StreamWatchCategory.tvShow
            : StreamWatchCategory.movie,
      );
      if (!mounted) return;
      setState(() {
        _continueWatching = entries;
        _loadingContinueWatching = false;
        _continueWatchingError = null;
      });
    } on Exception catch (error, stackTrace) {
      debugPrint('Watch progress could not load: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadingContinueWatching = false;
        _continueWatchingError = 'Continue watching could not be loaded.';
      });
    }
  }

  Future<void> _resumeContinueWatching(StreamWatchProgress progress) async {
    final resume = await _askResumeChoice(context, progress);
    if (resume == null) return;
    try {
      final results = await _service.search(
        progress.title,
        series: widget.series,
      );
      if (!mounted) return;
      WatchTitle? title;
      for (final result in results) {
        if (result.imdbId == progress.catalogId) {
          title = result;
          break;
        }
      }
      title ??= results.isEmpty ? null : results.first;
      if (title == null) {
        setState(() {
          _continueWatchingError =
              'This title is no longer available in the catalog.';
        });
        return;
      }

      if (!widget.series) {
        await _playMovie(
          title,
          initialPositionMs: resume ? progress.positionMs : 0,
        );
        return;
      }

      await _openTitle(title);
      if (!mounted) return;
      if (_titleError != null) {
        setState(() => _continueWatchingError = _titleError);
        return;
      }
      if (progress.season != null) {
        setState(() => _season = progress.season);
      }
      WatchEpisode? episode;
      for (final candidate in _episodes) {
        if (candidate.season == progress.season &&
            candidate.number == progress.episodeNumber) {
          episode = candidate;
          break;
        }
      }
      if (episode != null) {
        await _playEpisode(
          title,
          episode,
          resumePositionMs: resume ? progress.positionMs : 0,
        );
      } else if (progress.season != null && progress.episodeNumber != null) {
        await _playManual(
          title,
          progress.season!,
          progress.episodeNumber!,
          resumePositionMs: resume ? progress.positionMs : 0,
        );
      } else {
        setState(() {
          _continueWatchingError =
              'The saved episode is no longer available for this show.';
        });
      }
    } on WatchException catch (error, stackTrace) {
      debugPrint('Stream resume lookup failed: $error\n$stackTrace');
      if (mounted) setState(() => _continueWatchingError = error.message);
    } on Exception catch (error, stackTrace) {
      debugPrint('Stream resume lookup failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _continueWatchingError =
              'This title could not be resumed. Check your connection.';
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadFeatured() async {
    setState(() {
      _loadingFeatured = true;
      _featuredError = null;
    });
    final suggestions = widget.series ? _tvSuggestions : _movieSuggestions;
    try {
      final titles = await _loadWatchSuggestions(
        _service,
        suggestions,
        series: widget.series,
      );
      if (!mounted) return;
      setState(() {
        _featuredTitles = titles.isEmpty
            ? _fallbackWatchTitles(suggestions, series: widget.series)
            : titles;
        if (titles.isEmpty) {
          _featuredError =
              'No featured matches were returned. Search for any title.';
        }
        _loadingFeatured = false;
      });
    } on WatchException catch (error, stackTrace) {
      debugPrint('Featured title metadata could not load: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _featuredTitles = _fallbackWatchTitles(
          suggestions,
          series: widget.series,
        );
        _featuredError = 'Featured details could not refresh. ${error.message}';
        _loadingFeatured = false;
      });
    }
  }

  Future<void> _loadSeasonPremieres() async {
    setState(() {
      _loadingPremieres = true;
      _premiereError = null;
    });
    try {
      final premieres = await _service.upcomingSeasonPremieres();
      if (!mounted) return;
      setState(() => _seasonPremieres = premieres);
    } on WatchException catch (error, stackTrace) {
      debugPrint('TV season premieres could not load: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _premiereError =
            'New season listings could not refresh. ${error.message}';
      });
    } finally {
      if (mounted) setState(() => _loadingPremieres = false);
    }
  }

  Future<void> _runSearch([String? query]) async {
    final cleaned = (query ?? _searchController.text).trim();
    if (cleaned.isEmpty) {
      setState(() {
        _error = 'Type a title to search.';
        _results = const [];
      });
      return;
    }
    if (query != null) _searchController.text = query;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _searching = true;
      _error = null;
      _lastQuery = cleaned;
      _selected = null;
    });
    try {
      final results = await _service.search(cleaned, series: widget.series);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) {
          _error =
              'No ${widget.series ? 'shows' : 'movies'} matched "$cleaned".';
        }
      });
      if (results.isNotEmpty &&
          _selected == null &&
          Platform.environment['MUSICO_WATCH_AUTOPLAY'] == '1') {
        unawaited(_openTitle(results.first));
      }
    } on WatchException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'The catalog could not be reached. ($error)';
      });
    }
  }

  Future<void> _openTitle(WatchTitle title) async {
    setState(() {
      _selected = title;
      _episodes = const [];
      _season = null;
      _titleError = null;
      _loadingTitle = title.isSeries;
    });
    if (title.isMovie) {
      if (Platform.environment['MUSICO_WATCH_AUTOPLAY'] == '1') {
        unawaited(_playMovie(title));
      }
      return;
    }
    final episodes = await _service.episodes(title);
    if (!mounted || _selected?.imdbId != title.imdbId) return;
    setState(() {
      _episodes = episodes;
      _season = episodes.isEmpty ? null : episodes.first.season;
      _loadingTitle = false;
      if (episodes.isEmpty) {
        _titleError = null;
      }
    });
    if (episodes.isNotEmpty &&
        !_autoPlayConsumed &&
        Platform.environment['MUSICO_WATCH_AUTOPLAY'] == '1') {
      _autoPlayConsumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_playEpisode(title, episodes.first));
      });
    }
  }

  Future<void> _pauseMusic() async {
    try {
      await widget.appState.player.pause();
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Music playback could not be paused before opening a movie: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> _playMovie(WatchTitle movie, {int initialPositionMs = 0}) async {
    await _pauseMusic();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StreamPlayerPage(
          title: movie.title,
          badge: movie.typeLabel,
          initialIndex: 0,
          category: StreamWatchCategory.movie,
          catalogId: movie.imdbId,
          posterUrl: movie.posterUrl,
          initialPositionMs: initialPositionMs,
          episodes: [
            PlayerEpisode(
              label: movie.year == null ? 'Movie' : '${movie.year}',
              title: movie.title,
              id: 'movie',
              resolve: () => _service.resolveMovie(movie),
            ),
          ],
        ),
      ),
    );
    await _loadContinueWatching();
  }

  Future<void> _playEpisode(
    WatchTitle show,
    WatchEpisode episode, {
    int resumePositionMs = 0,
  }) async {
    final list = _seasonEpisodes;
    final index = list.indexWhere(
      (entry) =>
          entry.season == episode.season && entry.number == episode.number,
    );
    await _pauseMusic();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StreamPlayerPage(
          title: show.title,
          badge: 'S${episode.season}',
          initialIndex: index < 0 ? 0 : index,
          category: StreamWatchCategory.tvShow,
          catalogId: show.imdbId,
          posterUrl: show.posterUrl,
          initialPositionMs: resumePositionMs,
          episodes: [
            for (final entry in (list.isEmpty ? [episode] : list))
              PlayerEpisode(
                label: 'E${entry.number}',
                title: entry.displayTitle,
                id: '${entry.season}-${entry.number}',
                season: entry.season,
                episodeNumber: entry.number,
                resolve: () => _service.resolveEpisode(show, entry),
              ),
          ],
        ),
      ),
    );
    await _loadContinueWatching();
  }

  Future<void> _playManual(
    WatchTitle show,
    int season,
    int episode, {
    int resumePositionMs = 0,
  }) async {
    await _pauseMusic();
    if (!mounted) return;
    final entry = WatchEpisode(season: season, number: episode);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StreamPlayerPage(
          title: show.title,
          badge: 'S$season',
          initialIndex: 0,
          category: StreamWatchCategory.tvShow,
          catalogId: show.imdbId,
          posterUrl: show.posterUrl,
          initialPositionMs: resumePositionMs,
          episodes: [
            PlayerEpisode(
              label: 'E$episode',
              id: '$season-$episode',
              season: season,
              episodeNumber: episode,
              resolve: () => _service.resolveEpisode(show, entry),
            ),
          ],
        ),
      ),
    );
    await _loadContinueWatching();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 18, wide ? 32 : 18, 0),
          child: _buildHeader(context, wide),
        ),
        Expanded(
          child: _selected == null
              ? _buildResults(context)
              : _buildDetail(context),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool wide) {
    final label = widget.series ? 'WATCH · SERIES' : 'WATCH · MOVIES';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Overline(
          label,
          icon: widget.series ? Icons.live_tv_rounded : Icons.movie_rounded,
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.series ? 'Every episode,\n' : 'Movie night,\n',
              ),
              TextSpan(
                text: widget.series ? 'on demand.' : 'every night.',
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SearchAutocompleteField(
                controller: _searchController,
                suggestions: [
                  ...(widget.series ? _tvSuggestions : _movieSuggestions),
                  ..._featuredTitles.map((title) => title.title),
                  ..._results.map((title) => title.title),
                ],
                onSubmitted: (_) => _runSearch(),
                onSelected: _runSearch,
                decoration: InputDecoration(
                  hintText: widget.series
                      ? 'Search a series, e.g. "The Bear"'
                      : 'Search a movie, e.g. "Dune"',
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _searching ? null : () => _runSearch(),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Third-party streams · watch progress stays on this device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null &&
        _results.isEmpty &&
        (_lastQuery.isNotEmpty || _featuredTitles.isEmpty)) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 34,
                color: MusicoPalette.muted.withValues(alpha: .7),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _runSearch(_lastQuery),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final suggestions = widget.series ? _tvSuggestions : _movieSuggestions;
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 30),
        children: [
          _ContinueWatchingRail(
            entries: _continueWatching,
            isLoading: _loadingContinueWatching,
            error: _continueWatchingError,
            onRetry: () => unawaited(_loadContinueWatching()),
            onResume: _resumeContinueWatching,
          ),
          if (widget.series) ...[
            _SeasonPremiereRail(
              premieres: _seasonPremieres,
              isLoading: _loadingPremieres,
              error: _premiereError,
              onRetry: () => unawaited(_loadSeasonPremieres()),
              onOpen: (title) => unawaited(_openTitle(title)),
            ),
            const SizedBox(height: 24),
          ],
          _WatchTitleRail(
            title: widget.series ? 'Featured TV shows' : 'Featured movies',
            detail: 'Suggested titles · metadata from IMDb',
            titles: _featuredTitles,
            isLoading: _loadingFeatured,
            onOpen: (title) => unawaited(_openTitle(title)),
            trailing: IconButton(
              tooltip: 'Refresh featured suggestions',
              onPressed: _loadingFeatured
                  ? null
                  : () => unawaited(_loadFeatured()),
              icon: _loadingFeatured
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ),
          if (_featuredError != null) ...[
            const SizedBox(height: 12),
            Text(
              _featuredError!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: MusicoPalette.error),
            ),
          ],
          const SizedBox(height: 26),
          Text('Explore more', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            widget.series
                ? 'Look up a show to see its current seasons and episode schedule.'
                : 'Look up a film by title.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in suggestions)
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () => _runSearch(suggestion),
                ),
            ],
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 30),
      children: [
        SectionHeading(
          title: 'Results for "$_lastQuery"',
          detail: '${_results.length} titles',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 22,
          children: [
            for (final result in _results)
              SizedBox(
                width: 148,
                child: _WatchResultCard(
                  title: result,
                  onTap: () => _openTitle(result),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final title = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MusicoPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MusicoPalette.glassStrong),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PosterArtwork(
                  imageUrl: title.posterUrl,
                  title: title.title,
                  width: 92,
                  height: 128,
                  rounded: 12,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selected = null;
                          _titleError = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Back to search'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (title.subtitleLine.isNotEmpty) title.subtitleLine,
                          if (!_loadingTitle && title.isSeries)
                            '${_episodes.length} episodes',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      if (title.isMovie)
                        FilledButton.icon(
                          onPressed: () => _playMovie(title),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Play movie'),
                        )
                      else if (_loadingTitle)
                        const Text('Loading episodes…')
                      else if (_titleError != null)
                        Text(
                          _titleError!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (title.isSeries && _seasons.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _seasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final season = _seasons[index];
                  final selected = _season == season;
                  return ChoiceChip(
                    label: Text('Season $season'),
                    selected: selected,
                    onSelected: (_) => setState(() => _season = season),
                  );
                },
              ),
            ),
          ),
        ],
        Expanded(child: _buildEpisodes(context, title)),
      ],
    );
  }

  Widget _buildEpisodes(BuildContext context, WatchTitle title) {
    if (title.isMovie) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        children: [
          Text(
            'Streams instantly in the built-in player — no download step.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      );
    }
    if (_loadingTitle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_episodes.isEmpty) {
      return _ManualEpisodePicker(
        onPlay: (season, episode) => _playManual(title, season, episode),
      );
    }
    final list = _seasonEpisodes;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 54),
      itemBuilder: (context, index) {
        final episode = list[index];
        final opening = _openingId == '${episode.season}-${episode.number}';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MusicoPalette.canvasAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: MusicoPalette.glassStrong),
            ),
            child: Text(
              '${episode.number}',
              style: const TextStyle(
                color: MusicoPalette.softInk,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            episode.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            [
              'S${episode.season} · E${episode.number}',
              if (episode.airdate != null) episode.airdate!,
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: opening
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Play ${episode.label}',
                  onPressed: () {
                    setState(
                      () => _openingId = '${episode.season}-${episode.number}',
                    );
                    unawaited(_playEpisode(title, episode));
                  },
                  icon: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: MusicoPalette.forestLight,
                    size: 24,
                  ),
                ),
          onTap: opening ? null : () => _playEpisode(title, episode),
        );
      },
    );
  }
}

Future<bool?> _askResumeChoice(
  BuildContext context,
  StreamWatchProgress progress,
) {
  final position = Duration(milliseconds: progress.positionMs);
  final time =
      '${position.inMinutes}:'
      '${(position.inSeconds % 60).toString().padLeft(2, '0')}';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Continue watching?'),
      content: Text(
        'Resume ${progress.title} · ${progress.episodeLabel} from $time, '
        'or start this video from the beginning?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Start from beginning'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Resume'),
        ),
      ],
    ),
  );
}

class _ManualEpisodePicker extends StatefulWidget {
  const _ManualEpisodePicker({required this.onPlay});

  final void Function(int season, int episode) onPlay;

  @override
  State<_ManualEpisodePicker> createState() => _ManualEpisodePickerState();
}

class _ManualEpisodePickerState extends State<_ManualEpisodePicker> {
  int _season = 1;
  int _episode = 1;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
      children: [
        Text(
          'Episode list unavailable. Pick the season and episode manually.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _season,
                decoration: const InputDecoration(labelText: 'Season'),
                items: [
                  for (var value = 1; value <= 30; value++)
                    DropdownMenuItem(value: value, child: Text('$value')),
                ],
                onChanged: (value) => setState(() => _season = value ?? 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _episode,
                decoration: const InputDecoration(labelText: 'Episode'),
                items: [
                  for (var value = 1; value <= 60; value++)
                    DropdownMenuItem(value: value, child: Text('$value')),
                ],
                onChanged: (value) => setState(() => _episode = value ?? 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => widget.onPlay(_season, _episode),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Play S$_season · E$_episode'),
        ),
      ],
    );
  }
}

class _WatchResultCard extends StatelessWidget {
  const _WatchResultCard({required this.title, required this.onTap});

  final WatchTitle title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              PosterArtwork(
                imageUrl: title.posterUrl,
                title: title.title,
                width: 148,
                height: 214,
                rounded: 14,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: MusicoPalette.forestLight,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    title.isSeries
                        ? Icons.playlist_play_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                    color: MusicoPalette.canvas,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (title.subtitleLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              title.subtitleLine,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
