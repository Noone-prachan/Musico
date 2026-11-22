import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/youtube_media.dart';

/// Searches YouTube with the public InnerTube endpoint and returns plain
/// `videoRenderer` results as [YouTubeSearchResult]s. This is independent of
/// `youtube_explode_dart`'s search client, whose parsing breaks on live or
/// unusual results.
class YouTubeSearchService {
  const YouTubeSearchService(this._client);

  final http.Client _client;

  static const _key = String.fromEnvironment('YOUTUBE_API_KEY');
  static const _endpoint = 'https://www.youtube.com/youtubei/v1/search';

  Future<List<YouTubeSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (_key.isEmpty) {
      throw StateError(
        'YouTube search is not configured for this build. '
        'Set YOUTUBE_API_KEY when building Musico.',
      );
    }

    final response = await _client
        .post(
          Uri.parse('$_endpoint?key=$_key&prettyPrint=false'),
          headers: const {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/126.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
            'Origin': 'https://www.youtube.com',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20240726.00.00',
                'hl': 'en',
                'gl': 'US',
              },
            },
            'query': trimmed,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw HttpException('YouTube search failed (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('YouTube returned an invalid search result.');
    }

    final renderers = <Map<String, dynamic>>[];
    _collectVideoRenderers(decoded, renderers);

    final results = <YouTubeSearchResult>[];
    for (final renderer in renderers) {
      final result = YouTubeSearchResult.tryParse(renderer);
      if (result != null) results.add(result);
    }
    return results;
  }

  void _collectVideoRenderers(Object? node, List<Map<String, dynamic>> out) {
    if (node is Map) {
      final renderer = node['videoRenderer'];
      if (renderer is Map) {
        out.add(renderer.cast<String, dynamic>());
      }
      for (final value in node.values) {
        _collectVideoRenderers(value, out);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectVideoRenderers(value, out);
      }
    }
  }
}
