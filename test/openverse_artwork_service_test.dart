import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musico/services/openverse_artwork_service.dart';

void main() {
  const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

  Map<String, Object?> imageResult({
    String title = 'Ocean Sketch',
    String creator = 'Mira Lune',
    String license = 'by',
    String thumbnail = 'https://images.example.org/cover.png',
    List<Object?> tags = const [],
  }) => {
    'title': title,
    'creator': creator,
    'license': license,
    'license_version': '4.0',
    'license_url': 'https://creativecommons.org/licenses/by/4.0/',
    'foreign_landing_url': 'https://openverse.org/image/123',
    'thumbnail': thumbnail,
    'tags': tags,
  };

  test(
    'downloads exact title-and-artist artwork with permitted attribution',
    () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.openverse.org') {
          return http.Response(
            jsonEncode({
              'results': [imageResult()],
            }),
            200,
            request: request,
          );
        }
        return http.Response.bytes(
          pngSignature,
          200,
          headers: const {'content-type': 'image/png'},
          request: request,
        );
      });
      final service = OpenverseArtworkService(client);

      final artwork = await service.findForTrack(
        title: 'Ocean Sketch',
        artist: 'Mira Lune',
      );

      expect(artwork, isNotNull);
      expect(artwork!.license, 'CC BY 4.0');
      expect(artwork.attribution, contains('Mira Lune'));
      expect(artwork.extension, '.png');
      client.close();
    },
  );

  test('rejects non-exact or unsupported artwork results', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'results': [
            imageResult(title: 'Ocean Sketch (Live)'),
            imageResult(license: 'by-nc'),
          ],
        }),
        200,
        request: request,
      );
    });
    final service = OpenverseArtworkService(client);

    final artwork = await service.findForTrack(
      title: 'Ocean Sketch',
      artist: 'Mira Lune',
    );

    expect(artwork, isNull);
    client.close();
  });

  test('matches licensed cover art when tags identify the artist', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.openverse.org') {
        return http.Response(
          jsonEncode({
            'results': [
              imageResult(
                title: 'Kamal Phool cover artwork',
                creator: 'A photographer',
                tags: [
                  {'name': 'Yabesh Thapa'},
                  {'name': 'Kamal Phool'},
                ],
              ),
            ],
          }),
          200,
          request: request,
        );
      }
      return http.Response.bytes(
        pngSignature,
        200,
        headers: const {'content-type': 'image/png'},
        request: request,
      );
    });
    final service = OpenverseArtworkService(client);

    final artwork = await service.findForTrack(
      title: 'Kamal Phool',
      artist: 'Yabesh Thapa',
    );

    expect(artwork, isNotNull);
    expect(artwork!.creator, 'A photographer');
    expect(artwork.license, 'CC BY 4.0');
    client.close();
  });

  test(
    'falls back to a title-only search when the artist is not indexed',
    () async {
      final queries = <String>[];
      final client = MockClient((request) async {
        if (request.url.host == 'api.openverse.org') {
          final query = request.url.queryParameters['q']!;
          queries.add(query);
          final results = query == 'kamal phool'
              ? [imageResult(title: 'Kamal ka Phool', creator: 'soham_pablo')]
              : <Map<String, Object?>>[];
          return http.Response(jsonEncode({'results': results}), 200);
        }
        return http.Response.bytes(
          pngSignature,
          200,
          headers: const {'content-type': 'image/png'},
          request: request,
        );
      });
      final service = OpenverseArtworkService(client);

      final artwork = await service.findForTrack(
        title: 'Kamal Phool (Dada pari kanchi) OFFICIAL LYRIC VIDEO',
        artist: 'Yabesh Thapa',
      );

      expect(artwork, isNotNull);
      expect(artwork!.title, 'Kamal ka Phool');
      expect(artwork.attribution, contains('soham_pablo'));
      expect(queries, contains('kamal phool Yabesh Thapa'));
      expect(queries, contains('kamal phool'));
      client.close();
    },
  );

  test('refuses artwork redirects from HTTPS to HTTP', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.openverse.org') {
        return http.Response(
          jsonEncode({
            'results': [imageResult()],
          }),
          200,
          request: request,
        );
      }
      return http.Response(
        '',
        302,
        headers: const {'location': 'http://images.example.org/cover.png'},
        request: request,
      );
    });
    final service = OpenverseArtworkService(client);

    await expectLater(
      service.findForTrack(title: 'Ocean Sketch', artist: 'Mira Lune'),
      throwsA(isA<HttpException>()),
    );
    client.close();
  });
}
