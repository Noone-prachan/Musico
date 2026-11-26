import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musico/services/youtube_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports when the build has no YouTube API key', () async {
    final client = http.Client();
    addTearDown(client.close);
    final service = YouTubeSearchService(
      client,
      isWindows: false,
      isAndroid: false,
    );

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

  test('uses the Android yt-dlp bridge without an API key', () async {
    final client = http.Client();
    addTearDown(client.close);
    const channel = MethodChannel('musico/youtube_search');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'search');
      expect(call.arguments, {'query': 'Yabesh Thapa'});
      return jsonEncode({
        'entries': [
          {
            'id': 'xrP1fGAEwTw',
            'title': 'Yabesh Thapa - Kamal Phool',
            'channel': 'Yabesh Thapa',
            'duration': 191,
          },
        ],
      });
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final results = await YouTubeSearchService(
      client,
      isWindows: false,
      isAndroid: true,
    ).search(' Yabesh Thapa ');

    expect(results, hasLength(1));
    expect(results.single.videoId, 'xrP1fGAEwTw');
    expect(results.single.title, 'Yabesh Thapa - Kamal Phool');
  });

  test('surfaces errors from the Android yt-dlp bridge', () async {
    final client = http.Client();
    addTearDown(client.close);
    const channel = MethodChannel('musico/youtube_search');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'youtube_search_failed',
        message: 'YouTube could not be reached.',
      ),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await expectLater(
      YouTubeSearchService(
        client,
        isWindows: false,
        isAndroid: true,
      ).search('a song'),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          'YouTube could not be reached.',
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
