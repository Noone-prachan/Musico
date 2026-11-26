enum VideoCategory { other, tvShow, movie }

class VideoTrack {
  const VideoTrack({
    required this.id,
    required this.title,
    required this.path,
    required this.addedAtMs,
    required this.byteSize,
    this.rights,
    this.attribution,
    this.sourceUrl,
    this.artist,
    this.originalTitle,
    this.videoId,
    this.thumbnailUrl,
    this.artworkPath,
    this.quality,
    this.category = VideoCategory.other,
    this.positionMs = 0,
    this.durationMs = 0,
    this.lastWatchedAtMs = 0,
    this.completed = false,
  });

  final String id;
  final String title;
  final String path;
  final int addedAtMs;
  final int byteSize;
  final String? rights;
  final String? attribution;
  final String? sourceUrl;
  final String? artist;
  final String? originalTitle;
  final String? videoId;
  final String? thumbnailUrl;
  final String? artworkPath;
  final String? quality;
  final VideoCategory category;
  final int positionMs;
  final int durationMs;
  final int lastWatchedAtMs;
  final bool completed;

  bool get isResumable =>
      !completed &&
      durationMs > 0 &&
      positionMs >= const Duration(seconds: 30).inMilliseconds &&
      durationMs - positionMs > const Duration(seconds: 15).inMilliseconds;

  double get playbackProgress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1).toDouble();

  VideoTrack copyWith({
    int? positionMs,
    int? durationMs,
    int? lastWatchedAtMs,
    bool? completed,
    VideoCategory? category,
    String? artist,
    String? originalTitle,
    String? videoId,
    String? thumbnailUrl,
    String? artworkPath,
    String? quality,
    String? sourceUrl,
  }) => VideoTrack(
    id: id,
    title: title,
    path: path,
    addedAtMs: addedAtMs,
    byteSize: byteSize,
    rights: rights,
    attribution: attribution,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    artist: artist ?? this.artist,
    originalTitle: originalTitle ?? this.originalTitle,
    videoId: videoId ?? this.videoId,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    artworkPath: artworkPath ?? this.artworkPath,
    quality: quality ?? this.quality,
    category: category ?? this.category,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    lastWatchedAtMs: lastWatchedAtMs ?? this.lastWatchedAtMs,
    completed: completed ?? this.completed,
  );

  factory VideoTrack.fromJson(Map<String, dynamic> json) => VideoTrack(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled video',
    path: json['path'] as String,
    addedAtMs: json['addedAtMs'] as int? ?? 0,
    byteSize: json['byteSize'] as int? ?? 0,
    rights: json['rights'] as String?,
    attribution: json['attribution'] as String?,
    sourceUrl: json['sourceUrl'] as String?,
    artist: json['artist'] as String?,
    originalTitle: json['originalTitle'] as String?,
    videoId: json['videoId'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    artworkPath: json['artworkPath'] as String?,
    quality: json['quality'] as String?,
    category: switch (json['category']) {
      'tvShow' => VideoCategory.tvShow,
      'movie' => VideoCategory.movie,
      _ => VideoCategory.other,
    },
    positionMs: (json['positionMs'] as int? ?? 0).clamp(0, 1 << 62).toInt(),
    durationMs: (json['durationMs'] as int? ?? 0).clamp(0, 1 << 62).toInt(),
    lastWatchedAtMs: (json['lastWatchedAtMs'] as int? ?? 0)
        .clamp(0, 1 << 62)
        .toInt(),
    completed: json['completed'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'path': path,
    'addedAtMs': addedAtMs,
    'byteSize': byteSize,
    'rights': rights,
    'attribution': attribution,
    'sourceUrl': sourceUrl,
    if (artist != null) 'artist': artist,
    if (originalTitle != null) 'originalTitle': originalTitle,
    if (videoId != null) 'videoId': videoId,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (artworkPath != null) 'artworkPath': artworkPath,
    if (quality != null) 'quality': quality,
    'category': category.name,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastWatchedAtMs': lastWatchedAtMs,
    'completed': completed,
  };
}
