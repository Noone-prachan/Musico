class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.path,
    required this.durationMs,
    required this.addedAtMs,
    required this.license,
    required this.licenseUrl,
    required this.sourceUrl,
    required this.commonsPageId,
    required this.byteSize,
    this.attribution,
    this.artworkPath,
    this.artworkTitle,
    this.artworkCreator,
    this.artworkLicense,
    this.artworkAttribution,
    this.artworkLicenseUrl,
    this.artworkSourceUrl,
    this.clipStartMs,
    this.clipEndMs,
  });

  final String id;
  final String title;
  final String artist;
  final String path;
  final int durationMs;
  final int addedAtMs;
  final String? license;
  final String? licenseUrl;
  final String? sourceUrl;
  final int? commonsPageId;
  final int byteSize;
  final String? attribution;
  final String? artworkPath;
  final String? artworkTitle;
  final String? artworkCreator;
  final String? artworkLicense;
  final String? artworkAttribution;
  final String? artworkLicenseUrl;
  final String? artworkSourceUrl;
  final int? clipStartMs;
  final int? clipEndMs;

  bool get isFromCommons => commonsPageId != null;

  ({String title, String artist}) get displayMetadata {
    if (artist.toLowerCase() != 'imported audio') {
      return (title: title, artist: artist);
    }

    final normalized = title
        .replaceAll('+', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\(\s+'), '(')
        .replaceAll(RegExp(r'\s+\)'), ')')
        .replaceFirst(RegExp(r'\s+\[[A-Za-z0-9_-]{11}\]$'), '')
        .trim();
    final separator = RegExp(r'\s[-–—]\s').firstMatch(normalized);
    if (separator == null) return (title: normalized, artist: artist);

    final parsedArtist = normalized.substring(0, separator.start).trim();
    final parsedTitle = normalized.substring(separator.end).trim();
    if (parsedArtist.isEmpty || parsedTitle.isEmpty) {
      return (title: normalized, artist: artist);
    }
    return (title: parsedTitle, artist: parsedArtist);
  }

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final durationMs = json['durationMs'] as int? ?? 0;
    final clipStartMs = json['clipStartMs'] as int? ?? 0;
    final clipEndMs = json['clipEndMs'] as int?;
    if (clipStartMs < 0 ||
        (clipEndMs != null &&
            (clipEndMs <= clipStartMs ||
                (durationMs > 0 && clipEndMs > durationMs)))) {
      throw const FormatException('The saved audio trim is invalid.');
    }
    return MusicTrack(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled audio',
      artist: json['artist'] as String? ?? 'Your music',
      path: json['path'] as String,
      durationMs: durationMs,
      addedAtMs: json['addedAtMs'] as int? ?? 0,
      license: json['license'] as String?,
      licenseUrl: json['licenseUrl'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      commonsPageId: json['commonsPageId'] as int?,
      byteSize: json['byteSize'] as int? ?? 0,
      attribution: json['attribution'] as String?,
      artworkPath: json['artworkPath'] as String?,
      artworkTitle: json['artworkTitle'] as String?,
      artworkCreator: json['artworkCreator'] as String?,
      artworkLicense: json['artworkLicense'] as String?,
      artworkAttribution: json['artworkAttribution'] as String?,
      artworkLicenseUrl: json['artworkLicenseUrl'] as String?,
      artworkSourceUrl: json['artworkSourceUrl'] as String?,
      clipStartMs: clipStartMs == 0 ? null : clipStartMs,
      clipEndMs: clipEndMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'path': path,
    'durationMs': durationMs,
    'addedAtMs': addedAtMs,
    'license': license,
    'licenseUrl': licenseUrl,
    'sourceUrl': sourceUrl,
    'commonsPageId': commonsPageId,
    'byteSize': byteSize,
    'attribution': attribution,
    'artworkPath': artworkPath,
    'artworkTitle': artworkTitle,
    'artworkCreator': artworkCreator,
    'artworkLicense': artworkLicense,
    'artworkAttribution': artworkAttribution,
    'artworkLicenseUrl': artworkLicenseUrl,
    'artworkSourceUrl': artworkSourceUrl,
    'clipStartMs': clipStartMs,
    'clipEndMs': clipEndMs,
  };

  MusicTrack copyWith({int? durationMs, String? title, String? artist}) {
    return MusicTrack(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      path: path,
      durationMs: durationMs ?? this.durationMs,
      addedAtMs: addedAtMs,
      license: license,
      licenseUrl: licenseUrl,
      sourceUrl: sourceUrl,
      commonsPageId: commonsPageId,
      byteSize: byteSize,
      attribution: attribution,
      artworkPath: artworkPath,
      artworkTitle: artworkTitle,
      artworkCreator: artworkCreator,
      artworkLicense: artworkLicense,
      artworkAttribution: artworkAttribution,
      artworkLicenseUrl: artworkLicenseUrl,
      artworkSourceUrl: artworkSourceUrl,
      clipStartMs: clipStartMs,
      clipEndMs: clipEndMs,
    );
  }

  MusicTrack withArtwork({
    required String path,
    required String title,
    required String creator,
    required String license,
    required String licenseUrl,
    required String sourceUrl,
    required String attribution,
  }) => MusicTrack(
    id: id,
    title: this.title,
    artist: artist,
    path: this.path,
    durationMs: durationMs,
    addedAtMs: addedAtMs,
    license: this.license,
    licenseUrl: this.licenseUrl,
    sourceUrl: this.sourceUrl,
    commonsPageId: commonsPageId,
    byteSize: byteSize,
    attribution: this.attribution,
    artworkPath: path,
    artworkTitle: title,
    artworkCreator: creator,
    artworkLicense: license,
    artworkAttribution: attribution,
    artworkLicenseUrl: licenseUrl,
    artworkSourceUrl: sourceUrl,
    clipStartMs: clipStartMs,
    clipEndMs: clipEndMs,
  );

  MusicTrack withTrim({required int? startMs, required int? endMs}) =>
      MusicTrack(
        id: id,
        title: title,
        artist: artist,
        path: path,
        durationMs: durationMs,
        addedAtMs: addedAtMs,
        license: license,
        licenseUrl: licenseUrl,
        sourceUrl: sourceUrl,
        commonsPageId: commonsPageId,
        byteSize: byteSize,
        attribution: attribution,
        artworkPath: artworkPath,
        artworkTitle: artworkTitle,
        artworkCreator: artworkCreator,
        artworkLicense: artworkLicense,
        artworkAttribution: artworkAttribution,
        artworkLicenseUrl: artworkLicenseUrl,
        artworkSourceUrl: artworkSourceUrl,
        clipStartMs: startMs == 0 ? null : startMs,
        clipEndMs: endMs,
      );
}

class MusicResult {
  const MusicResult({
    required this.pageId,
    required this.title,
    required this.artist,
    required this.mime,
    required this.size,
    required this.duration,
    required this.fileUrl,
    required this.sourceUrl,
    required this.license,
    required this.licenseUrl,
  });

  final int pageId;
  final String title;
  final String artist;
  final String mime;
  final int size;
  final int duration;
  final String fileUrl;
  final String sourceUrl;
  final String license;
  final String licenseUrl;

  factory MusicResult.fromJson(Map<String, dynamic> page) {
    final imageInfo =
        (page['imageinfo'] as List<dynamic>).first as Map<String, dynamic>;
    final metadata =
        imageInfo['extmetadata'] as Map<String, dynamic>? ?? const {};
    final title =
        _plainText(metadata['ObjectName']?['value'] as String?) ??
        (page['title'] as String? ?? 'Untitled audio')
            .replaceFirst(RegExp(r'^File:', caseSensitive: false), '')
            .replaceAll('_', ' ')
            .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final artist =
        _plainText(metadata['Artist']?['value'] as String?) ??
        _plainText(metadata['Credit']?['value'] as String?) ??
        'Wikimedia Commons contributor';

    return MusicResult(
      pageId: page['pageid'] as int,
      title: title,
      artist: artist,
      mime: imageInfo['mime'] as String? ?? 'audio/mpeg',
      size: imageInfo['size'] as int? ?? 0,
      duration: imageInfo['duration'] as int? ?? 0,
      fileUrl: imageInfo['url'] as String,
      sourceUrl: imageInfo['descriptionurl'] as String,
      license:
          _license(metadata) ??
          (throw const FormatException('Unsupported audio license.')),
      licenseUrl:
          metadata['LicenseUrl']?['value'] as String? ??
          imageInfo['descriptionurl'] as String,
    );
  }

  static String? _plainText(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _license(Map<String, dynamic> metadata) {
    final name = metadata['LicenseShortName']?['value'] as String? ?? '';
    final usage = metadata['UsageTerms']?['value'] as String? ?? '';
    final license = '$name $usage';
    final isPublicDomain = RegExp(
      r'public domain|\bPD[-\s]|CC0|Creative Commons Zero',
      caseSensitive: false,
    ).hasMatch(license);
    final isAttribution = RegExp(
      r'CC[-\s]BY(?:[-\s]SA)?(?:\s|[-\d]|$)|Creative Commons Attribution(?:-ShareAlike)?',
      caseSensitive: false,
    ).hasMatch(license);
    final restricted = RegExp(
      r'non.?commercial|\bNC\b|no derivatives|\bND\b|all rights reserved',
      caseSensitive: false,
    ).hasMatch(license);

    if ((!isPublicDomain && !isAttribution) || restricted) return null;
    return name.isEmpty
        ? (isPublicDomain ? 'Public domain' : 'Creative Commons Attribution')
        : name;
  }
}
