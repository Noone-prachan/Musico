import 'dart:convert';

/// Declarative streaming extension.
///
/// Extensions are plain JSON files, so anyone can add a source without
/// shipping a new build. A manifest maps a provider's HTTP API onto Musico's
/// search / episode / stream steps:
///
/// ```json
/// {
///   "schema": 1,
///   "id": "example-movies",
///   "name": "Example Movies",
///   "kinds": ["movie", "tv"],
///   "headers": { "Referer": "https://example.com/" },
///   "search": {
///     "url": "https://example.com/api/search?q={query}",
///     "items": "results",
///     "id": "id",
///     "title": "title",
///     "poster": "poster",
///     "subtitle": "year"
///   },
///   "episodes": {
///     "url": "https://example.com/api/title/{id}",
///     "items": "episodes",
///     "id": "id",
///     "title": "name",
///     "season": "season",
///     "number": "episode"
///   },
///   "stream": {
///     "url": "https://example.com/api/stream/{id}",
///     "urlField": "url",
///     "referer": "https://example.com/",
///     "subtitleField": "subtitle"
///   }
/// }
/// ```
///
/// Every mapping value is a dot path (`data.items`, `sources.0.url`) into the
/// JSON response. URLs may contain `{query}`, `{id}`, `{season}`, `{number}`
/// and `{mode}` placeholders.
class StreamExtensionManifest {
  const StreamExtensionManifest({
    required this.id,
    required this.name,
    required this.kinds,
    this.schema = 1,
    this.description = '',
    this.version = '',
    this.headers = const {},
    this.search,
    this.episodes,
    this.seasons,
    this.stream,
    this.modes = const ['sub'],
    this.userAgent,
  });

  final int schema;
  final String id;
  final String name;
  final String description;
  final String version;

  /// `anime`, `tv` and/or `movie`.
  final Set<String> kinds;

  /// Extra headers sent with every request from this extension.
  final Map<String, String> headers;

  final StreamSearchSpec? search;
  final StreamEpisodeSpec? episodes;
  final StreamSeasonSpec? seasons;
  final StreamSourceSpec? stream;

  /// Anime audio modes, e.g. `["sub", "dub"]`.
  final List<String> modes;

  final String? userAgent;

  bool get isAnime => kinds.contains('anime');
  bool get isSeries => kinds.contains('tv');
  bool get isMovie => kinds.contains('movie');

  /// Normalised provider id (`a.b` style) so folder names cannot collide.
  static String normaliseId(String raw) {
    final cleaned = raw.trim().toLowerCase();
    final slug = cleaned
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp('-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'extension' : slug;
  }

  static StreamExtensionManifest? tryParse(
    String source, {
    String? fallbackId,
    void Function(String message)? onIssue,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      onIssue?.call('Not valid JSON: ${error.message}');
      return null;
    }
    if (decoded is! Map) {
      onIssue?.call('The manifest must be a JSON object.');
      return null;
    }
    final name = _string(decoded['name']);
    if (name == null || name.isEmpty) {
      onIssue?.call('Missing "name".');
      return null;
    }
    final rawId = _string(decoded['id']) ?? fallbackId ?? name;
    final kinds = <String>{};
    final rawKinds = decoded['kinds'];
    if (rawKinds is List) {
      for (final kind in rawKinds) {
        final value = _string(kind)?.toLowerCase();
        if (value == null) continue;
        if (value == 'series' || value == 'shows' || value == 'tvshows') {
          kinds.add('tv');
        } else if (value == 'film' || value == 'films' || value == 'movies') {
          kinds.add('movie');
        } else if (value == 'anime') {
          kinds.add('anime');
        }
      }
    }
    if (kinds.isEmpty) {
      onIssue?.call('"kinds" must list at least one of anime, tv, movie.');
      return null;
    }

    final search = StreamSearchSpec.tryParse(decoded['search'], onIssue);
    if (search == null) {
      onIssue?.call('A "search" block with a "url" is required.');
      return null;
    }
    final stream = StreamSourceSpec.tryParse(decoded['stream'], onIssue);
    if (stream == null) {
      onIssue?.call('A "stream" block with a "url" is required.');
      return null;
    }

    final modes = <String>[];
    final rawModes = decoded['modes'];
    if (rawModes is List) {
      for (final mode in rawModes) {
        final value = _string(mode)?.toLowerCase();
        if (value != null && value.isNotEmpty && !modes.contains(value)) {
          modes.add(value);
        }
      }
    }

    return StreamExtensionManifest(
      schema: _int(decoded['schema']) ?? 1,
      id: normaliseId(rawId),
      name: name,
      description: _string(decoded['description']) ?? '',
      version: _string(decoded['version']) ?? '',
      kinds: kinds,
      headers: _headers(decoded['headers']),
      search: search,
      episodes: StreamEpisodeSpec.tryParse(decoded['episodes'], onIssue),
      seasons: StreamSeasonSpec.tryParse(decoded['seasons'], onIssue),
      stream: stream,
      modes: modes.isEmpty ? const ['sub'] : modes,
      userAgent: _string(decoded['userAgent']),
    );
  }

  static String? _string(Object? value) {
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Map<String, String> _headers(Object? value) {
    if (value is! Map) return const {};
    final headers = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final text = _string(entry.value);
      if (key.isEmpty || text == null) continue;
      headers[key] = text;
    }
    return headers;
  }
}

/// The `search` block of a manifest.
class StreamSearchSpec {
  const StreamSearchSpec({
    required this.url,
    this.items = '',
    this.id = 'id',
    this.title = 'title',
    this.poster,
    this.subtitle,
    this.kind,
    this.year,
  });

