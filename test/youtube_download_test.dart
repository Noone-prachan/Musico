import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/youtube_download.dart';
import 'package:musico/models/youtube_media.dart';
import 'package:musico/services/yt_dlp_executable_resolver.dart';

void main() {
  group('findYtDlpExecutable', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'musico-ytdlp-resolver',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('prefers the bundled executable beside the app', () async {
      final bundled = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}yt-dlp.exe',
      );
      await bundled.create(recursive: true);
      final pythonExecutable = File(
        '${temporaryDirectory.path}\\AppData\\Roaming\\Python\\Python314'
        '\\Scripts\\yt-dlp.exe',
      );
      await pythonExecutable.create(recursive: true);

      expect(
        findYtDlpExecutable(
          applicationDirectory: temporaryDirectory.path,
          userProfile: temporaryDirectory.path,
        ),
        bundled.path,
      );
    });

    test('keeps the existing Python install fallback', () async {
      final fallback = File(
        '${temporaryDirectory.path}\\AppData\\Roaming\\Python\\Python314'
        '\\Scripts\\yt-dlp.exe',
      );
      await fallback.create(recursive: true);

      expect(
        findYtDlpExecutable(
          applicationDirectory: temporaryDirectory.path,
          userProfile: temporaryDirectory.path,
        ),
        fallback.path,
      );
    });
  });

  group('sanitizeYouTubeFileName', () {
    test('removes characters that are invalid in file names', () {
      expect(
        sanitizeYouTubeFileName('My/Song: "Live"? *01*'),
        'My_Song_ _Live__ _01_',
      );
    });

    test('trims whitespace, dots and empty input', () {
      expect(sanitizeYouTubeFileName('  Night Drive...  '), 'Night Drive');
      expect(sanitizeYouTubeFileName('   '), 'YouTube download');
    });

    test('avoids Windows reserved names', () {
      expect(sanitizeYouTubeFileName('CON'), '_CON');
    });
  });

  group('YouTubeDownloadMetadata', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'musico-youtube-metadata',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test(
      'writes the requested name and the original metadata to a sidecar',
      () async {
        final media = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}My song.mp3',
        );
        await media.writeAsString('audio');

        const metadata = YouTubeDownloadMetadata(
          requestedName: 'My song',
          originalTitle: 'Official Video - My song (Remastered)',
          channel: 'An Artist',
          videoId: 'dQw4w9WgXcQ',
          videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          format: 'mp3',
          quality: '192k',
          durationMs: 214000,
          thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          artworkPath: '/artwork/dQw4w9WgXcQ.jpg',
          mediaFileName: 'My song.mp3',
          byteSize: 4096,
          savedAtMs: 1700000000000,
        );

        final sidecar = await metadata.writeNextTo(media);
        final decoded = jsonDecode(await sidecar.readAsString());

        expect(sidecar.path, endsWith('My song.metadata.json'));
        expect(decoded['requestedName'], 'My song');
        expect(
          decoded['originalTitle'],
          'Official Video - My song (Remastered)',
        );
        expect(decoded['channel'], 'An Artist');
        expect(decoded['videoId'], 'dQw4w9WgXcQ');
        expect(decoded['format'], 'mp3');
        expect(decoded['durationMs'], 214000);
        expect(decoded['artworkPath'], '/artwork/dQw4w9WgXcQ.jpg');
        expect(
          YouTubeDownloadMetadata.fromJson(decoded).requestedName,
          'My song',
        );
      },
    );

    test(
      'a rip request derives its safe file name from the requested name',
      () {
        const request = YouTubeRipRequest(
          videoId: 'dQw4w9WgXcQ',
          videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          requestedName: 'Road Trip: Mix!',
          originalTitle: 'Actual YouTube title',
          channel: 'Channel',
          format: YouTubeDownloadFormat.mp4,
          quality: '1080p',
        );

        expect(request.safeFileName, 'Road Trip_ Mix!');
        expect(request.originalTitle, 'Actual YouTube title');
      },
    );
  });
}
