enum YouTubeDownloadFormat { mp3, mp4 }

class YouTubeSearchResult {
  const YouTubeSearchResult({
    required this.videoId,
    required this.title,
    required this.channel,
    this.duration,
    this.thumbnailUrl,
    this.isLive = false,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;
  final String? thumbnailUrl;
  final bool isLive;

  String get videoUrl => 'https://www.youtube.com/watch?v=$videoId';

  static YouTubeSearchResult? tryParse(Map<String, dynamic> renderer) {
    final videoId = renderer['videoId'];
    if (videoId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      return null;
    }

    final title = _runsText(renderer['title']);
    if (title.isEmpty) return null;
    final channel = _runsText(renderer['ownerText']);

    final length = renderer['lengthText'];
    final lengthValue = length is Map ? length['simpleText'] : null;
    final duration = lengthValue is String ? _parseDuration(lengthValue) : null;

    final thumbnail = renderer['thumbnail'];
    final thumbs = thumbnail is Map ? thumbnail['thumbnails'] : null;
    final thumbnailUrl = thumbs is List && thumbs.isNotEmpty
        ? thumbs.last['url'] as String?
        : null;

    return YouTubeSearchResult(
      videoId: videoId,
      title: title,
      channel: channel.isEmpty ? 'YouTube' : channel,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      isLive:
          renderer['isLive'] == true ||
          (lengthValue is! String || lengthValue.isEmpty),
    );
  }

  static String _runsText(Object? node) {
    if (node is! Map) return '';
    final runs = node['runs'];
    if (runs is List) {
      final parts = <String>[];
      for (final run in runs) {
        if (run is Map && run['text'] is String)
          parts.add(run['text'] as String);
      }
      return parts.join().trim();
    }
    final simpleText = node['simpleText'];
    return simpleText is String ? simpleText.trim() : '';
  }

  static Duration? _parseDuration(String value) {
    final parts = value
        .trim()
        .split(':')
        .map((part) => int.tryParse(part.trim()))
        .toList();
    if (parts.isEmpty || parts.any((part) => part == null)) return null;
    final seconds = parts.last!;
    final minutes = parts.length >= 2 ? parts[parts.length - 2]! : 0;
    final hours = parts.length >= 3 ? parts[parts.length - 3]! : 0;
    if (seconds < 0 || minutes < 0 || hours < 0) return null;
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }
}

class YouTubeQuality {
  const YouTubeQuality({
    required this.label,
    required this.height,
    required this.itag,
    required this.codec,
    required this.container,
    required this.bitrateKbps,
    required this.sizeBytes,
  });

  final String label;

  final int height;

  final int itag;
  final String? codec;
  final String container;
  final double bitrateKbps;
  final int sizeBytes;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}
