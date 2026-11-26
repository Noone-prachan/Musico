import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/youtube_download.dart';
import 'package:musico/models/youtube_media.dart';
import 'package:musico/services/youtube_download_service.dart';
import 'package:musico/services/yt_dlp_executable_resolver.dart';

void main() {
  group('parseYtDlpProgress', () {
    test('parses progress output emitted by yt-dlp', () {
      expect(
        parseYtDlpProgress(
          '[download]  42.5% of 8.00MiB at 2.00MiB/s ETA 00:02',
        ),
        0.425,
      );
      expect(parseYtDlpProgress('[download] 100.0% of 8.00MiB'), 1);
    });

    test('ignores status lines without a valid percentage', () {
      expect(parseYtDlpProgress('[download] Destination: track.webm'), isNull);
      expect(parseYtDlpProgress('[download] NaN%'), isNull);
    });
  });

  test('parses and sorts downloadable MP4 qualities from yt-dlp metadata', () {
    final qualities = YouTubeDownloadService.parseYtDlpQualities(
      jsonEncode({
        'formats': [
          {
            'format_id': '136',
            'format_note': '720p',
            'height': 720,
            'ext': 'mp4',
            'vcodec': 'avc1.4d401f',
            'tbr': 1200,
            'filesize': 20000000,
          },
          {
            'format_id': '137',
            'format_note': '1080p',
            'height': 1080,
            'ext': 'mp4',
            'vcodec': 'avc1.640028',
            'tbr': 2400,
            'filesize_approx': 40000000,
          },
          {
            'format_id': '248',
            'format_note': '1080p',
            'height': 1080,
            'ext': 'webm',
            'vcodec': 'vp9',
            'tbr': 2600,
          },
          {'format_id': '140', 'height': null, 'ext': 'm4a', 'vcodec': 'none'},
        ],
      }),
    );

    expect(qualities.map((quality) => quality.label), ['1080p', '720p']);
    expect(qualities.first.itag, 137);
    expect(qualities.first.sizeBytes, 40000000);
  });

  test('Android MP4 selection prefers the chosen format with fallbacks', () {
    expect(
      YouTubeDownloadService.androidVideoFormatSelector(
        height: 720,
        formatId: 137,
      ),
      '137/bestvideo*[height<=720][ext=mp4]/'
      'best[height<=720][ext=mp4]/best[ext=mp4]',
    );
    expect(
      YouTubeDownloadService.androidVideoFormatSelector(height: 480),
      'bestvideo*[height<=480][ext=mp4]/'
      'best[height<=480][ext=mp4]/best[ext=mp4]',
    );
  });

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

  group('ytDlpRuntimeArguments', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'musico-ytdlp-runtime',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('uses the bundled Deno runtime when it is present', () async {
      final deno = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}deno.exe',
      );
      await deno.create(recursive: true);

      expect(
        ytDlpRuntimeArguments(applicationDirectory: temporaryDirectory.path),
        ['--js-runtimes', 'deno:${deno.path}'],
      );
    });

    test('does not pass a runtime option when Deno is not bundled', () {
      expect(
        ytDlpRuntimeArguments(applicationDirectory: temporaryDirectory.path),
        isEmpty,
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
