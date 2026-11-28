import 'package:material_ui/material_ui.dart';

import '../services/extension_loader.dart';
import '../services/streaming_catalog.dart';
import '../theme/app_theme.dart';

/// Manage streaming sources.
///
/// Lists the built-in providers, every extension found on disk and any file
/// that could not be loaded, with a shortcut to the extensions folder.
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  final StreamingCatalog _catalog = StreamingCatalog.instance;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_onCatalogChanged);
    if (!_catalog.isInitialized) {
      setState(() => _busy = true);
      _reload();
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    await _catalog.reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = 'Extensions reloaded.';
    });
  }

  Future<void> _openFolder() async {
    final opened = await _catalog.openExtensionsFolder();
    if (!mounted) return;
    if (!opened) {
      setState(() => _message = 'The extensions folder could not be opened.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = _catalog.animeProviders.length + _catalog.watchProviders.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming sources'),
        actions: [
          IconButton(
            tooltip: 'Open extensions folder',
            onPressed: _openFolder,
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: 'Reload extensions',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          Text(
            'Musico ships with built-in sources and loads extra ones from a '
            'folder. Every source can be picked per category from the Watch '
            'screens.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: MusicoPalette.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MusicoPalette.forest,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const _SectionLabel('Built in'),
          const SizedBox(height: 8),
          for (final provider in _catalog.animeProviders)
            if (!provider.isExtension)
              _ProviderTile(
                name: provider.name,
                description: provider.description,
                kinds: 'Anime',
                isExtension: false,
              ),
          for (final provider in _catalog.watchProviders)
            if (!provider.isExtension)
              _ProviderTile(
                name: provider.name,
                description: provider.description,
                kinds: [
                  if (provider.supportsSeries) 'TV',
                  if (provider.supportsMovies) 'Movies',
                ].join(' · '),
                isExtension: false,
              ),
          const SizedBox(height: 20),
          _SectionLabel('Extensions ($providers installed)'),
          const SizedBox(height: 8),
          if (_catalog.extensions.entries.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MusicoPalette.canvasAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MusicoPalette.glassStrong),
              ),
              child: Text(
                'No extension files found yet. Drop a .json manifest into the '
                'extensions folder and press reload. The example file shows '
                'the format.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            )
          else
            for (final entry in _catalog.extensions.entries)
              _ExtensionTile(entry: entry),
          const SizedBox(height: 20),
          const _SectionLabel('Extensions folder'),
          const SizedBox(height: 8),
          for (final directory in _catalog.extensionDirectories)
            SelectableText(
              directory,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'IBM Plex Mono'),
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            label: const Text('Open extensions folder'),
          ),
          const SizedBox(height: 18),
          Text(
            'Manifest format',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'A manifest maps a provider\'s HTTP API onto search, episodes and '
            'stream steps with dot paths, e.g. "items": "data.results" and '
            '"url": "https://host/api/search?q={query}". Supported placeholders: '
            '{query}, {id}, {season}, {number}, {mode}, {kind}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        letterSpacing: 0.2,
        color: MusicoPalette.softInk,
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.name,
    required this.description,
    required this.kinds,
    required this.isExtension,
  });

  final String name;
  final String description;
  final String kinds;
  final bool isExtension;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isExtension ? Icons.extension_outlined : Icons.layers_outlined,
          color: MusicoPalette.forest,
        ),
        title: Text(name),
        subtitle: Text(
          [kinds, if (description.isNotEmpty) description].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.check_circle_outline, size: 18),
      ),
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  const _ExtensionTile({required this.entry});

  final ExtensionEntry entry;

  @override
  Widget build(BuildContext context) {
    final manifest = entry.manifest;
    final loaded = manifest != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          loaded ? Icons.extension_rounded : Icons.error_outline_rounded,
          color: loaded ? MusicoPalette.forest : MusicoPalette.error,
        ),
        title: Text(loaded ? manifest.name : 'Could not load a manifest'),
        subtitle: Text(
          loaded
              ? [
                  [
                    if (manifest.isAnime) 'Anime',
                    if (manifest.isSeries) 'TV',
                    if (manifest.isMovie) 'Movies',
                  ].join(' · '),
                  if (manifest.description.isNotEmpty) manifest.description,
                ].join('\n')
              : (entry.error ?? 'Unknown problem'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: loaded && manifest.description.isNotEmpty,
      ),
    );
  }
}
