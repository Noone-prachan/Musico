import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/anime_stream.dart';
import 'anime_provider.dart';

class AnimeStreamService implements AnimeProvider {
  @override
  String get id => 'hianime';

  @override
  String get name => 'HiAnime';

  @override
  String get description => 'Sub and English dub, multiple mirrors';

  @override
  bool get isExtension => false;

  @override
  List<String> get supportedLanguages => const ['ja', 'en'];
  AnimeStreamService({
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client();

  static const String baseUrl = 'https://hianime.fm';

  static const List<String> mirrors = [
    'https://hianime.fm',
    'https://hianime.at',
  ];
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const String _streamServerName = 'ZokoAnime';
  static const String _embedKey = 'otaku-embed-v1';

  final http.Client _client;
  final Duration timeout;
  String? _activeHost;

  Future<String> _host() async {
    final cached = _activeHost;
    if (cached != null) return cached;
    for (final host in mirrors) {
      try {
        final html = await _get('$host/', accept: 'text/html');
        if (html.toLowerCase().contains('hianime')) {
          _activeHost = host;
          return host;
        }
      } on Object {
        continue;
      }
    }
    return baseUrl;
  }

  @override
  Future<List<AnimeSearchResult>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return const [];
    final host = await _host();
    final keyword = Uri.encodeQueryComponent(cleaned).replaceAll('%20', '+');
    final html = await _get(
      '$host/search?keyword=$keyword',
      accept: 'text/html',
    );
    return parseSearchHtml(html);
  }

  @override
  Future<List<AnimeEpisode>> episodes(AnimeSearchResult show) async {
    final numericId = show.numericId;
    if (!RegExp(r'^\d+$').hasMatch(numericId)) {
      throw const AnimeStreamException('That show id is not valid.');
    }
    final host = await _host();
    final body = await _get(
      '$host/api/theme/episode/list/$numericId',
      referer: '$host/',
      accept: 'application/json',
    );
    final parsed = parseEpisodeList(body, show.slug);
    if (parsed.isEmpty) {
      throw const AnimeStreamException(
        'No episodes are available for this title yet.',
      );
    }
    return parsed;
  }

  @override
  Future<AnimeStreamSource> resolveStream(
    AnimeEpisode episode, {
    String mode = 'sub',
  }) async {
    final host = await _host();
    final servers = await _get(
      '$host/api/theme/episode/servers?episodeId=${episode.id}',
      referer: '$host/',
      accept: 'application/json',
    );
    final hashes = serverHashes(servers, mode);
    if (hashes.isEmpty) {
      throw AnimeStreamException(
        mode == 'dub'
            ? 'No English dub stream is available for episode ${episode.number}. '
                  'Switch to Sub, or pick another episode.'
            : 'No streaming service returned a playable stream for episode '
                  '${episode.number}. Try another episode.',
      );
    }

    AnimeStreamException? lastError;
    for (final hash in hashes) {
      try {
        return await _resolveHash(hash);
      } on AnimeStreamException catch (error) {
        lastError = error;
      }
    }
    throw lastError ??
        const AnimeStreamException(
          'This episode has no playable stream right now. Try another episode.',
        );
  }

  static List<String> parseAvailableModes(String body) {
    final html = unwrapApiHtml(body);
    final modes = <String>[];
    for (final chunk in html.split('server-item').skip(1)) {
      final type = _attribute(chunk, 'data-type')?.trim().toLowerCase();
      if (type != null && type.isNotEmpty && !modes.contains(type)) {
        modes.add(type);
      }
    }
    return modes;
  }

  @override
  Future<List<String>> availableModes(AnimeEpisode episode) async {
    final host = await _host();
    final servers = await _get(
      '$host/api/theme/episode/servers?episodeId=${episode.id}',
      referer: '$host/',
      accept: 'application/json',
    );
    return parseAvailableModes(servers);
  }

  static List<String> serverHashes(String body, String mode) {
    final html = unwrapApiHtml(body);
    final preferred = <String>[];
    final others = <String>[];
    final seen = <String>{};
    for (final chunk in html.split('server-item').skip(1)) {
      if (_attribute(chunk, 'data-type') != mode) continue;
      final hash = _attribute(chunk, 'data-hash');
      if (hash == null || hash.isEmpty || !seen.add(hash)) continue;
      if (_attribute(chunk, 'data-server-name') == _streamServerName) {
        preferred.add(hash);
      } else {
        others.add(hash);
      }
    }
    return [...preferred, ...others];
  }

  Future<AnimeStreamSource> _resolveHash(String hash) async {
    final embedUrl = _decodeBase64Text(hash);
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(embedUrl)) {
      throw const AnimeStreamException('The stream host returned a bad link.');
    }
    final origin = RegExp(
      r'^(https?://[^/]+)',
      caseSensitive: false,
    ).firstMatch(embedUrl)?.group(1);
    final referer = '${origin ?? baseUrl}/';

    final embedHtml = await _get(embedUrl, referer: referer);
    final blob = RegExp(r'window\.__P="([^"]*)"')
        .firstMatch(embedHtml)
        ?.group(1);
    if (blob == null) {
      throw const AnimeStreamException(
        'The stream host did not return a playable episode.',
      );
    }

    final configText = deobfuscateEmbed(blob);
    final resolved = parseEmbedConfig(configText);
    if (resolved.playlistUrl == null) {
      throw const AnimeStreamException(
        'This episode has no playable stream right now. Try another server or episode.',
      );
    }

    final malId = RegExp(r'/mal/(\d+)/').firstMatch(embedUrl)?.group(1);

    return AnimeStreamSource(
      url: resolved.playlistUrl!,
      referer: referer,
      subtitleUrl: resolved.subtitleUrl,
      malId: malId == null ? null : int.tryParse(malId),
    );
  }