  final String url;
  final String items;
  final String id;
  final String title;
  final String? poster;
  final String? subtitle;

  /// Field holding the media type for TV/movie searches.
  final String? kind;
  final String? year;

  static StreamSearchSpec? tryParse(
    Object? value,
    void Function(String message)? onIssue,
  ) {
    if (value is! Map) return null;
    final url = StreamExtensionManifest._string(value['url']);
    if (url == null || url.isEmpty) return null;
    return StreamSearchSpec(
      url: url,
      items: StreamExtensionManifest._string(value['items']) ?? '',
      id: StreamExtensionManifest._string(value['id']) ?? 'id',
      title: StreamExtensionManifest._string(value['title']) ?? 'title',
      poster: StreamExtensionManifest._string(value['poster']),
      subtitle: StreamExtensionManifest._string(value['subtitle']),
      kind: StreamExtensionManifest._string(value['kind']),
      year: StreamExtensionManifest._string(value['year']),
    );
  }
}

/// The `episodes` block of a manifest.
class StreamEpisodeSpec {
  const StreamEpisodeSpec({
    required this.url,
    this.items = '',
    this.id = 'id',
    this.title,
    this.season,
    this.number,
  });

  final String url;
  final String items;
  final String id;
  final String? title;
  final String? season;
  final String? number;

  static StreamEpisodeSpec? tryParse(
    Object? value,
    void Function(String message)? onIssue,
  ) {
    if (value is! Map) return null;
    final url = StreamExtensionManifest._string(value['url']);
    if (url == null || url.isEmpty) return null;
    return StreamEpisodeSpec(
      url: url,
      items: StreamExtensionManifest._string(value['items']) ?? '',
      id: StreamExtensionManifest._string(value['id']) ?? 'id',
      title: StreamExtensionManifest._string(value['title']),
      season: StreamExtensionManifest._string(value['season']),
      number: StreamExtensionManifest._string(value['number']),
    );
  }
}

/// The optional `seasons` block of a manifest.
class StreamSeasonSpec {
  const StreamSeasonSpec({
    required this.url,
    this.items = '',
    this.title = 'name',
    this.number = 'number',
    this.episodeCount = 'episodeCount',
    this.cover,
  });

  final String url;
  final String items;
  final String title;
  final String number;
  final String episodeCount;
  final String? cover;

  static StreamSeasonSpec? tryParse(
    Object? value,
    void Function(String message)? onIssue,
  ) {
    if (value is! Map) return null;
    final url = StreamExtensionManifest._string(value['url']);
    if (url == null || url.isEmpty) return null;
    return StreamSeasonSpec(
      url: url,
      items: StreamExtensionManifest._string(value['items']) ?? '',
      title: StreamExtensionManifest._string(value['title']) ?? 'name',
      number: StreamExtensionManifest._string(value['number']) ?? 'number',
      episodeCount:
          StreamExtensionManifest._string(value['episodeCount']) ??
          'episodeCount',
      cover: StreamExtensionManifest._string(value['cover']),
    );
  }
}

/// The `stream` block of a manifest.
class StreamSourceSpec {
  const StreamSourceSpec({
    required this.url,
    this.urlField = 'url',
    this.referer,
    this.subtitleField,
    this.audioField,
  });

  final String url;

  /// Dot path to the playable URL inside the response.
  final String urlField;
  final String? referer;
  final String? subtitleField;
  final String? audioField;

  static StreamSourceSpec? tryParse(
    Object? value,
    void Function(String message)? onIssue,
  ) {
    if (value is! Map) return null;
    final url = StreamExtensionManifest._string(value['url']);
    if (url == null || url.isEmpty) return null;
    return StreamSourceSpec(
      url: url,
      urlField: StreamExtensionManifest._string(value['urlField']) ?? 'url',
      referer: StreamExtensionManifest._string(value['referer']),
      subtitleField: StreamExtensionManifest._string(value['subtitleField']),
      audioField: StreamExtensionManifest._string(value['audioField']),
    );
  }
}

/// Reads `a.b.0.c` style paths out of decoded JSON.
class JsonPath {
  const JsonPath._();

  static Object? read(Object? root, String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return root;
    Object? current = root;
    for (final part in trimmed.split('.')) {
      if (current == null) return null;
      if (current is List) {
        final index = int.tryParse(part);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  static String? text(Object? root, String? path) {
    if (path == null) return null;
    final value = read(root, path);
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static int? integer(Object? root, String? path) {
    if (path == null) return null;
    final value = read(root, path);
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final match = RegExp(r'\d{1,5}').firstMatch(value);
      return match == null ? null : int.tryParse(match.group(0)!);
    }
    return null;
  }

  static List<Object?> list(Object? root, String path) {
    final value = read(root, path);
    if (value is List) return value;
    if (value is Map) return [value];
    return const [];
  }
}
