import 'package:material_ui/material_ui.dart';

import '../models/media_download.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'musico_widgets.dart';

Future<void> showConfiguredDownloadsDialog(
  BuildContext context, {
  required AppState appState,
  required MediaDownloadCategory category,
  String initialQuery = '',
}) async {
  await appState.reloadMediaDownloadConfig();
  if (!context.mounted) return;
  return showDialog<void>(
    context: context,
    builder: (context) => ConfiguredDownloadsDialog(
      appState: appState,
      category: category,
      initialQuery: initialQuery,
    ),
  );
}

class ConfiguredDownloadsDialog extends StatefulWidget {
  const ConfiguredDownloadsDialog({
    required this.appState,
    required this.category,
    this.initialQuery = '',
    super.key,
  });

  final AppState appState;
  final MediaDownloadCategory category;
  final String initialQuery;

  @override
  State<ConfiguredDownloadsDialog> createState() =>
      _ConfiguredDownloadsDialogState();
}

class _ConfiguredDownloadsDialogState extends State<ConfiguredDownloadsDialog> {
  late final _queryController = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.category) {
    MediaDownloadCategory.music => 'Download music',
    MediaDownloadCategory.video => 'Download videos',
    MediaDownloadCategory.anime => 'Download anime episodes',
  };

  Future<void> _download(MediaDownloadLink item) async {
    final downloaded = await widget.appState.downloadConfiguredMedia(item);
    if (!mounted) return;
    showMusicoToast(
      context,
      message: downloaded
          ? 'Saved ${item.title} on this device.'
          : widget.appState.configuredDownloadErrorMessage ??
                'The download could not be completed.',
      isError: !downloaded,
      icon: downloaded ? Icons.download_done_rounded : Icons.error_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .84,
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
                      _title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close downloads',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  IconButton(
                    tooltip: 'Reload download links',
                    onPressed: widget.appState.reloadMediaDownloadConfig,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Filter configured downloads',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 13),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.appState,
                  builder: (context, _) {
                    final query = _queryController.text.trim().toLowerCase();
                    final all =
                        widget.appState.mediaDownloadConfig?.forCategory(
                          widget.category,
                        ) ??
                        const <MediaDownloadLink>[];
                    final filtered = all
                        .where(
                          (item) =>
                              query.isEmpty ||
                              '${item.title} ${item.artist ?? ''} ${item.attribution ?? ''}'
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .toList();
                    if (filtered.isEmpty) {
                      return _DownloadEmptyState(
                        hasConfiguredLinks: all.isNotEmpty,
                        configError: widget.appState.mediaDownloadErrorMessage,
                        category: widget.category,
                      );
                    }
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _DownloadLinkTile(
                        item: filtered[index],
                        appState: widget.appState,
                        onDownload: () => _download(filtered[index]),
                      ),
                    );
                  },
                ),
              ),
              if (widget.appState.mediaDownloadErrorMessage
                  case final configError?) ...[
                const SizedBox(height: 8),
                Text(
                  configError,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: MusicoPalette.error),
                ),
                Text(
                  'Fix or import the JSON in Settings, then reload links.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (widget.appState.configuredDownloadErrorMessage
                  case final error?) ...[
                const SizedBox(height: 9),
                Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: MusicoPalette.error),
                ),
              ],
              const SizedBox(height: 9),
              Text(
                'Only direct media files are accepted. Rights labels are your declaration; Musico does not verify copyright ownership.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadLinkTile extends StatelessWidget {
  const _DownloadLinkTile({
    required this.item,
    required this.appState,
    required this.onDownload,
  });

  final MediaDownloadLink item;
  final AppState appState;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final saved = appState.isConfiguredDownloadSaved(item);
    final downloading = appState.downloadingConfiguredIds.contains(
      item.progressKey,
    );
    final progress = appState.configuredDownloadProgress[item.progressKey];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [?item.artist, item.rights.label].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: saved || downloading ? null : onDownload,
                icon: downloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        saved ? Icons.check_rounded : Icons.download_rounded,
                        size: 16,
                      ),
                label: Text(
                  downloading
                      ? 'Downloading'
                      : saved
                      ? 'Saved'
                      : 'Download',
                ),
              ),
            ],
          ),
          if (item.attribution case final attribution?) ...[
            const SizedBox(height: 3),
            Text(
              attribution,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
    );
  }
}

class _DownloadEmptyState extends StatelessWidget {
  const _DownloadEmptyState({
    required this.hasConfiguredLinks,
    required this.configError,
    required this.category,
  });

  final bool hasConfiguredLinks;
  final String? configError;
  final MediaDownloadCategory category;

  @override
  Widget build(BuildContext context) {
    final categoryName = switch (category) {
      MediaDownloadCategory.music => 'music',
      MediaDownloadCategory.video => 'videos',
      MediaDownloadCategory.anime => 'anime episodes',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasConfiguredLinks
                  ? Icons.search_off_rounded
                  : Icons.download_for_offline_outlined,
              color: MusicoPalette.muted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              configError != null
                  ? 'Download links could not be loaded'
                  : hasConfiguredLinks
                  ? 'No matching downloads'
                  : 'No $categoryName links yet',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              configError != null
                  ? 'Check media_downloads.json in Settings and reload the links.'
                  : hasConfiguredLinks
                  ? 'Try another title or edit media_downloads.json in Settings.'
                  : 'Add direct file URLs to media_downloads.json in Settings.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
