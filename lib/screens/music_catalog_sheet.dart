import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/music_track.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/search_autocomplete_field.dart';

Future<void> showMusicCatalog(BuildContext context, AppState appState) {
  final height = MediaQuery.sizeOf(context).height;
  if (!Platform.isAndroid) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: MusicoPalette.paper,
        constraints: BoxConstraints(maxWidth: 740, maxHeight: height * .88),
        child: SizedBox(
          width: 680,
          child: MusicCatalogSheet(appState: appState),
        ),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MusicoPalette.paper,
    showDragHandle: false,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * .88),
      child: MusicCatalogSheet(appState: appState),
    ),
  );
}

class MusicCatalogSheet extends StatefulWidget {
  const MusicCatalogSheet({required this.appState, super.key});

  final AppState appState;

  @override
  State<MusicCatalogSheet> createState() => _MusicCatalogSheetState();
}

class _MusicCatalogSheetState extends State<MusicCatalogSheet> {
  late final _queryController = TextEditingController(
    text: widget.appState.commonsQuery,
  );
  final _focusNode = FocusNode();

  AppState get appState => widget.appState;

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    _focusNode.unfocus();
    await appState.searchCommons(_queryController.text);
  }

  @override
  Widget build(BuildContext context) {
    final resultHeight = math
        .min(MediaQuery.sizeOf(context).height * .31, 320.0)
        .toDouble();
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Platform.isAndroid) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 37,
                height: 4,
                decoration: BoxDecoration(
                  color: MusicoPalette.line,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 16, 15, 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Find music to keep',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 28),
                  ),
                ),
                IconButton(
                  tooltip: 'Close free music catalogue',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 4, 23, 13),
            child: Text(
              'Public-domain and Creative Commons audio from Wikimedia Commons. Author, source and license stay with each track.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: MusicoPalette.muted, height: 1.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 23),
            child: SearchAutocompleteField(
              controller: _queryController,
              focusNode: _focusNode,
              suggestions: [
                ...AppState.musicSuggestions,
                ...appState.commonsResults.map((result) => result.title),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
              onSelected: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Try a genre, instrument, or artist',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Search free music',
                  onPressed: appState.isSearchingMusic ? null : _search,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 10, 23, 0),
            child: _MusicSuggestions(
              query: _queryController.text,
              onSelect: (suggestion) {
                _queryController.text = suggestion;
                _search();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 12, 23, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: MusicoPalette.moss,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only public domain, CC0, CC BY and CC BY-SA licenses.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 11, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          if (appState.musicErrorMessage != null &&
              appState.commonsSearchError == null &&
              appState.commonsResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(23, 0, 23, 7),
              child: Text(
                appState.musicErrorMessage!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: MusicoPalette.error, height: 1.5),
              ),
            ),
          if (appState.isSearchingMusic)
            const SizedBox(height: 115, child: _CatalogLoading())
          else if (appState.commonsResults.isEmpty &&
              appState.hasSearchedCommons &&
              appState.commonsSearchError != null)
            SizedBox(
              height: 165,
              child: _CatalogError(
                message: appState.commonsSearchError!,
                onRetry: _search,
              ),
            )
          else if (appState.commonsResults.isEmpty)
            _CatalogEmpty(
              hasSearched: appState.hasSearchedCommons,
              message: appState.commonsEmptyMessage,
            )
          else
            SizedBox(
              height: resultHeight,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                itemCount: appState.commonsResults.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _MusicResultTile(
                  item: appState.commonsResults[index],
                  appState: appState,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MusicSuggestions extends StatelessWidget {
  const _MusicSuggestions({required this.query, required this.onSelect});

  final String query;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final matches = AppState.musicSuggestions
        .where(
          (suggestion) => normalized.isEmpty || suggestion.contains(normalized),
        )
        .toList();
    final suggestions = matches.take(5).toList();
    if (suggestions.isEmpty) {
      return Text(
        'No suggestions. Press Enter to search this exact phrase.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          normalized.isEmpty ? 'A few places to start' : 'Suggested searches',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () => onSelect(suggestion),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ],
    );
  }
}

class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({required this.hasSearched, this.message});

  final bool hasSearched;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: Row(
        children: [
          Icon(
            hasSearched ? Icons.search_off_rounded : Icons.graphic_eq_rounded,
            size: 22,
            color: MusicoPalette.forestLight,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSearched
                      ? 'No matching licensed audio'
                      : 'Start with a sound you like',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  message ?? 'Try another genre, instrument, or artist. We only show audio with supported open licenses.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 13),
            Expanded(child: Text('Looking for open-licensed audio…')),
          ],
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: MusicoPalette.error,
              size: 28,
            ),
            const SizedBox(height: 11),
            Text(
              'The music catalogue couldn’t load.',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicResultTile extends StatelessWidget {
  const _MusicResultTile({required this.item, required this.appState});

  final MusicResult item;
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final downloaded = appState.hasTrack(item);
    final isDownloading = appState.downloadingIds.contains(item.pageId);
    final progress = appState.downloadProgress[item.pageId] ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MusicoPalette.white,
        border: Border.all(color: MusicoPalette.line),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: MusicoPalette.olive.withValues(alpha: .64),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 19,
              color: MusicoPalette.forestLight,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.artist} · ${_formatSize(item.size)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  item.license,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MusicoPalette.moss,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isDownloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    color: MusicoPalette.moss,
                    backgroundColor: MusicoPalette.canvasAlt,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            height: 38,
            child: downloaded
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: MusicoPalette.success,
                    size: 20,
                  )
                : OutlinedButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () => appState.downloadMusic(item),
                    icon: isDownloading
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 1.7),
                          )
                        : const Icon(Icons.download_rounded, size: 15),
                    label: Text(isDownloading ? 'Saving' : 'Download'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
