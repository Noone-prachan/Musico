import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musico/models/media_download.dart';
import 'package:musico/services/direct_media_download_service.dart';

void main() {
  group('direct media downloader', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'musico-direct-download',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('streams a direct audio response to a local file', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: const {'content-type': 'audio/mpeg'},
        ),
      );
      final progress = <double?>[];
      final item = MediaDownloadLink.fromJson(
        {
          'id': 'track-01',
          'title': 'Night Drive',
          'url': 'https://cdn.example.org/night-drive.mp3',
          'rights': 'user_owned',
        },
        category: MediaDownloadCategory.music,
        location: 'music[1]',
      );

      final downloaded = await DirectMediaDownloadService(client)
          .download(item, temporaryDirectory, onProgress: progress.add);

      expect(downloaded.byteSize, 4);
      expect(downloaded.file.path, endsWith('.mp3'));
      expect(await downloaded.file.readAsBytes(), [1, 2, 3, 4]);
      expect(progress.last, 1);
      client.close();
    });

    test('rejects HTML responses and removes partial downloads', () async {
      final client = MockClient(
        (request) async => http.Response(
          '<html>not a media file</html>',
          200,
          headers: const {'content-type': 'text/html'},
        ),
      );
      final item = MediaDownloadLink.fromJson(
        {
          'id': 'clip-01',
          'title': 'Clip',
          'url': 'https://cdn.example.org/clip.mp4',
          'rights': 'permission',
        },
        category: MediaDownloadCategory.video,
        location: 'video[1]',
      );

      await expectLater(
        DirectMediaDownloadService(client)
            .download(item, temporaryDirectory, onProgress: (_) {}),
        throwsFormatException,
      );
      expect(await temporaryDirectory.list().isEmpty, isTrue);
      client.close();
    });

    test('does not follow a redirect to an insecure URL', () async {
      final client = MockClient(
        (request) async => http.Response(
          '',
          302,
          headers: const {'location': 'http://cdn.example.org/track.mp3'},
        ),
      );
      final item = MediaDownloadLink.fromJson(
        {
          'id': 'track-01',
          'title': 'Track',
          'url': 'https://cdn.example.org/track.mp3',
          'rights': 'permission',
        },
        category: MediaDownloadCategory.music,
        location: 'music[1]',
      );

      await expectLater(
        DirectMediaDownloadService(client)
            .download(item, temporaryDirectory, onProgress: (_) {}),
        throwsFormatException,
      );
      client.close();
    });
  });
}