  Future<List<AnimeSeasonOption>> relatedSeasons(String title) async {
    final query = r'''query ($search: String) {
          Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
            title { romaji english }
            relations {
              edges {
                relationType
                node {
                  type
                  format
                  episodes
                  seasonYear
                  title { romaji english }
                  coverImage { medium }
                }
              }
            }
          }
        }''';
    try {
      final response = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': userAgent,
            },
            body: jsonEncode({
              'query': query,
              'variables': {'search': title},
            }),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      ) as Map<String, dynamic>;
      return parseAniListSeasons(decoded);
    } on Object {
      return const [];
    }
  }

  Future<String> _get(String url, {String? referer, String? accept}) async {
    final uri = Uri.parse(url);
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': accept ?? '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Referer': ?referer,
    };
    http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(timeout);
    } on Object catch (error) {
      throw AnimeStreamException(
        'The anime catalog could not be reached. Check your connection and try again. ($error)',
      );
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (body.contains('Just a moment')) {
      throw const AnimeStreamException(
        'The anime catalog is temporarily blocking requests. Try again in a minute.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnimeStreamException(
        'The anime catalog answered with HTTP ${response.statusCode}. Try again.',
      );
    }
    return body;
  }

  static List<AnimeSearchResult> parseSearchHtml(String html) {
    final main = html.split('id="main-sidebar"').first;
    final results = <AnimeSearchResult>[];
    final seen = <String>{};
    final blocks = main.split('class="flw-item').skip(1);
    for (final block in blocks) {
      final heading = RegExp(r'<h3 class="film-name">([\s\S]*?)</h3>')
          .firstMatch(block)
          ?.group(1);
      if (heading == null) continue;
      final anchor = RegExp(r'<a\s+([^>]*)>').firstMatch(heading)?.group(1);
      if (anchor == null) continue;
      final href = _attribute(anchor, 'href');
      final title = _attribute(anchor, 'title');
      if (href == null || title == null) continue;
      final slug = _slugFromHref(href);
      if (slug == null || !seen.add(slug)) continue;
      final japaneseTitle = _attribute(anchor, 'data-jname');
      results.add(
        AnimeSearchResult(
          slug: slug,
          title: decodeEntities(title),
          japaneseTitle: japaneseTitle == null
              ? null
              : decodeEntities(japaneseTitle),
          posterUrl: RegExp(r'<img[^>]*?src="([^"]+)"')
              .firstMatch(block)
              ?.group(1),
          type: RegExp(r'<span class="fdi-item">([^<]+)</span>')
              .firstMatch(block)
              ?.group(1)
              ?.trim(),
          duration: RegExp(
            r'<span class="fdi-item fdi-duration">([^<]+)</span>',
          ).firstMatch(block)?.group(1)?.trim(),
          episodeCount: int.tryParse(
            RegExp(r'tick-eps">(\d+)<').firstMatch(block)?.group(1) ?? '',
          ),
        ),
      );
    }
    return results;
  }

  static List<AnimeEpisode> parseEpisodeList(String body, String slug) {
    final html = unwrapApiHtml(body);
    final episodes = <AnimeEpisode>[];
    final seen = <String>{};
    for (final chunk in html.split('ep-item').skip(1)) {
      final number = _attribute(chunk, 'data-number');
      final id = _attribute(chunk, 'data-id');
      if (number == null || id == null) continue;
      if (!RegExp(r'^\d+$').hasMatch(id)) continue;
      if (!chunk.contains('$slug?ep=')) continue;
      if (!seen.add(id)) continue;
      final parsedNumber = int.tryParse(number.trim());
      if (parsedNumber == null) continue;
      final title = RegExp(
        r'<div class="ssli-detail">[\s\S]*?<p[^>]*>([^<]*)</p>',
      ).firstMatch(chunk)?.group(1)?.trim();
      episodes.add(
        AnimeEpisode(
          id: id,
          number: parsedNumber,
          title: title == null || title.isEmpty ? null : decodeEntities(title),
          filler:
              chunk.contains('ssl-item-filler') ||
              chunk.contains('tick-filler'),
        ),
      );
    }
    episodes.sort((a, b) => a.number.compareTo(b.number));
    return episodes;
  }

  static String? parseServerHash(String body, String mode) {
    final html = unwrapApiHtml(body);
    for (final chunk in html.split('server-item').skip(1)) {
      if (_attribute(chunk, 'data-server-name') != _streamServerName) continue;
      if (_attribute(chunk, 'data-type') != mode) continue;
      final hash = _attribute(chunk, 'data-hash');
      if (hash != null && hash.isNotEmpty) return hash;
    }
    return null;
  }

  static String? parseAnyServerHash(String body, String mode) {
    final html = unwrapApiHtml(body);
    for (final chunk in html.split('server-item').skip(1)) {
      if (_attribute(chunk, 'data-type') != mode) continue;
      final hash = _attribute(chunk, 'data-hash');
      if (hash != null && hash.isNotEmpty) return hash;
    }
    return null;
  }

  static ({String? playlistUrl, String? subtitleUrl}) parseEmbedConfig(
    String configText,
  ) {
    var text = configText.replaceAll(r'\/', '/');
    String? playlist;
    String? subtitle;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (decoded != null) {
      playlist = _findPlaylist(decoded);
      subtitle = _findDefaultSubtitle(decoded);
    }
    playlist ??= RegExp(r'"src"\s*:\s*"([^"]*\.m3u8[^"]*)"')
        .firstMatch(text)
        ?.group(1);
    subtitle ??= RegExp(r'"src"\s*:\s*"([^"]*\.vtt[^"]*)"')
        .firstMatch(text)
        ?.group(1);
    return (
      playlistUrl: playlist?.replaceAll(r'\/', '/'),
      subtitleUrl: subtitle?.replaceAll(r'\/', '/'),
    );
  }

  static String deobfuscateEmbed(String blob) {
    final bytes = base64.decode(_padBase64(blob));
    final key = utf8.encode(_embedKey);
    final output = Uint8List(bytes.length);
    for (var index = 0; index < bytes.length; index++) {
      output[index] = bytes[index] ^ key[index % key.length];
    }
    return utf8.decode(output, allowMalformed: true);
  }

  static String unwrapApiHtml(String body) {
    var text = body;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded != null) {
      final parts = <String>[];
      void walk(Object? value) {
        if (value is String) {
          parts.add(value);
        } else if (value is List) {
          for (final item in value) {
            walk(item);
          }
        } else if (value is Map) {
          for (final item in value.values) {
            walk(item);
          }
        }
      }

      walk(decoded);
      if (parts.isNotEmpty) text = parts.join('\n');
    }
    return text
        .replaceAll(r'\"', '"')
        .replaceAll(r'\/', '/')
        .replaceAll(r'\', '');
  }

  static List<AnimeSeasonOption> parseAniListSeasons(
    Map<String, dynamic> payload,
  ) {
    final media = (payload['data'] as Map?)?['Media'] as Map?;
    final edges = (media?['relations'] as Map?)?['edges'];
    if (edges is! List) return const [];
    const wantedRelations = {
      'SEQUEL',
      'PREQUEL',
      'SEASON',
      'PARENT',
      'SIDE_STORY',
    };
    const wantedFormats = {'TV', 'TV_SHORT', 'ONA'};
    final seasons = <AnimeSeasonOption>[];
    final seen = <String>{};
    for (final edge in edges) {
      if (edge is! Map) continue;
      final relation = edge['relationType'];
      if (!wantedRelations.contains(relation)) continue;
      final node = edge['node'];
      if (node is! Map) continue;
      if (node['type'] != 'ANIME') continue;
      if (!wantedFormats.contains(node['format'])) continue;
      final titles = node['title'];
      final title = switch (titles) {
        final Map map =>
          (map['english'] as String?)?.trim().isNotEmpty == true
              ? map['english'] as String
              : (map['romaji'] as String?),
        _ => null,
      };
      if (title == null || title.trim().isEmpty) continue;
      if (!seen.add(title.toLowerCase())) continue;
      seasons.add(
        AnimeSeasonOption(
          title: title.trim(),
          year: node['seasonYear'] is int ? node['seasonYear'] as int : null,
          format: node['format'] as String?,
          coverUrl: (node['coverImage'] as Map?)?['medium'] as String?,
          episodeCount: node['episodes'] is int
              ? node['episodes'] as int
              : null,
        ),
      );
    }
    seasons.sort((a, b) {
      final yearA = a.year ?? 9999;
      final yearB = b.year ?? 9999;
      final byYear = yearA.compareTo(yearB);
      return byYear != 0 ? byYear : a.title.compareTo(b.title);
    });
    return seasons;
  }

  static String? _findPlaylist(Object? value) {
    if (value is String) {
      return RegExp(r'\.m3u8', caseSensitive: false).hasMatch(value)
          ? value
          : null;
    }
    if (value is List) {
      for (final item in value) {
        final found = _findPlaylist(item);
        if (found != null) return found;
      }
      return null;
    }
    if (value is Map) {
      final source = value['src'];
      if (source is String &&
          RegExp(r'\.m3u8', caseSensitive: false).hasMatch(source)) {
        return source;
      }
      for (final item in value.values) {
        final found = _findPlaylist(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _findDefaultSubtitle(Object? value) {
    if (value is List) {
      for (final item in value) {
        if (item is Map && item['default'] == true && item['src'] is String) {
          return item['src'] as String;
        }
        final nested = _findDefaultSubtitle(item);
        if (nested != null) return nested;
      }
      return null;
    }
    if (value is Map) {
      for (final item in value.values) {
        final found = _findDefaultSubtitle(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _attribute(String text, String name) {
    final match = RegExp('$name="([^"]*)"').firstMatch(text);
    return match?.group(1);
  }

  static String? _slugFromHref(String href) {
    final withoutQuery = href.split('?').first;
    final segments = withoutQuery
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    final slug = segments.last;
    return slug.isEmpty ? null : slug;
  }

  static String _decodeBase64Text(String value) {
    try {
      return utf8.decode(base64.decode(_padBase64(value))).trim();
    } on FormatException {
      throw const AnimeStreamException(
        'The stream host returned a link Musico could not read.',
      );
    }
  }

  static String _padBase64(String value) {
    final normalized = value.replaceAll(RegExp(r'\s'), '');
    final remainder = normalized.length % 4;
    if (remainder == 0) return normalized;
    return normalized.padRight(normalized.length + (4 - remainder), '=');
  }

  static String decodeEntities(String value) {
    return value
        .replaceAll(RegExp(r'&#0?39;'), "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  void dispose() => _client.close();
}
