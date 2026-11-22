import 'package:material_ui/material_ui.dart';

import '../models/media_download.dart';
import '../models/media_title.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/musico_widgets.dart';
import '../widgets/configured_downloads_dialog.dart';

class AnimeScreen extends StatefulWidget {
  const AnimeScreen({required this.appState, super.key});

  final AppState appState;

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  static const _animeSuggestions = [
    'Frieren',
    'Solo Leveling',
    'Spy x Family',
    'Demon Slayer',
    'Jujutsu Kaisen',
  ];

  late final _searchController = TextEditingController(
    text: widget.appState.searchQuery,
  );

  AppState get appState => widget.appState;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    await appState.searchAnime(_searchController.text);
  }

  void _selectCollection(ReleaseCollection collection) {
    _searchController.clear();
    appState.setCollection(collection);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1050;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 52 : 26, 33, wide ? 52 : 26, 35),
      children: [
        _CalendarHeading(appState: appState),
        const SizedBox(height: 23),
        _CollectionSwitch(appState: appState, onSelect: _selectCollection),
        const SizedBox(height: 17),
        _AnimeSearchField(
          controller: _searchController,
          onSearch: _search,
          onChanged: (value) {
            setState(() {});
            if (appState.releaseCollection != ReleaseCollection.search &&
                value.isEmpty) {
              appState.setSearchQuery('');
            }
          },
        ),
        if (_searchController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final suggestion in _animeSuggestions.where(
                (title) => title.toLowerCase().contains(
                  _searchController.text.trim().toLowerCase(),
                ),
              ))
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _searchController.text = suggestion;
                    _search();
                  },
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          TextButton.icon(
            onPressed: () => showConfiguredDownloadsDialog(
              context,
              appState: appState,
              category: MediaDownloadCategory.anime,
              initialQuery: _searchController.text,
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download configured anime episodes'),
          ),
        ],
        if (appState.releaseCollection == ReleaseCollection.weekly) ...[
          const SizedBox(height: 18),
          _DayPicker(appState: appState),
        ],
        const SizedBox(height: 25),
        _ReleaseSection(appState: appState),
        const SizedBox(height: 17),
        _ScheduleFinePrint(appState: appState),
      ],
    );
  }
}

class _CalendarHeading extends StatelessWidget {
  const _CalendarHeading({required this.appState});

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
                'Anime releases',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width > 600 ? 43 : 36,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Episodes, premieres and the series you want to follow.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: MusicoPalette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: appState.isLoadingSchedule
              ? 'Refreshing anime releases'
              : 'Refresh the anime release calendar',
          onPressed: appState.isLoadingSchedule
              ? null
              : () => appState.refreshAnime(),
          style: IconButton.styleFrom(
            foregroundColor: MusicoPalette.forest,
            backgroundColor: MusicoPalette.canvasAlt,
            minimumSize: Size(compact ? 42 : 46, compact ? 42 : 46),
          ),
          icon: appState.isLoadingSchedule
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
    );
  }
}

class _CollectionSwitch extends StatelessWidget {
  const _CollectionSwitch({required this.appState, required this.onSelect});

  final AppState appState;
  final ValueChanged<ReleaseCollection> onSelect;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MusicoPalette.canvasAlt.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          _CollectionButton(
            label: 'This week',
            icon: Icons.calendar_month_rounded,
            selected: appState.releaseCollection == ReleaseCollection.weekly,
            onTap: () => onSelect(ReleaseCollection.weekly),
          ),
          _CollectionButton(
            label: compact ? 'Series' : 'Anime series',
            icon: Icons.tv_rounded,
            selected:
                appState.releaseCollection == ReleaseCollection.upcomingSeries,
            onTap: () => onSelect(ReleaseCollection.upcomingSeries),
          ),
          _CollectionButton(
            label: compact ? 'Movies' : 'Anime movies',
            icon: Icons.movie_creation_outlined,
            selected:
                appState.releaseCollection == ReleaseCollection.upcomingMovies,
            onTap: () => onSelect(ReleaseCollection.upcomingMovies),
          ),
        ],
      ),
    );
  }
}

