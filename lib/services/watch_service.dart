import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/anime_stream.dart';
import '../models/watch_media.dart';
import 'tmdb_service.dart';
import 'watch_provider.dart';

class WatchService implements WatchProvider {
  WatchService({
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client();

  @override
  String get id => 'vixsrc';

  @override
  String get name => 'vixsrc';

  @override
  String get description => 'Movies and TV shows, multi-language audio';

  @override
  bool get isExtension => false;

  @override
  bool get supportsSeries => true;

  @override
  bool get supportsMovies => true;

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const String _imdbSuggest =
      'https://v3.sg.media-imdb.com/suggestion/x';
  static const String _tvmaze = 'https://api.tvmaze.com';
  static const String _provider = 'https://vixsrc.to';

  final http.Client _client;
  final Duration timeout;
  final TmdbService _tmdb = TmdbService();

  Future<List<WatchTitle>> search(String query, {required bool series}) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const [];
    try {
      final tmdbResults = await _tmdb.search(cleaned, series: series);
      if (tmdbResults.isNotEmpty) return tmdbResults;
    } on Object catch (error, stackTrace) {
      developer.log(
        'TMDB search failed; falling back to TVMaze/IMDb.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (series) {
      try {
        final body = await _get(
          '$_tvmaze/search/shows?q=${Uri.encodeQueryComponent(cleaned)}',
        );
        final titles = parseTvmazeSearch(body);
        if (titles.isNotEmpty) return titles;
      } on Object catch (error, stackTrace) {
        developer.log(
          'TVMaze search failed; falling back to IMDb.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    final encoded = Uri.encodeComponent(cleaned);
    final body = await _get('$_imdbSuggest/$encoded.json');
    return parseImdbSuggestions(body, series: series);
  }

  Future<List<WatchEpisode>> episodes(WatchTitle show) async {
    var id = show.imdbId;
    if (!RegExp(r'^tt\d+$').hasMatch(id) && show.tmdbId != null) {
      id = await _tmdb.tmdbToImdbId(show.tmdbId!, isMovie: false) ?? id;
    }
    if (!RegExp(r'^tt\d+$').hasMatch(id)) {
      try {
        final search = await _get(
          '$_tvmaze/singlesearch/shows?q=${Uri.encodeComponent(show.title)}',
        );
        final tvmazeId = _tvmazeId(search);
        if (tvmazeId == null) return const [];
        final body = await _get('$_tvmaze/shows/$tvmazeId/episodes');
        return parseTvmazeEpisodes(body);
      } on Object {
        return const [];
      }
    }
    try {
      final lookup = await _get('$_tvmaze/lookup/shows?imdb=$id');
      var tvmazeId = _tvmazeId(lookup);
      if (tvmazeId == null) {
        final search = await _get(
          '$_tvmaze/singlesearch/shows?q=${Uri.encodeComponent(show.title)}',
        );
        tvmazeId = _tvmazeId(search);
      }
      if (tvmazeId == null) return const [];
      final body = await _get('$_tvmaze/shows/$tvmazeId/episodes');
      return parseTvmazeEpisodes(body);
    } on Object {
      return const [];
    }
  }

  Future<List<WatchSeasonPremiere>> upcomingSeasonPremieres({
    DateTime? from,
  }) async {
    final firstDay = from ?? DateTime.now();
    final start = DateTime(firstDay.year, firstDay.month, firstDay.day);
    final schedules = await Future.wait([
      for (var offset = 0; offset < 7; offset++)
        _get(
          Uri.parse('$_tvmaze/schedule/web')
              .replace(
                queryParameters: {
                  'date': _scheduleDate(start.add(Duration(days: offset))),
                  'embed': 'show',
                },
              )
              .toString(),
        ),
    ]);
    return parseTvmazeSeasonPremieres(schedules);
  }

  Future<List<AnimeSeasonOption>> seasons(WatchTitle show) async {
    final list = await episodes(show);
    final grouped = <int, int>{};
    for (final episode in list) {
      grouped.update(episode.season, (value) => value + 1, ifAbsent: () => 1);
    }
    final seasons = grouped.keys.toList()..sort();
    return [
      for (final season in seasons)
        AnimeSeasonOption(
          title: 'Season $season',
          year: show.year,
          format: 'TV',
          coverUrl: show.posterUrl,
          episodeCount: grouped[season],
        ),
    ];
  }

  Future<AnimeStreamSource> resolveMovie(WatchTitle movie) async {
    var id = movie.imdbId;
    if (!id.startsWith('tt') && movie.tmdbId != null) {
      id = await _tmdb.tmdbToImdbId(movie.tmdbId!, isMovie: true) ?? id;
    }
    return _resolve('/api/movie/$id');
  }

  Future<AnimeStreamSource> resolveEpisode(
    WatchTitle show,
    WatchEpisode episode,
  ) async {
    if (episode.airdate != null && episode.airdate!.isNotEmpty) {
      final airDate = DateTime.tryParse(episode.airdate!);
      final now = DateTime.now();
      if (airDate != null && airDate.isAfter(now)) {
        final diff = airDate.difference(now);
        final countdown = diff.inDays > 0
            ? '${diff.inDays}d ${diff.inHours % 24}h'
            : diff.inHours > 0
            ? '${diff.inHours}h ${diff.inMinutes % 60}m'
            : '${diff.inMinutes.clamp(1, 59)}m';
        throw WatchException(
          'Episode ${episode.number} has not aired yet — airs in $countdown (${episode.airdate}).',
        );
      }
    }
    var id = show.imdbId;
    if (!id.startsWith('tt') && show.tmdbId != null) {
      id = await _tmdb.tmdbToImdbId(show.tmdbId!, isMovie: false) ?? id;
    }
    return _resolve(
      '/api/tv/$id/${episode.season}/${episode.number}',
    );
  }

  Future<AnimeStreamSource> _resolve(String apiPath) async {
    final body = await _get(
      '$_provider$apiPath?lang=en',
      referer: '$_provider/',
    );
    String? embedPath;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['src'] is String) {
        embedPath = (decoded['src'] as String).replaceAll(r'\/', '/');
      }
    } on FormatException {
      embedPath = body.trim();
    }
    if (embedPath == null || embedPath.isEmpty) {
      throw const WatchException(
        'No streaming service has this title right now. Try another result.',
      );
    }
    final embedUrl = embedPath.startsWith('http')
        ? embedPath
        : '$_provider$embedPath';
    final html = await _get(embedUrl, referer: '$_provider/');
    final playlist = parseVixsrcEmbed(html);
    if (playlist == null) {
      throw const WatchException(
        'This title has no playable stream right now. Try another result.',
      );
    }
    return AnimeStreamSource(url: playlist, referer: '$_provider/');
  }

  static String? parseVixsrcEmbed(String html) {
    final url = RegExp(r"url:\s*'([^']+)'").firstMatch(html)?.group(1);
    final token = RegExp(r"'token':\s*'([^']*)'").firstMatch(html)?.group(1);
    final expires = RegExp(r"'expires':\s*'([^']*)'")
        .firstMatch(html)
        ?.group(1);
    final asn = RegExp(r"'asn':\s*'([^']*)'").firstMatch(html)?.group(1) ?? '';
    if (url != null && token != null && expires != null) {
      return '$url?token=$token&expires=$expires&asn=$asn';
    }
    final normalized = html.replaceAll(r'\/', '/');
    final streamUrl = RegExp(r'"url":"(https://[^"]*/playlist/[^"]*)"')
        .firstMatch(normalized)
        ?.group(1);
    return streamUrl;
  }

  static List<WatchTitle> parseImdbSuggestions(
    String body, {
    required bool series,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];
    final items = decoded['d'];
    if (items is! List) return const [];
    final titles = <WatchTitle>[];
    final seen = <String>{};
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'];
      final label = item['l'];
      if (id is! String || label is! String) continue;
      if (!id.startsWith('tt')) continue;
      final kind = switch (item['qid']) {
        final String value when value.isNotEmpty => value,
        _ => switch (item['q']) {
          final String value when value.isNotEmpty =>
            value == 'feature' ? 'movie' : value,
          _ => '',
        },
      };
      final title = WatchTitle(imdbId: id, title: label, kind: kind);
      if (series ? !title.isSeries : !title.isMovie) continue;
      if (!seen.add(id)) continue;
      final image = item['i'];
      final poster = image is Map && image['imageUrl'] is String
          ? image['imageUrl'] as String
          : null;
      titles.add(
        WatchTitle(
          imdbId: id,
          title: label,
          year: item['y'] is int ? item['y'] as int : null,
          kind: kind,
          posterUrl: poster,
        ),
      );
    }
    return titles;
  }

  static List<WatchTitle> parseTvmazeSearch(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final titles = <WatchTitle>[];
    final seen = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final show = item['show'];
      if (show is! Map) continue;
      final name = show['name'];
      final externals = show['externals'];
      final imdbId = externals is Map ? externals['imdb'] : null;
      if (name is! String || name.trim().isEmpty) continue;
      if (imdbId is! String || !imdbId.startsWith('tt')) continue;
      if (!seen.add(imdbId)) continue;
      final premiered = show['premiered'];
      final image = show['image'];
      titles.add(
        WatchTitle(
          imdbId: imdbId,
          title: name.trim(),
          year: premiered is String && premiered.length >= 4
              ? int.tryParse(premiered.substring(0, 4))
              : null,
          kind: 'tvSeries',
          posterUrl: image is Map && image['medium'] is String
              ? image['medium'] as String
              : null,
        ),
      );
    }
    return titles;
  }

  static List<WatchEpisode> parseTvmazeEpisodes(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final episodes = <WatchEpisode>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final season = item['season'];
      final number = item['number'];
      if (season is! int || number is! int) continue;
      final name = item['name'];
      final airdate = item['airdate'];
      if (airdate is String && airdate.isNotEmpty) {
        final parsed = DateTime.tryParse(airdate);
        if (parsed != null && parsed.isAfter(DateTime.now())) continue;
      }
      episodes.add(
        WatchEpisode(
          season: season,
          number: number,
          name: name is String && name.trim().isNotEmpty ? name.trim() : null,
          airdate: airdate is String && airdate.isNotEmpty ? airdate : null,
        ),
      );
    }
    episodes.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
    });
    return episodes;
  }

  static List<WatchSeasonPremiere> parseTvmazeSeasonPremieres(
    Iterable<String> schedules,
  ) {
    final premieres = <String, WatchSeasonPremiere>{};
    for (final body in schedules) {
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        continue;
      }
      if (decoded is! List) continue;
      for (final item in decoded) {
        if (item is! Map) continue;
        final season = item['season'];
        final number = item['number'];
        final airdate = item['airdate'];
      if (airdate is String && airdate.isNotEmpty) {
        final parsed = DateTime.tryParse(airdate);
        if (parsed != null && parsed.isAfter(DateTime.now())) continue;
      }
        if (season is! int ||
            season < 2 ||
            number is! int ||
            number != 1 ||
            airdate is! String ||
            DateTime.tryParse(airdate) == null) {
          continue;
        }
        final embedded = item['_embedded'];
        final show = embedded is Map ? embedded['show'] : null;
        if (show is! Map) continue;
        final name = show['name'];
        final externals = show['externals'];
        final imdbId = externals is Map ? externals['imdb'] : null;
        if (name is! String ||
            name.trim().isEmpty ||
            imdbId is! String ||
            !RegExp(r'^tt\d+$').hasMatch(imdbId)) {
          continue;
        }
        final image = show['image'];
        final premiered = show['premiered'];
        final episodeName = item['name'];
        final premiere = WatchSeasonPremiere(
          show: WatchTitle(
            imdbId: imdbId,
            title: name.trim(),
            year: premiered is String && premiered.length >= 4
                ? int.tryParse(premiered.substring(0, 4))
                : null,
            kind: 'tvSeries',
            posterUrl: image is Map && image['medium'] is String
                ? image['medium'] as String
                : null,
          ),
          season: season,
          episode: WatchEpisode(
            season: season,
            number: number,
            name: episodeName is String ? episodeName : null,
            airdate: airdate,
          ),
        );
        premieres.putIfAbsent('$imdbId:$season', () => premiere);
      }
    }
    final sorted = premieres.values.toList()
      ..sort((first, second) {
        return first.episode.airdate!.compareTo(second.episode.airdate!);
      });
    return sorted;
  }

  static String _scheduleDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _tvmazeId(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['id'] is int)
        return (decoded['id'] as int).toString();
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is Map && first['id'] is int) {
          return (first['id'] as int).toString();
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<String> _get(String url, {String? referer}) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'application/json,text/html,*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': ?referer,
    };
    http.Response response;
    try {
      response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
    } on Object catch (error) {
      throw WatchException('The catalog could not be reached. ($error)');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WatchException(
        'The catalog answered with HTTP ${response.statusCode}. Try again.',
      );
    }
    return body;
  }

  void dispose() {
    _tmdb.dispose();
    _client.close();
  }
}
