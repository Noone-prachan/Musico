import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/watch_media.dart';

/// TMDB API helper for searching movies/TV shows and converting between
/// TMDB numeric IDs and IMDb IDs.
class TmdbService {
  TmdbService({http.Client? client}) : _client = client ?? http.Client();

  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';
  static const String _bearer =
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJmM2U3YzdhYjI0YTUxYWUwM2JlODAwMDBjZjc5OTRiYiIsIm5iZiI6MTc5NTc5MTA2MC4yOTMsInN1YiI6IjZiMDk5OGQ0NGE1N2UzY2FkZDc1OGVlNyIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.CZua3kAAuYCVZW4GDRvUW-xI0Tj6y2zjB-coKHg-F9c';

  final http.Client _client;

  final Map<String, int?> _imdbToTmdbCache = {};
  final Map<String, String?> _tmdbToImdbCache = {};

  Map<String, String> get _headers => const {
    'Authorization': 'Bearer $_bearer',
    'Accept': 'application/json',
  };

  /// Searches TMDB for movies or TV shows and returns [WatchTitle]s with
  /// [WatchTitle.tmdbId] populated.
  Future<List<WatchTitle>> search(String query, {required bool series}) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const [];

    final endpoint = series ? 'search/tv' : 'search/movie';
    final uri = Uri.parse('$_baseUrl/$endpoint').replace(
      queryParameters: {
        'query': cleaned,
        'include_adult': 'false',
        'language': 'en-US',
        'page': '1',
      },
    );

    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw WatchException('TMDB search failed (HTTP ${response.statusCode}).');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    final titles = <WatchTitle>[];

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final tmdbId = item['id'] as int?;
      final name = (series ? item['name'] : item['title']) as String?;
      if (tmdbId == null || name == null || name.trim().isEmpty) continue;

      final dateStr =
          (series ? item['first_air_date'] : item['release_date']) as String?;
      final year = (dateStr != null && dateStr.length >= 4)
          ? int.tryParse(dateStr.substring(0, 4))
          : null;
      final posterPath = item['poster_path'] as String?;

      titles.add(
        WatchTitle(
          imdbId: 'tmdb:$tmdbId',
          tmdbId: tmdbId,
          title: name.trim(),
          year: year,
          kind: series ? 'tvSeries' : 'movie',
          posterUrl: posterPath != null ? '$_imageBase$posterPath' : null,
        ),
      );
    }
    return titles;
  }

  /// Converts an IMDb ID (e.g. `tt14452776`) to a TMDB numeric ID.
  Future<int?> imdbToTmdbId(String imdbId, {bool? isMovie}) async {
    if (!imdbId.startsWith('tt')) return null;
    if (_imdbToTmdbCache.containsKey(imdbId)) return _imdbToTmdbCache[imdbId];

    try {
      final uri = Uri.parse('$_baseUrl/find/$imdbId?external_source=imdb_id');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final movieResults = data['movie_results'] as List? ?? [];
      if ((isMovie ?? true) && movieResults.isNotEmpty) {
        final id = (movieResults.first as Map)['id'] as int?;
        _imdbToTmdbCache[imdbId] = id;
        return id;
      }

      final tvResults = data['tv_results'] as List? ?? [];
      if (!(isMovie ?? false) && tvResults.isNotEmpty) {
        final id = (tvResults.first as Map)['id'] as int?;
        _imdbToTmdbCache[imdbId] = id;
        return id;
      }

      _imdbToTmdbCache[imdbId] = null;
      return null;
    } on Object catch (error, stackTrace) {
      developer.log(
        'TMDB lookup failed for $imdbId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Fetches the IMDb ID (e.g. `tt14452776`) for a TMDB ID, used when
  /// falling back to vixsrc.to.
  Future<String?> tmdbToImdbId(int tmdbId, {required bool isMovie}) async {
    final key = '${isMovie ? 'm' : 'tv'}:$tmdbId';
    if (_tmdbToImdbCache.containsKey(key)) return _tmdbToImdbCache[key];

    try {
      final type = isMovie ? 'movie' : 'tv';
      final uri = Uri.parse('$_baseUrl/$type/$tmdbId/external_ids');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final imdbId = data['imdb_id'] as String?;
      _tmdbToImdbCache[key] = imdbId;
      return imdbId;
    } on Object catch (error, stackTrace) {
      developer.log(
        'TMDB external_ids failed for $key',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  void dispose() => _client.close();
}
