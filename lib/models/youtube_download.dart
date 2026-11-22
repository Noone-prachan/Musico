import 'dart:convert';
import 'dart:io';

import 'youtube_media.dart';

const _reservedWindowsNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

/// Turns a user-typed name into a name that is safe for a file on Windows,
/// Android and Linux.
String sanitizeYouTubeFileName(String value) {
  var name = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (name.endsWith('.')) {
    name = name.substring(0, name.length - 1).trimRight();
  }
  if (name.isEmpty) name = 'YouTube download';
  if (_reservedWindowsNames.contains(name.split('.').first.toUpperCase())) {
    name = '_$name';
  }
  if (name.length > 120) name = name.substring(0, 120).trimRight();
  return name;
}

/// Everything the downloader needs to rip one video under a user-chosen name.
class YouTubeRipRequest {
  const YouTubeRipRequest({
    required this.videoId,
    required this.videoUrl,
    required this.requestedName,
    required this.originalTitle,
    required this.channel,
    required this.format,
    this.quality,
    this.durationMs,
    this.thumbnailUrl,
  });

  final String videoId;
  final String videoUrl;

  /// Name the user asked for; used for the file name and the embedded title.
  final String requestedName;

  /// The video's real YouTube title, kept in the metadata sidecar.
  final String originalTitle;
  final String channel;
  final YouTubeDownloadFormat format;
  final String? quality;
  final int? durationMs;
  final String? thumbnailUrl;

  String get safeFileName => sanitizeYouTubeFileName(requestedName);
}

/// Details written to a small `.metadata.json` file beside every ripped file.
class YouTubeDownloadMetadata {
  const YouTubeDownloadMetadata({
    required this.requestedName,
    required this.originalTitle,
    required this.channel,
    required this.videoId,
    required this.videoUrl,
    required this.format,
    required this.savedAtMs,
    this.quality,
    this.durationMs,
    this.thumbnailUrl,
    this.artworkPath,
    this.mediaFileName,
    this.byteSize,
  });

  final String requestedName;
  final String originalTitle;
  final String channel;
  final String videoId;
  final String videoUrl;
  final String format;
  final int savedAtMs;
  final String? quality;
  final int? durationMs;
  final String? thumbnailUrl;
  final String? artworkPath;
  final String? mediaFileName;
  final int? byteSize;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'source': 'youtube',
    'requestedName': requestedName,
    'originalTitle': originalTitle,
    'channel': channel,
    'videoId': videoId,
    'videoUrl': videoUrl,
    'format': format,
    'savedAtMs': savedAtMs,
    if (quality != null) 'quality': quality,
    if (durationMs != null) 'durationMs': durationMs,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (artworkPath != null) 'artworkPath': artworkPath,
    if (mediaFileName != null) 'mediaFileName': mediaFileName,
    if (byteSize != null) 'byteSize': byteSize,
  };

  factory YouTubeDownloadMetadata.fromJson(Map<String, dynamic> json) {
    return YouTubeDownloadMetadata(
      requestedName: json['requestedName'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
      channel: json['channel'] as String? ?? '',
      videoId: json['videoId'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      format: json['format'] as String? ?? '',
      savedAtMs: (json['savedAtMs'] as num?)?.toInt() ?? 0,
      quality: json['quality'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      mediaFileName: json['mediaFileName'] as String?,
      byteSize: (json['byteSize'] as num?)?.toInt(),
    );
  }

  /// Writes the sidecar next to [mediaFile], e.g. `My song.metadata.json`.
  Future<File> writeNextTo(File mediaFile) async {
    final path = mediaFile.path.replaceFirst(
      RegExp(r'\.[^./\\]+$'),
      '.metadata.json',
    );
    final file = File(path);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      flush: true,
    );
    return file;
  }
}
