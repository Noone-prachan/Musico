enum StreamWatchCategory { anime, tvShow, movie }

class StreamWatchProgress {
  const StreamWatchProgress({
    required this.category,
    required this.catalogId,
    required this.title,
    required this.episodeLabel,
    required this.episodeIndex,
    required this.positionMs,
    required this.durationMs,
    required this.lastWatchedAtMs,
    this.episodeId,
    this.episodeTitle,
    this.season,
    this.episodeNumber,
    this.posterUrl,
  });

  final StreamWatchCategory category;
  final String catalogId;
  final String title;
  final String episodeLabel;
  final String? episodeId;
  final String? episodeTitle;
  final int? season;
  final int? episodeNumber;
  final int episodeIndex;
  final int positionMs;
  final int durationMs;
  final int lastWatchedAtMs;
  final String? posterUrl;

  String get storageKey => '${category.name}:$catalogId';

  double get playbackProgress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0, 1).toDouble();

  bool get isResumable =>
      durationMs > 0 &&
      positionMs >= const Duration(seconds: 30).inMilliseconds &&
      durationMs - positionMs > const Duration(seconds: 15).inMilliseconds;

  factory StreamWatchProgress.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category'];
    final category = StreamWatchCategory.values.where(
      (value) => value.name == categoryName,
    );
    if (categoryName is! String || category.isEmpty) {
      throw const FormatException('Unknown stream progress category.');
    }

    int readInt(String key, {int fallback = 0}) {
      final value = json[key];
      return value is int ? value.clamp(0, 1 << 62).toInt() : fallback;
    }

    String readString(String key, {String fallback = ''}) {
      final value = json[key];
      return value is String ? value : fallback;
    }

    String? readOptionalString(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    int? readOptionalInt(String key) {
      final value = json[key];
      return value is int ? value.clamp(0, 1 << 62).toInt() : null;
    }

    return StreamWatchProgress(
      category: category.first,
      catalogId: readString('catalogId'),
      title: readString('title'),
      episodeLabel: readString('episodeLabel'),
      episodeId: readOptionalString('episodeId'),
      episodeTitle: readOptionalString('episodeTitle'),
      season: readOptionalInt('season'),
      episodeNumber: readOptionalInt('episodeNumber'),
      episodeIndex: readInt('episodeIndex'),
      positionMs: readInt('positionMs'),
      durationMs: readInt('durationMs'),
      lastWatchedAtMs: readInt('lastWatchedAtMs'),
      posterUrl: readOptionalString('posterUrl'),
    );
  }

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'catalogId': catalogId,
    'title': title,
    'episodeLabel': episodeLabel,
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
    'season': season,
    'episodeNumber': episodeNumber,
    'episodeIndex': episodeIndex,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastWatchedAtMs': lastWatchedAtMs,
    'posterUrl': posterUrl,
  };
}
