import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime_stream.dart';
import '../models/watch_media.dart';
import 'anime_provider.dart';
import 'extension_manifest.dart';
import 'watch_provider.dart';

/// Shared HTTP + mapping engine behind declarative extensions.
///
/// [JsonAnimeProvider] and [JsonWatchProvider] both delegate here, so a single
/// manifest can feed the anime tab and the TV/movie tabs.
class JsonExtensionEngine {
  JsonExtensionEngine(
    this.manifest, {
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client();

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final StreamExtensionManifest manifest;
  final Duration timeout;
  final http.Client _client;

  Map<String, String> get _headers => {
    'User-Agent': manifest.userAgent ?? defaultUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    ...manifest.headers,
  };

  String buildUrl(
    String template, {
    String? query,
    String? id,
    int? season,
    int? number,
    String? mode,
    String? kind,
  }) {
    return template
        .replaceAll('{query}', Uri.encodeQueryComponent(query ?? ''))
        .replaceAll('{id}', Uri.encodeComponent(id ?? ''))
        .replaceAll('{season}', '${season ?? 1}')
        .replaceAll('{number}', '${number ?? 1}')
        .replaceAll('{mode}', mode ?? 'sub')
        .replaceAll('{kind}', kind ?? 'movie');
  }

  Future<Object?> getJson(String url) async {
    final response = await _client
        .get(Uri.parse(url), headers: _headers)
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StreamExtensionException(
        '${manifest.name} answered with HTTP ${response.statusCode}.',
      );
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }

  /// Search results mapped to anime results.
  Future<List<AnimeSearchResult>> searchAnime(String query) async {
    final spec = manifest.search!;
    final url = buildUrl(spec.url, query: query);
    final payload = await getJson(url);
    final items = JsonPath.list(payload, spec.items);
    final results = <AnimeSearchResult>[];
    final seen = <String>{};
    for (final item in items) {
      final id = JsonPath.text(item, spec.id);
      final title = JsonPath.text(item, spec.title);
      if (id == null || title == null || !seen.add(id)) continue;
      final subtitle = JsonPath.text(item, spec.subtitle);
      results.add(
        AnimeSearchResult(
          slug: id,
          title: title,
          posterUrl: JsonPath.text(item, spec.poster),
          type: subtitle,
        ),
      );
    }
    return results;
  }

  /// Search results mapped to TV / movie titles.
  Future<List<WatchTitle>> searchWatch(
    String query, {
    required bool series,
  }) async {
    final spec = manifest.search!;
    final url = buildUrl(
      spec.url,
      query: query,
      kind: series ? 'tv' : 'movie',
    );
    final payload = await getJson(url);
    final items = JsonPath.list(payload, spec.items);
    final titles = <WatchTitle>[];
    final seen = <String>{};
    for (final item in items) {
      final id = JsonPath.text(item, spec.id);
      final title = JsonPath.text(item, spec.title);
      if (id == null || title == null || !seen.add(id)) continue;
      final rawKind = JsonPath.text(item, spec.kind)?.toLowerCase();
      var kind = series ? 'tvSeries' : 'movie';
      if (!series && rawKind != null && _looksLikeSeries(rawKind)) {
        // Keep movie results movie-shaped; the tab filters by kind.
        kind = 'tvSeries';
      }
      titles.add(
        WatchTitle(
          imdbId: id,
          title: title,
          year: JsonPath.integer(item, spec.year),
          kind: kind,
          posterUrl: JsonPath.text(item, spec.poster),
        ),
      );
    }
    return titles;
  }

  Future<List<AnimeEpisode>> episodesAnime(AnimeSearchResult show) async {
    final spec = manifest.episodes;
    if (spec == null) {
      throw StreamExtensionException(
        '${manifest.name} does not list episodes.',
      );
    }
    final url = buildUrl(spec.url, id: show.slug);
    final payload = await getJson(url);
    final items = JsonPath.list(payload, spec.items);
    final episodes = <AnimeEpisode>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final id = JsonPath.text(item, spec.id) ?? '${show.slug}-${index + 1}';
      final number = JsonPath.integer(item, spec.number) ?? index + 1;
      episodes.add(
        AnimeEpisode(
          id: id,
          number: number,
          title: JsonPath.text(item, spec.title),
        ),
      );
    }
    episodes.sort((a, b) => a.number.compareTo(b.number));
    return episodes;
  }

  Future<List<WatchEpisode>> episodesWatch(WatchTitle show) async {
    final payload = await _episodePayload(show);
    if (payload == null) return const [];
    return payload;
  }

  Future<List<WatchEpisode>?> _episodePayload(WatchTitle show) async {
    final spec = manifest.episodes;
    if (spec == null) return const [];
    final url = buildUrl(spec.url, id: show.imdbId, kind: 'tv');
    final payload = await getJson(url);
    final items = JsonPath.list(payload, spec.items);
    final episodes = <WatchEpisode>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final season = JsonPath.integer(item, spec.season) ?? 1;
      final number = JsonPath.integer(item, spec.number) ?? index + 1;
      episodes.add(
        WatchEpisode(
          season: season,
          number: number,
          name: JsonPath.text(item, spec.title),
        ),
      );
    }
    episodes.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
    });
    return episodes;
  }

  Future<List<AnimeSeasonOption>> seasonsWatch(WatchTitle show) async {
    final spec = manifest.seasons;
    if (spec != null) {
      final url = buildUrl(spec.url, id: show.imdbId, kind: 'tv');
      final payload = await getJson(url);
      final items = JsonPath.list(payload, spec.items);
      final seasons = <AnimeSeasonOption>[];
      for (final item in items) {
        final number = JsonPath.integer(item, spec.number);
        final title = JsonPath.text(item, spec.title);
        if (number == null || title == null) continue;
        seasons.add(
          AnimeSeasonOption(
            title: title,
            year: show.year,
            format: 'TV',
            coverUrl: JsonPath.text(item, spec.cover) ?? show.posterUrl,
            episodeCount: JsonPath.integer(item, spec.episodeCount),
          ),
        );
      }
      if (seasons.isNotEmpty) return seasons;
    }
    final episodes = await episodesWatch(show);
    final grouped = <int, int>{};
    for (final episode in episodes) {
      grouped.update(episode.season, (value) => value + 1, ifAbsent: () => 1);
    }
    final keys = grouped.keys.toList()..sort();
    return [
      for (final season in keys)
        AnimeSeasonOption(
          title: 'Season $season',
          year: show.year,
          format: 'TV',
          coverUrl: show.posterUrl,
          episodeCount: grouped[season],
        ),
    ];
  }

  Future<AnimeStreamSource> resolve(
    String itemId, {
    int? season,
    int? number,
    String mode = 'sub',
    String kind = 'movie',
  }) async {
    final spec = manifest.stream!;
    final url = buildUrl(
      spec.url,
      id: itemId,
      season: season,
      number: number,
      mode: mode,
      kind: kind,
    );
    final payload = await getJson(url);
    final Object? rawUrl = payload is String
        ? (payload.trim().startsWith('http') ? payload.trim() : null)
        : JsonPath.read(payload, spec.urlField);
    final playable = rawUrl is String ? rawUrl.trim() : null;
    if (playable == null || playable.isEmpty) {
      throw StreamExtensionException(
        '${manifest.name} did not return a playable stream.',
      );
    }
    final resolvedUrl = playable.startsWith('http')
        ? playable
        : Uri.parse(url).resolve(playable).toString();
    final referer =
        spec.referer ?? manifest.headers['Referer'] ?? manifest.headers['referer'] ?? '';
    return AnimeStreamSource(
      url: resolvedUrl,
      referer: referer,
      subtitleUrl: spec.subtitleField == null || payload is String
          ? null
          : JsonPath.text(payload, spec.subtitleField),
    );
  }

  static bool _looksLikeSeries(String kind) {
    return kind.contains('series') ||
        kind.contains('tv') ||
        kind.contains('show');
  }

  void dispose() => _client.close();
}

