import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musico/models/youtube_video_metadata.dart';
import 'package:musico/services/youtube_metadata_service.dart';

void main() {
  group('YouTube metadata lookup', () {
    test('parses supported URL forms and a bare video ID', () {
      const id = 'a1B2c3D4e5F';
      expect(
        YouTubeVideoMetadata.parseVideoId(
          'https://www.youtube.com/watch?v=$id&t=30',
        ),
        id,
      );
      expect(
        YouTubeVideoMetadata.parseVideoId('https://youtu.be/$id?si=share'),
        id,
      );
      expect(
        YouTubeVideoMetadata.parseVideoId('https://youtube.com/shorts/$id'),
        id,
      );
      expect(YouTubeVideoMetadata.parseVideoId(id), id);
    });

    test('rejects non-YouTube links and malformed video IDs', () {
      for (final input in [
        'https://example.org/watch?v=a1B2c3D4e5F',
        'https://youtube.com/watch?v=short',
        'https://youtube.com/channel/a1B2c3D4e5F',
      ]) {
        expect(
          () => YouTubeVideoMetadata.parseVideoId(input),
          throwsFormatException,
          reason: input,
        );
      }
    });

    test('looks up title and channel through oEmbed only', () async {
      late Uri requestUri;
      final service = YouTubeMetadataService(
        MockClient((request) async {
          requestUri = request.url;
          return http.Response(
            '{"title":"Open song","author_name":"Artist","thumbnail_url":"https://i.ytimg.com/vi/a1B2c3D4e5F/hqdefault.jpg"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final metadata = await service.lookup('https://youtu.be/a1B2c3D4e5F');

      expect(requestUri.host, 'www.youtube.com');
      expect(requestUri.path, '/oembed');
      expect(requestUri.queryParameters['format'], 'json');
      expect(metadata.title, 'Open song');
      expect(metadata.authorName, 'Artist');
      expect(metadata.videoUrl, 'https://www.youtube.com/watch?v=a1B2c3D4e5F');
    });
  });
}
