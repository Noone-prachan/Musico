import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/youtube_media.dart';

void main() {
  group('YouTubeSearchResult.tryParse', () {
    test('parses a normal video renderer', () {
      final result = YouTubeSearchResult.tryParse({
        'videoId': 'dQw4w9WgXcQ',
        'title': {
          'runs': [
            {'text': 'Rick Astley - '},
            {'text': 'Never Gonna Give You Up'},
          ],
        },
        'ownerText': {
          'runs': [
            {'text': 'Rick Astley'},
          ],
        },
        'lengthText': {'simpleText': '3:34'},
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'},
            {'url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg'},
          ],
        },
      });

      expect(result, isNotNull);
      expect(result!.videoId, 'dQw4w9WgXcQ');
      expect(result.title, 'Rick Astley - Never Gonna Give You Up');
      expect(result.channel, 'Rick Astley');
      expect(result.duration, const Duration(minutes: 3, seconds: 34));
      expect(
        result.thumbnailUrl,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg',
      );
      expect(result.isLive, isFalse);
      expect(result.videoUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('parses hour-long durations', () {
      final result = YouTubeSearchResult.tryParse({
        'videoId': 'abcdefghijk',
        'title': {'simpleText': 'Long mix'},
        'ownerText': {'simpleText': 'Channel'},
        'lengthText': {'simpleText': '1:02:03'},
      });
      expect(
        result!.duration,
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
    });

    test('marks live streams without a duration as live', () {
      final result = YouTubeSearchResult.tryParse({
        'videoId': 'abcdefghijk',
        'title': {'simpleText': '24/7 radio'},
        'ownerText': {'simpleText': 'Channel'},
      });
      expect(result!.isLive, isTrue);
      expect(result.duration, isNull);
    });

    test('rejects entries without a valid video id', () {
      expect(
        YouTubeSearchResult.tryParse({
          'title': {'simpleText': 'No id'},
        }),
        isNull,
      );
      expect(
        YouTubeSearchResult.tryParse({
          'videoId': 'too-short',
          'title': {'simpleText': 'Bad id'},
        }),
        isNull,
      );
    });
  });

  group('YouTubeQuality', () {
    test('formats a human-readable size label', () {
      const quality = YouTubeQuality(
        label: '1080p',
        height: 1080,
        itag: 137,
        codec: 'avc1.640028',
        container: 'mp4',
        bitrateKbps: 4000,
        sizeBytes: 80 * 1024 * 1024,
      );
      expect(quality.sizeLabel, '80 MB');
    });
  });
}
