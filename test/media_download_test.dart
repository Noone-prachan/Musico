import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/media_download.dart';

void main() {
  group('direct media downloads', () {
    test('decodes supported direct files by category', () {
      final config = MediaDownloadConfig.decode('''
      {
        "schemaVersion": 1,
        "downloads": {
          "music": [{
            "id": "track-01",
            "title": "Night Drive",
            "artist": "Sample Artist",
            "url": "https://cdn.example.org/night-drive.mp3",
            "rights": "cc_by",
            "attribution": "Sample Artist",
            "licenseUrl": "https://creativecommons.org/licenses/by/4.0/"
          }],
          "video": [],
          "anime": [{
            "id": "episode-01",
            "title": "Open episode",
            "url": "https://cdn.example.org/episode-01.mp4",
            "rights": "public_domain"
          }]
        }
      }
      ''');

      expect(
        config.forCategory(MediaDownloadCategory.music).single.title,
        'Night Drive',
      );
      expect(
        config.forCategory(MediaDownloadCategory.anime).single.category,
        MediaDownloadCategory.anime,
      );
      expect(
        MediaDownloadConfig.decode(config.encode())
            .forCategory(MediaDownloadCategory.music)
            .single
            .rights,
        MediaRights.ccBy,
      );
    });

    test('rejects web pages, insecure URLs, and streaming services', () {
      for (final url in [
        'http://cdn.example.org/song.mp3',
        'https://example.org/search?q=song',
        'https://youtube.com/watch?v=example.mp4',
        'https://example.org/stream.m3u8',
      ]) {
        expect(
          () => MediaDownloadLink.fromJson(
            {
              'id': 'test',
              'title': 'Test file',
              'url': url,
              'rights': 'permission',
            },
            category: MediaDownloadCategory.music,
            location: 'music[1]',
          ),
          throwsFormatException,
          reason: url,
        );
      }
    });

    test('requires attribution for Creative Commons attribution licenses', () {
      expect(
        () => MediaDownloadLink.fromJson(
          {
            'id': 'track',
            'title': 'Track',
            'url': 'https://cdn.example.org/track.mp3',
            'rights': 'cc_by',
          },
          category: MediaDownloadCategory.music,
          location: 'music[1]',
        ),
        throwsFormatException,
      );
    });
  });
}
