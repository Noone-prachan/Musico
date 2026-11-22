import 'dart:convert';

enum MediaDownloadCategory {
  music('music'),
  video('video'),
  anime('anime');

  const MediaDownloadCategory(this.key);

  final String key;
}

enum MediaRights {
  publicDomain('public_domain', 'Public domain'),
  cc0('cc0', 'CC0'),
  ccBy('cc_by', 'CC BY'),
  ccBySa('cc_by_sa', 'CC BY-SA'),
  userOwned('user_owned', 'I own this media'),
  permission('permission', 'I have permission to download this media');

  const MediaRights(this.key, this.label);

  final String key;
  final String label;

  static MediaRights parse(Object? value, String location) {
    for (final rights in values) {
      if (rights.key == value) return rights;
    }
    throw FormatException(
      '$location must declare public_domain, cc0, cc_by, cc_by_sa, user_owned, or permission.',
    );
  }
}

class MediaDownloadLink {
  const MediaDownloadLink({
    required this.id,
    required this.title,
    required this.url,
    required this.category,
    required this.rights,
    this.artist,
    this.attribution,
    this.licenseUrl,
  });

  final String id;
  final String title;
  final String url;
  final MediaDownloadCategory category;
  final MediaRights rights;
  final String? artist;
  final String? attribution;
  final String? licenseUrl;

  Uri get uri => Uri.parse(url);

  String get progressKey => '${category.key}:$id';

  void validateRedirectUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        _isStreamingService(uri.host)) {
      throw const FormatException(
        'The download redirected to an unsafe or unsupported address.',
      );
    }
  }

  factory MediaDownloadLink.fromJson(
    Map<String, dynamic> json, {
    required MediaDownloadCategory category,
    required String location,
  }) {
    final id = json['id'];
    if (id is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$').hasMatch(id)) {
      throw FormatException('$location needs a simple, unique id.');
    }

    final title = json['title'];
    if (title is! String || title.trim().isEmpty) {
      throw FormatException('$location needs a title.');
    }

    final url = json['url'];
    if (url is! String) {
      throw FormatException('$location needs a direct media file url.');
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !_hasSupportedExtension(uri.path, category) ||
        _isStreamingService(uri.host)) {
      throw FormatException(
        '$location must use an HTTPS direct audio/video file URL, not a streaming or web page.',
      );
    }

    final rights = MediaRights.parse(json['rights'], location);
    final artist = _optionalText(json['artist'], '$location artist');
    final attribution = _optionalText(
      json['attribution'],
      '$location attribution',
    );
    final licenseUrl = _optionalText(
      json['licenseUrl'],
      '$location licenseUrl',
    );
    if (licenseUrl != null) {
      final parsedLicenseUrl = Uri.tryParse(licenseUrl);
      if (parsedLicenseUrl == null ||
          parsedLicenseUrl.scheme != 'https' ||
          parsedLicenseUrl.host.isEmpty ||
          parsedLicenseUrl.userInfo.isNotEmpty) {
        throw FormatException('$location licenseUrl must use HTTPS.');
      }
    }
    if ((rights == MediaRights.ccBy || rights == MediaRights.ccBySa) &&
        (attribution == null || attribution.isEmpty)) {
      throw FormatException(
        '$location needs attribution for ${rights.label} media.',
      );
    }

    return MediaDownloadLink(
      id: id,
      title: title.trim(),
      url: uri.toString(),
      category: category,
      rights: rights,
      artist: artist,
      attribution: attribution,
      licenseUrl: licenseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'rights': rights.key,
    if (artist != null) 'artist': artist,
    if (attribution != null) 'attribution': attribution,
    if (licenseUrl != null) 'licenseUrl': licenseUrl,
  };

  static String? _optionalText(Object? value, String location) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$location must be text.');
    return value.trim().isEmpty ? null : value.trim();
  }

  static bool _hasSupportedExtension(
    String path,
    MediaDownloadCategory category,
  ) {
    final extension = path
        .substring(path.lastIndexOf('/') + 1)
        .split('.')
        .last
        .toLowerCase();
    return switch (category) {
      MediaDownloadCategory.music => const {
        'aac',
        'flac',
        'm4a',
        'mp3',
        'oga',
        'ogg',
        'opus',
        'wav',
      }.contains(extension),
      MediaDownloadCategory.video || MediaDownloadCategory.anime => const {
        'avi',
        'm4v',
        'mkv',
        'mov',
        'mp4',
        'webm',
      }.contains(extension),
    };
  }

  static bool _isStreamingService(String host) {
    final normalizedHost = host.toLowerCase();
    const blockedHosts = {
      'youtu.be',
      'googlevideo.com',
      'netflix.com',
      'nflxvideo.net',
      'primevideo.com',
      'disneyplus.com',
      'hulu.com',
      'crunchyroll.com',
      'tiktok.com',
    };
    return blockedHosts.any(
      (blocked) =>
          normalizedHost == blocked || normalizedHost.endsWith('.$blocked'),
    );
  }
}

class MediaDownloadConfig {
  MediaDownloadConfig({
    required Map<MediaDownloadCategory, List<MediaDownloadLink>> downloads,
  }) : downloads =
           Map<MediaDownloadCategory, List<MediaDownloadLink>>.unmodifiable({
             for (final category in MediaDownloadCategory.values)
               category: List<MediaDownloadLink>.unmodifiable(
                 downloads[category] ?? const <MediaDownloadLink>[],
               ),
           });

  final Map<MediaDownloadCategory, List<MediaDownloadLink>> downloads;

  List<MediaDownloadLink> forCategory(MediaDownloadCategory category) =>
      downloads[category] ?? const [];

  factory MediaDownloadConfig.empty() => MediaDownloadConfig(
    downloads: const {
      MediaDownloadCategory.music: [],
      MediaDownloadCategory.video: [],
      MediaDownloadCategory.anime: [],
    },
  );

  factory MediaDownloadConfig.decode(String contents) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported direct download links file format.',
      );
    }
    final rawDownloads = decoded['downloads'];
    if (rawDownloads is! Map<String, dynamic>) {
      throw const FormatException(
        'The direct download links file needs a downloads object.',
      );
    }

    final downloads = <MediaDownloadCategory, List<MediaDownloadLink>>{};
    final ids = <String>{};
    for (final category in MediaDownloadCategory.values) {
      final rawEntries = rawDownloads[category.key] ?? const <dynamic>[];
      if (rawEntries is! List) {
        throw FormatException(
          'The "${category.key}" downloads entry must be a list.',
        );
      }
      downloads[category] = [
        for (var index = 0; index < rawEntries.length; index++)
          if (rawEntries[index] case final Map<String, dynamic> entry)
            MediaDownloadLink.fromJson(
              entry,
              category: category,
              location: '${category.key}[${index + 1}]',
            )
          else
            throw FormatException(
              '${category.key}[${index + 1}] must be an object.',
            ),
      ];
      for (final link in downloads[category]!) {
        if (!ids.add(link.progressKey)) {
          throw FormatException(
            'The direct download id "${link.id}" is repeated in ${category.key}.',
          );
        }
      }
    }
    return MediaDownloadConfig(downloads: downloads);
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'downloads': {
      for (final category in MediaDownloadCategory.values)
        category.key: forCategory(category)
            .map((link) => link.toJson())
            .toList(),
    },
  });
}
