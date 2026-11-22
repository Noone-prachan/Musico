import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/youtube_video_metadata.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

Future<void> showYouTubeMetadataDialog(
  BuildContext context, {
  required AppState appState,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _YouTubeMetadataDialog(appState: appState),
  );
}

class _YouTubeMetadataDialog extends StatefulWidget {
  const _YouTubeMetadataDialog({required this.appState});

  final AppState appState;

  @override
  State<_YouTubeMetadataDialog> createState() => _YouTubeMetadataDialogState();
}

class _YouTubeMetadataDialogState extends State<_YouTubeMetadataDialog> {
  final _urlController = TextEditingController();
  YouTubeVideoMetadata? _metadata;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _metadata = null;
    });
    try {
      final metadata = await widget.appState.lookupYouTubeMetadata(
        _urlController.text,
      );
      if (!mounted) return;
      setState(() => _metadata = metadata);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error) {
          FormatException() => error.message,
          HttpException() => error.message,
          _ => 'Could not reach YouTube. Check your connection and try again.',
        },
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Look up YouTube metadata',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close metadata lookup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paste a video URL to view its title and channel in Musico. This does not download the video or audio.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: MusicoPalette.muted, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _isLoading ? null : _lookup(),
                decoration: InputDecoration(
                  labelText: 'YouTube URL or video ID',
                  hintText: 'youtube.com/watch?v=…',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Look up metadata',
                    onPressed: _isLoading ? null : _lookup,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: MusicoPalette.error),
                ),
              ],
              if (_metadata case final metadata?) ...[
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MusicoPalette.canvasAlt,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: MusicoPalette.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Channel · ${metadata.authorName}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        metadata.videoUrl,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
