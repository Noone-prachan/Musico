import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class LicensedArtwork {
  const LicensedArtwork({
    required this.bytes,
    required this.extension,
    required this.title,
    required this.creator,
    required this.license,
    required this.licenseUrl,
    required this.sourceUrl,
  });

  final Uint8List bytes;
  final String extension;
  final String title;
  final String creator;
  final String license;
  final String licenseUrl;
  final String sourceUrl;

  String get attribution => creator.trim().isEmpty
      ? '"$title" ($license), $sourceUrl, $licenseUrl'
      : '"$title" by $creator ($license), $sourceUrl, $licenseUrl';
}

class OpenverseArtworkService {
  const OpenverseArtworkService(this._client);

  static const _allowedLicenses = {'by', 'by-sa', 'cc0', 'pdm'};
  static const _attributionLicenses = {'by', 'by-sa'};
  static const _trackTitleNoise = {
    '4k',
    'audio',
    'extended',
    'full',
    'hd',
    'hq',
    'lyric',
    'lyrics',
    'music',
    'official',
    'video',
    'visualizer',
    'version',
  };
  static const _artworkDescriptors = {
    '4k',
    'album',
    'art',
    'artwork',
    'audio',
    'cover',
    'extended',
    'fan',
    'fanart',
    'full',
    'hd',
    'hq',
    'image',
    'lyric',
    'lyrics',
    'music',
    'official',
    'poster',
    'single',
    'video',
    'visualizer',
    'version',
  };
  static const _maxArtworkBytes = 10 * 1024 * 1024;
  static const _maxRedirects = 5;

  final http.Client _client;

