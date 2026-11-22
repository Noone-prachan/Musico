import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musico/services/youtube_search_service.dart';

void main() {
  test('reports when the build has no YouTube API key', () async {
    final client = http.Client();
    addTearDown(client.close);
    final service = YouTubeSearchService(client);

    await expectLater(
      service.search('a song'),
      throwsA(
        isA<YouTubeSearchNotConfiguredException>().having(
          (error) => error.toString(),
          'message',
          contains('YOUTUBE_API_KEY'),
        ),
      ),
    );
  });
}
