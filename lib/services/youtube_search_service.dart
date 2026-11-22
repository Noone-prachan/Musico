import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/youtube_media.dart';
import 'yt_dlp_executable_resolver.dart';

final class YouTubeSearchNotConfiguredException implements Exception {
  const YouTubeSearchNotConfiguredException();

  @override
  String toString() =>
      'YouTube search is not configured for this build. '
      'Set YOUTUBE_API_KEY when building Musico.';
}

/// Uses the bundled yt-dlp executable on Windows and InnerTube on other
/// platforms, returning normalized [YouTubeSearchResult]s.
class YouTubeSearchService {
  YouTubeSearchService(this._client, {bool? isWindows})
    : _isWindows = isWindows ?? Platform.isWindows;

  final http.Client _client;
  final bool _isWindows;

  static const _key = String.fromEnvironment('YOUTUBE_API_KEY');
  static const _endpoint = 'https://www.youtube.com/youtubei/v1/search';

  Future<List<YouTubeSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    if (_isWindows) return _searchWithYtDlp(trimmed);
    if (_key.isEmpty) {
      throw const YouTubeSearchNotConfiguredException();
    }

    return _searchWithInnerTube(trimmed);
  }

  Future<List<YouTubeSearchResult>> _searchWithInnerTube(String query) async {
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
            'query': query,
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
    return renderers
        .map(YouTubeSearchResult.tryParse)
        .whereType<YouTubeSearchResult>()
        .toList();
  }

  Future<List<YouTubeSearchResult>> _searchWithYtDlp(String query) async {
    final userProfile = Platform.environment['USERPROFILE'];
    final executable = findYtDlpExecutable(
      applicationDirectory: File(Platform.resolvedExecutable).parent.path,
      userProfile: userProfile,
    );
    if (executable == null) {
      throw const FormatException(
        'yt-dlp is missing. Reinstall Musico to restore its YouTube search files.',
      );
    }

    final process = await Process.start(executable, [
      '--flat-playlist',
      '--dump-single-json',
      '--skip-download',
      '--quiet',
      '--no-warnings',
      '--socket-timeout',
      '20',
      '--retries',
      '1',
      'ytsearch10:$query',
    ]);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
      await stdout;
      await stderr;
      throw TimeoutException(
        'YouTube search timed out. Check your connection and retry.',
      );
    }

    final output = await stdout;
    final errorOutput = (await stderr).trim();
    if (exitCode != 0) {
      final message = errorOutput.isEmpty
          ? 'yt-dlp could not search YouTube (exit $exitCode).'
          : errorOutput.split(RegExp(r'[\r\n]+')).last;
      throw HttpException(message);
    }
    return parseYtDlpSearchResults(output);
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

List<YouTubeSearchResult> parseYtDlpSearchResults(String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('yt-dlp returned invalid search results.');
  }
  final entries = decoded['entries'];
  if (entries is! List) return const [];

  final results = <YouTubeSearchResult>[];
  for (final entry in entries) {
    if (entry is! Map) continue;
    final videoId = entry['id'];
    final title = entry['title'];
    if (videoId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ||
        title is! String ||
        title.trim().isEmpty) {
      continue;
    }

    final channel = entry['channel'] ?? entry['uploader'];
    final duration = entry['duration'];
    final thumbnails = entry['thumbnails'];
    final lastThumbnail = thumbnails is List && thumbnails.isNotEmpty
        ? thumbnails.last
        : null;
    final thumbnail =
        entry['thumbnail'] ??
        (lastThumbnail is Map ? lastThumbnail['url'] : null);

    results.add(
      YouTubeSearchResult(
        videoId: videoId,
        title: title.trim(),
        channel: channel is String && channel.trim().isNotEmpty
            ? channel.trim()
            : 'YouTube',
        duration: duration is num && duration.isFinite && duration >= 0
            ? Duration(seconds: duration.round())
            : null,
        thumbnailUrl: thumbnail is String ? thumbnail : null,
        isLive:
            entry['is_live'] == true ||
            entry['live_status'] == 'is_live' ||
            duration == null,
      ),
    );
  }
  return results;
}
