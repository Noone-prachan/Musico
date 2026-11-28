import 'dart:convert';
import 'dart:io';

import 'anime_provider.dart';
import 'extension_manifest.dart';
import 'json_stream_provider.dart';
import 'watch_provider.dart';

/// One extension file that was found, with either its provider or why it was
/// rejected.
class ExtensionEntry {
  const ExtensionEntry({
    required this.file,
    this.manifest,
    this.error,
  });

  final String file;
  final StreamExtensionManifest? manifest;
  final String? error;

  bool get isLoaded => manifest != null;
}

/// Everything the loader found on disk.
class LoadedExtensions {
  const LoadedExtensions({
    required this.animeProviders,
    required this.watchProviders,
    required this.entries,
    required this.directories,
  });

  final List<AnimeProvider> animeProviders;
  final List<WatchProvider> watchProviders;
  final List<ExtensionEntry> entries;
  final List<String> directories;

  static const empty = LoadedExtensions(
    animeProviders: [],
    watchProviders: [],
    entries: [],
    directories: [],
  );
}

/// Reads declarative extensions from disk.
///
/// Two places are scanned:
///  * `extensions/` next to the executable (ships with the app),
///  * `%APPDATA%\Musico\extensions` (the folder users drop files into).
///
/// A file is either `<folder>/<name>.json` or `<folder>/musico-extension.json`.
class ExtensionLoader {
  ExtensionLoader({this.maxDepth = 2});

  final int maxDepth;

  Future<List<String>> directories() async {
    final roots = <String>[];
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.trim().isNotEmpty) {
        final dir = Directory(
          [appData, 'Musico', 'extensions'].join(Platform.pathSeparator),
        );
        await dir.create(recursive: true);
        roots.add(dir.path);
      }
    } on Object {
      // A locked profile can reject the write; the app still works without it.
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final dir = Directory(
        [exeDir, 'extensions'].join(Platform.pathSeparator),
      );
      if (await dir.exists()) roots.add(dir.path);
    } on Object {
      // Ignore unreadable install folders.
    }
    return roots;
  }

  Future<LoadedExtensions> load() async {
    final dirs = await directories();
    final anime = <AnimeProvider>[];
    final watch = <WatchProvider>[];
    final entries = <ExtensionEntry>[];
    final seenIds = <String>{};

    for (final root in dirs) {
      final files = await _collectFiles(Directory(root));
      for (final file in files) {
        final entry = await _loadFile(file, seenIds);
        entries.add(entry);
        final manifest = entry.manifest;
        if (manifest == null) continue;
        if (manifest.isAnime) {
          anime.add(JsonAnimeProvider(manifest));
        }
        if (manifest.isSeries || manifest.isMovie) {
          watch.add(JsonWatchProvider(manifest));
        }
      }
    }

    return LoadedExtensions(
      animeProviders: anime,
      watchProviders: watch,
      entries: entries,
      directories: dirs,
    );
  }

  Future<List<File>> _collectFiles(Directory root) async {
    final files = <File>[];
    if (!await root.exists()) return files;
    try {
      await for (final entity in root.list(
        recursive: maxDepth > 1,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.toLowerCase().endsWith('.json')) continue;
        if (name == 'example-musico-extension.json') continue;
        files.add(entity);
      }
    } on Object {
      // Unreadable folder: skip it.
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<ExtensionEntry> _loadFile(File file, Set<String> seenIds) async {
    String? issue;
    try {
      final source = await file.readAsString();
      final folder = file.parent.path.split(Platform.pathSeparator).last;
      final manifest = StreamExtensionManifest.tryParse(
        source,
        fallbackId: folder,
        onIssue: (message) => issue ??= message,
      );
      if (manifest == null) {
        return ExtensionEntry(
          file: file.path,
          error: issue ?? 'The manifest could not be read.',
        );
      }
      if (!seenIds.add(manifest.id)) {
        return ExtensionEntry(
          file: file.path,
          error: 'Another extension already uses the id "${manifest.id}".',
        );
      }
      return ExtensionEntry(file: file.path, manifest: manifest);
    } on Object catch (error) {
      return ExtensionEntry(
        file: file.path,
        error: 'The file could not be read: $error',
      );
    }
  }

  /// Writes the commented example manifest to the user extensions folder the
  /// first time the app runs, so the format is discoverable.
  static Future<File?> ensureExampleFile() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.trim().isEmpty) return null;
      final dir = Directory(
        [appData, 'Musico', 'extensions'].join(Platform.pathSeparator),
      );
      await dir.create(recursive: true);
      final file = File(
        [dir.path, 'example-musico-extension.json'].join(
          Platform.pathSeparator,
        ),
      );
      if (await file.exists()) return file;
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exampleManifest),
      );
      return file;
    } on Object {
      return null;
    }
  }

  /// Disabled by default: the loader skips this name, so a user who just wants
  /// to read the format does not end up with a broken provider.
  static Map<String, Object?> get exampleManifest => {
    'schema': 1,
    'id': 'example-source',
    'name': 'Example source (disabled)',
    'description':
        'Rename this file, fill in a real API, then reload extensions.',
    'version': '1.0.0',
    'kinds': ['movie', 'tv'],
    'headers': {
      'Referer': 'https://example.com/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    },
    'search': {
      'url': 'https://example.com/api/search?q={query}',
      'items': 'results',
      'id': 'id',
      'title': 'name',
      'poster': 'poster',
      'year': 'year',
      'kind': 'type',
    },
    'episodes': {
      'url': 'https://example.com/api/title/{id}',
      'items': 'episodes',
      'id': 'id',
      'title': 'name',
      'season': 'season',
      'number': 'episode',
    },
    'seasons': {
      'url': 'https://example.com/api/title/{id}/seasons',
      'items': 'seasons',
      'title': 'name',
      'number': 'number',
      'episodeCount': 'episodeCount',
    },
    'stream': {
      'url': 'https://example.com/api/stream/{id}?season={season}&episode={number}&mode={mode}',
      'urlField': 'url',
      'referer': 'https://example.com/',
      'subtitleField': 'subtitle',
    },
    'modes': ['sub', 'dub'],
  };
}