  Future<LicensedArtwork?> findForTrack({
    required String title,
    required String artist,
  }) async {
    final normalizedTitle = _normalize(title);
    final normalizedArtist = _normalize(artist);
    if (normalizedTitle.isEmpty || normalizedArtist.isEmpty) return null;

    final searchTitle = _tokens(title, ignoreTrackTitleNoise: true).join(' ');
    final primaryTitle = title.split(RegExp(r'[\(\[]')).first.trim();
    final primarySearchTitle = _tokens(
      primaryTitle,
      ignoreTrackTitleNoise: true,
    ).join(' ');
    final searchQueries = <String>{
      '$searchTitle $artist',
      '$primarySearchTitle $artist',
      primarySearchTitle,
      searchTitle,
    }.where((query) => query.trim().isNotEmpty);

    for (final query in searchQueries) {
      final searchUri = Uri.https('api.openverse.org', '/v1/images/', {
        'q': query,
        'license': 'cc0,by,by-sa,pdm',
        'page_size': '20',
      });
      final response = await _client.get(
        searchUri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'Musico/1.0 (licensed artwork lookup)',
        },
      );
      if (response.statusCode != 200) {
        throw HttpException(
          'Openverse returned ${response.statusCode}.',
          uri: searchUri,
        );
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> || payload['results'] is! List) {
        throw const FormatException(
          'Openverse returned an invalid image list.',
        );
      }

      for (final raw in payload['results'] as List<dynamic>) {
        if (raw is! Map<String, dynamic>) continue;
        final resultTitle = raw['title'];
        final creator = raw['creator'];
        final license = raw['license'];
        if (resultTitle is! String ||
            creator is! String ||
            license is! String ||
            !_allowedLicenses.contains(license.toLowerCase()) ||
            (_attributionLicenses.contains(license.toLowerCase()) &&
                creator.trim().isEmpty) ||
            !_matchesTrack(
              resultTitle: resultTitle,
              creator: creator,
              tags: raw['tags'],
              title: title,
              artist: artist,
              normalizedTitle: normalizedTitle,
              normalizedArtist: normalizedArtist,
            )) {
          continue;
        }

        final imageUri = _httpsUri(raw['thumbnail']);
        final licenseUri = _httpsUri(raw['license_url']);
        final sourceUri = _httpsUri(raw['foreign_landing_url']);
        if (imageUri == null || licenseUri == null || sourceUri == null) {
          continue;
        }

        final image = await _downloadImage(imageUri);
        if (image == null) continue;
        return LicensedArtwork(
          bytes: image.bytes,
          extension: image.extension,
          title: resultTitle,
          creator: creator.trim(),
          license: _displayLicense(license, raw['license_version']),
          licenseUrl: licenseUri.toString(),
          sourceUrl: sourceUri.toString(),
        );
      }
    }
    return null;
  }

  Future<({Uint8List bytes, String extension})?> _downloadImage(
    Uri initialUri,
  ) async {
    var uri = initialUri;
    for (
      var redirectCount = 0;
      redirectCount <= _maxRedirects;
      redirectCount++
    ) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'image/jpeg, image/png, image/webp'
        ..headers['User-Agent'] = 'Musico/1.0 (licensed artwork lookup)';
      final response = await _client.send(request);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || redirectCount == _maxRedirects) {
          throw const HttpException(
            'The artwork image redirected too many times.',
          );
        }
        final destination = uri.resolve(location);
        if (destination.scheme != 'https' ||
            destination.host.isEmpty ||
            destination.userInfo.isNotEmpty) {
          throw const HttpException(
            'The artwork image redirected to an unsafe URL.',
          );
        }
        uri = destination;
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        return null;
      }

      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final extension = switch (contentType) {
        'image/jpeg' => '.jpg',
        'image/png' => '.png',
        'image/webp' => '.webp',
        _ => null,
      };
      if (extension == null ||
          (response.contentLength != null &&
              response.contentLength! > _maxArtworkBytes)) {
        await response.stream.drain<void>();
        return null;
      }

      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.stream) {
        length += chunk.length;
        if (length > _maxArtworkBytes) {
          throw const HttpException(
            'The artwork image exceeds the 10 MB limit.',
          );
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (!_hasExpectedSignature(bytes, contentType!)) return null;
      return (bytes: bytes, extension: extension);
    }
    throw const HttpException('The artwork image redirected too many times.');
  }

  Uri? _httpsUri(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  String _displayLicense(String license, Object? version) {
    final normalizedVersion = version is String ? version.trim() : '';
    return switch (license.toLowerCase()) {
      'by' => 'CC BY${normalizedVersion.isEmpty ? '' : ' $normalizedVersion'}',
      'by-sa' =>
        'CC BY-SA${normalizedVersion.isEmpty ? '' : ' $normalizedVersion'}',
      'cc0' => 'CC0',
      'pdm' => 'Public Domain Mark',
      _ => license,
    };
  }

  bool _hasExpectedSignature(Uint8List bytes, String contentType) {
    if (contentType == 'image/png') {
      return bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0d &&
          bytes[5] == 0x0a &&
          bytes[6] == 0x1a &&
          bytes[7] == 0x0a;
    }
    if (contentType == 'image/jpeg') {
      return bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
    }
    if (contentType == 'image/webp') {
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    }
    return false;
  }

  bool _matchesTrack({
    required String resultTitle,
    required String creator,
    required Object? tags,
    required String title,
    required String artist,
    required String normalizedTitle,
    required String normalizedArtist,
  }) {
    final titleTokens = _tokens(title, ignoreTrackTitleNoise: true);
    final resultTitleTokens = _tokens(resultTitle);
    final primaryTitle = title.split(RegExp(r'[\(\[]')).first.trim();
    final primaryTitleTokens = _tokens(
      primaryTitle,
      ignoreTrackTitleNoise: true,
    );
    final extraPrimaryTokens = resultTitleTokens.difference(primaryTitleTokens);
    final primaryTitleMatch =
        _normalize(resultTitle) == normalizedTitle ||
        (primaryTitleTokens.length >= 2 &&
            primaryTitleTokens.every(resultTitleTokens.contains) &&
            extraPrimaryTokens.every(_artworkDescriptors.contains));
    final matchingTitleTokens = titleTokens
        .where(resultTitleTokens.contains)
        .length;
    final extraTitleTokens = resultTitleTokens.difference(titleTokens);
    final titleMatch =
        _normalize(resultTitle) == normalizedTitle ||
        (titleTokens.isNotEmpty &&
            matchingTitleTokens * 4 >= titleTokens.length * 3 &&
            extraTitleTokens.every(_artworkDescriptors.contains)) ||
        (titleTokens.length >= 3 &&
            titleTokens.take(2).every(resultTitleTokens.contains) &&
            extraTitleTokens.every(_artworkDescriptors.contains));

    final artistTokens = _tokens(artist);
    final indexedTokens = _tokens('$resultTitle $creator ${_tagText(tags)}');
    final artistMatch =
        _normalize(creator) == normalizedArtist ||
        (artistTokens.isNotEmpty && artistTokens.every(indexedTokens.contains));
    return primaryTitleMatch || (titleMatch && artistMatch);
  }

  String _tagText(Object? tags) {
    if (tags is! List) return '';
    return tags
        .map((tag) {
          if (tag is String) return tag;
          if (tag is Map<String, dynamic> && tag['name'] is String) {
            return tag['name'] as String;
          }
          return '';
        })
        .join(' ');
  }

  Set<String> _tokens(String value, {bool ignoreTrackTitleNoise = false}) {
    const commonWords = {
      'a',
      'an',
      'and',
      'by',
      'for',
      'ka',
      'ke',
      'ki',
      'of',
      'the',
    };
    return _normalize(value)
        .split(' ')
        .where(
          (token) =>
              token.isNotEmpty &&
              !commonWords.contains(token) &&
              (!ignoreTrackTitleNoise || !_trackTitleNoise.contains(token)),
        )
        .toSet();
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
