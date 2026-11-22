import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/youtube_video_metadata.dart';

class YouTubeMetadataService {
  const YouTubeMetadataService(this._client);

  final http.Client _client;

  Future<YouTubeVideoMetadata> lookup(String input) async {
    final videoId = YouTubeVideoMetadata.parseVideoId(input);
    final videoUrl = Uri.https('www.youtube.com', '/watch', {'v': videoId});
    final response = await _client
        .get(
          Uri.https('www.youtube.com', '/oembed', {
            'url': videoUrl.toString(),
            'format': 'json',
          }),
          headers: const {'User-Agent': 'Musico/1.0'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException(
        'YouTube metadata lookup failed (${response.statusCode}).',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('YouTube returned invalid video metadata.');
    }
    return YouTubeVideoMetadata.fromOEmbed(videoId: videoId, json: json);
  }
}
