import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musico/services/youtube_search_service.dart';

void main() {
  test('reports when the build has no YouTube API key', () async {
    final client = http.Client();
    addTearDown(client.close);
    final service = YouTubeSearchService(client, isWindows: false);

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

  test('parses yt-dlp results and discards non-video search entries', () {
    final results = parseYtDlpSearchResults(
      jsonEncode({
        'entries': [
          {'id': 'UCXR00_5QcEleXwXloTNTv5A', 'title': 'A channel result'},
          {
            'id': 'xrP1fGAEwTw',
            'title': 'Yabesh Thapa - Kamal Phool',
            'channel': 'Yabesh Thapa',
            'duration': 191,
            'thumbnail': 'https://i.ytimg.com/vi/xrP1fGAEwTw/hqdefault.jpg',
          },
          {'id': 'abcdefghijk', 'title': 'Live session', 'is_live': true},
        ],
      }),
    );

    expect(results, hasLength(2));
    expect(results.first.title, 'Yabesh Thapa - Kamal Phool');
    expect(results.first.channel, 'Yabesh Thapa');
    expect(results.first.duration, const Duration(seconds: 191));
    expect(results.first.thumbnailUrl, contains('xrP1fGAEwTw'));
    expect(results.last.isLive, isTrue);
  });
}