/// Anime view of a declarative extension.
class JsonAnimeProvider implements AnimeProvider {
  JsonAnimeProvider(this.manifest, {JsonExtensionEngine? engine})
    : _engine = engine ?? JsonExtensionEngine(manifest);

  final StreamExtensionManifest manifest;
  final JsonExtensionEngine _engine;

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get description =>
      manifest.description.isEmpty ? 'Extension provider' : manifest.description;

  @override
  bool get isExtension => true;

  @override
  List<String> get supportedLanguages => const ['ja', 'en'];

  @override
  Future<List<AnimeSearchResult>> search(String query) =>
      _engine.searchAnime(query);

  @override
  Future<List<AnimeEpisode>> episodes(AnimeSearchResult show) =>
      _engine.episodesAnime(show);

  @override
  Future<List<AnimeSeasonOption>> relatedSeasons(String title) async =>
      const [];

  @override
  Future<List<String>> availableModes(AnimeEpisode episode) async =>
      manifest.modes;

  @override
  Future<AnimeStreamSource> resolveStream(
    AnimeEpisode episode, {
    String mode = 'sub',
  }) => _engine.resolve(
    episode.id,
    number: episode.number,
    mode: mode,
    kind: 'anime',
  );

  @override
  void dispose() => _engine.dispose();
}

/// TV / movie view of a declarative extension.
class JsonWatchProvider implements WatchProvider {
  JsonWatchProvider(this.manifest, {JsonExtensionEngine? engine})
    : _engine = engine ?? JsonExtensionEngine(manifest);

  final StreamExtensionManifest manifest;
  final JsonExtensionEngine _engine;

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get description =>
      manifest.description.isEmpty ? 'Extension provider' : manifest.description;

  @override
  bool get isExtension => true;

  @override
  bool get supportsSeries => manifest.isSeries;

  @override
  bool get supportsMovies => manifest.isMovie;

  @override
  Future<List<WatchTitle>> search(String query, {required bool series}) =>
      _engine.searchWatch(query, series: series);

  @override
  Future<List<WatchEpisode>> episodes(WatchTitle show) =>
      _engine.episodesWatch(show);

  @override
  Future<List<AnimeSeasonOption>> seasons(WatchTitle show) =>
      _engine.seasonsWatch(show);

  @override
  Future<AnimeStreamSource> resolveEpisode(
    WatchTitle show,
    WatchEpisode episode,
  ) => _engine.resolve(
    show.imdbId,
    season: episode.season,
    number: episode.number,
    kind: 'tv',
  );

  @override
  Future<AnimeStreamSource> resolveMovie(WatchTitle movie) =>
      _engine.resolve(movie.imdbId, kind: 'movie');

  @override
  void dispose() => _engine.dispose();
}

class StreamExtensionException implements Exception {
  const StreamExtensionException(this.message);

  final String message;

  @override
  String toString() => message;
}