class _CollectionButton extends StatelessWidget {
  const _CollectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? MusicoPalette.forest : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MusicoPalette.forest : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: MusicoPalette.ink.withValues(alpha: .045),
                    blurRadius: 9,
                    offset: const Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 430 ? 9 : 13,
                vertical: 11,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? MusicoPalette.white : MusicoPalette.muted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? MusicoPalette.white
                            : MusicoPalette.softInk,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimeSearchField extends StatelessWidget {
  const _AnimeSearchField({
    required this.controller,
    required this.onSearch,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search anime movies and series to save…',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: IconButton(
          tooltip: 'Search AniList',
          onPressed: onSearch,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        ),
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = DateTime(today.year, today.month, today.day + index);
          final selected = _sameDay(date, appState.selectedDate);
          final label = index == 0
              ? 'Today'
              : index == 1
              ? 'Tomorrow'
              : _weekday(date);
          return InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => appState.setSelectedDate(date),
            mouseCursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              width: 69,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: selected ? MusicoPalette.forest : MusicoPalette.paper,
                border: Border.all(
                  color: selected ? MusicoPalette.forest : MusicoPalette.line,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? MusicoPalette.white
                          : MusicoPalette.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: selected ? MusicoPalette.white : MusicoPalette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReleaseSection extends StatelessWidget {
  const _ReleaseSection({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final titles = appState.visibleReleaseTitles;
    final weekly = appState.releaseCollection == ReleaseCollection.weekly;
    final isSearch = appState.releaseCollection == ReleaseCollection.search;
    final isUpcoming = appState.isUpcomingCollection;
    final heading = isSearch
        ? 'Search results'
        : weekly
        ? '${_weekdayFull(appState.selectedDate)} releases'
        : appState.releaseCollection == ReleaseCollection.upcomingMovies
        ? 'Upcoming anime movies'
        : 'Upcoming anime series';
    final eyebrow = isSearch
        ? 'ANIList SEARCH'
        : weekly
        ? '${_shortDate(appState.selectedDate)} · ${appState.currentSeasonLabel}'
        : 'ANNOUNCED ANIME';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: heading,
          detail: eyebrow,
          trailing: titles.isEmpty
              ? null
              : Text(
                  '${titles.length} ${titles.length == 1 ? 'title' : 'titles'}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                ),
        ),
        const SizedBox(height: 13),
        if (titles.isEmpty)
          _EmptyReleases(
            appState: appState,
            loading: appState.isLoadingSchedule || appState.isSearching,
            hasError: appState.errorMessage != null,
            error: appState.errorMessage,
            isSearch: isSearch,
            isUpcoming: isUpcoming,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 980
                  ? 3
                  : width >= 650
                  ? 2
                  : 1;
              const spacing = 11.0;
              final itemWidth = (width - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final title in titles)
                    SizedBox(
                      width: itemWidth,
                      child: ReleaseCard(title: title, appState: appState),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class ReleaseCard extends StatelessWidget {
  const ReleaseCard({required this.title, required this.appState, super.key});

  final MediaTitle title;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final saved = appState.isSaved(title);
    final hasAnimeDownloads =
        appState.mediaDownloadConfig
            ?.forCategory(MediaDownloadCategory.anime)
            .isNotEmpty ??
        false;
    final format = prettyFormat(title.format);
    final featuredAiring = title.nextAiring;
    final scheduleLabel = featuredAiring == null
        ? title.startDate == null
              ? 'Release date not announced'
              : '${_shortDate(title.startDate!)} · premiere'
        : '${_shortDate(featuredAiring.airingAt)} · episode ${featuredAiring.episode}';

    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(title.id),
      tween: Tween(begin: .985, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MusicoPalette.paper,
          border: Border.all(color: MusicoPalette.line),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: MusicoPalette.ink.withValues(alpha: .025),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              PosterArtwork(
                imageUrl: title.imageUrl,
                title: title.title,
                width: 62,
                height: 86,
                rounded: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 86),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          const Spacer(),
                          if (title.seasonYear != null)
                            Text(
                              '${title.seasonYear}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        title.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(height: 1.35, fontSize: 11),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(child: SplitFlapLabel(value: scheduleLabel)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              if (hasAnimeDownloads)
                IconButton(
                  tooltip: 'Download ${title.title} episodes',
                  onPressed: () => showConfiguredDownloadsDialog(
                    context,
                    appState: appState,
                    category: MediaDownloadCategory.anime,
                    initialQuery: title.title,
                  ),
                  icon: const Icon(
                    Icons.download_rounded,
                    color: MusicoPalette.forest,
                    size: 18,
                  ),
                ),
              Tooltip(
                message: saved
                    ? 'Remove from your watchlist'
                    : 'Add to your watchlist',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (saved) {
                      await appState.removeFromWatchlist(title);
                    } else {
                      await appState.addToWatchlist(title);
                    }
                    if (!context.mounted) return;
                    showMusicoToast(
                      context,
                      message: saved
                          ? 'Removed ${title.title} from your watchlist.'
                          : 'Saved ${title.title} to your watchlist.',
                    );
                  },
                  icon: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_add_outlined,
                    size: 19,
                    color: saved
                        ? MusicoPalette.terracotta
                        : MusicoPalette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReleases extends StatelessWidget {
  const _EmptyReleases({
    required this.appState,
    required this.loading,
    required this.hasError,
    required this.error,
    required this.isSearch,
    required this.isUpcoming,
  });

  final AppState appState;
  final bool loading;
  final bool hasError;
  final String? error;
  final bool isSearch;
  final bool isUpcoming;

  @override
  Widget build(BuildContext context) {
    final title = loading
        ? 'Checking the release calendar…'
        : hasError
        ? 'The calendar couldn’t load.'
        : isSearch
        ? 'No series or films found.'
        : isUpcoming
        ? 'New announcements will appear here.'
        : 'A quiet day in anime.';
    final subtitle = loading
        ? 'AniList is checking its latest anime episode and premiere data.'
        : error ??
              (isUpcoming
                  ? 'Refresh this season’s movie and series premieres when they’re announced.'
                  : 'Try another day, or search for the series you want to follow.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: MusicoPalette.paper,
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.wb_sunny_outlined,
              size: 20,
              color: MusicoPalette.terracotta,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(height: 1.5),
                ),
                if (hasError && !loading) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => appState.refreshAnime(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleFinePrint extends StatelessWidget {
  const _ScheduleFinePrint({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: MusicoPalette.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Schedule from AniList · Airing times use your device time zone. Published times can change. ${appState.hasNetworkConnection ? '' : 'No network — showing the last saved calendar.'}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 11, height: 1.5),
          ),
        ),
        if (!appState.notificationsEnabled)
          TextButton(
            onPressed: appState.requestAiringNotifications,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Enable alerts', style: TextStyle(fontSize: 11)),
          ),
      ],
    );
  }
}

String _weekday(DateTime date) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[date.weekday - 1];
}

String _weekdayFull(DateTime date) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[date.weekday - 1];
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

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
