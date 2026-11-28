import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// One selectable streaming source in [ProviderPicker].
class ProviderChoice {
  const ProviderChoice({
    required this.id,
    required this.name,
    this.description = '',
    this.isExtension = false,
  });

  final String id;
  final String name;
  final String description;
  final bool isExtension;
}

/// Compact source selector used by the anime, TV and movie tabs.
///
/// Shows the active source and lets the user switch to another installed
/// provider without leaving the screen.
class ProviderPicker extends StatelessWidget {
  const ProviderPicker({
    required this.providers,
    required this.selectedId,
    required this.onSelected,
    this.tooltip = 'Streaming source',
    this.compact = false,
    super.key,
  });

  final List<ProviderChoice> providers;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final String tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selected = providers.where((p) => p.id == selectedId).firstOrNull;
    final label = selected?.name ?? (providers.isEmpty ? 'No source' : providers.first.name);
    if (providers.length <= 1) {
      return Tooltip(
        message: providers.isEmpty
            ? 'No streaming source is installed'
            : '${label} is the only installed source',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MusicoPalette.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: tooltip,
      color: MusicoPalette.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: MusicoPalette.glassStrong),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final provider in providers)
          PopupMenuItem<String>(
            value: provider.id,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: provider.id == selectedId
                      ? const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: MusicoPalette.forest,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      provider.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (provider.description.isNotEmpty)
                      Text(
                        provider.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: MusicoPalette.muted,
                          fontSize: 11,
                        ),
                      ),
                    if (provider.isExtension)
                      Text(
                        'Extension',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: MusicoPalette.forestLight,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: MusicoPalette.canvasAlt,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: MusicoPalette.glassStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.layers_outlined,
              size: 16,
              color: MusicoPalette.forest,
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MusicoPalette.softInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: MusicoPalette.muted,
            ),
          ],
        ),
      ),
    );
  }
}
