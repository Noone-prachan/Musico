class YouTubeVideoMetadata {
  const YouTubeVideoMetadata({
    required this.videoId,
    required this.title,
    required this.authorName,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  static final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  final String videoId;
  final String title;
  final String authorName;
  final String videoUrl;
  final String? thumbnailUrl;

  static String parseVideoId(String input) {
    final trimmed = input.trim();
    if (_videoIdPattern.hasMatch(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !{
          'youtube.com',
          'www.youtube.com',
          'm.youtube.com',
          'youtu.be',
        }.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid YouTube video URL or ID.');
    }

    String? id;
    if (uri.host.toLowerCase() == 'youtu.be') {
      id = uri.pathSegments.firstOrNull;
    } else if (uri.path == '/watch') {
      id = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)) {
      id = uri.pathSegments[1];
    }
    if (id == null || !_videoIdPattern.hasMatch(id)) {
      throw const FormatException('Enter a valid YouTube video URL or ID.');
    }
    return id;
  }

  factory YouTubeVideoMetadata.fromOEmbed({
    required String videoId,
    required Map<String, dynamic> json,
  }) {
    final title = json['title'];
    final author = json['author_name'];
    if (title is! String ||
        title.trim().isEmpty ||
        author is! String ||
        author.trim().isEmpty) {
      throw const FormatException(
        'YouTube did not return valid video metadata.',
      );
    }
    final thumbnail = json['thumbnail_url'];
    return YouTubeVideoMetadata(
      videoId: videoId,
      title: title.trim(),
      authorName: author.trim(),
      videoUrl: Uri.https('www.youtube.com', '/watch', {
        'v': videoId,
      }).toString(),
      thumbnailUrl: thumbnail is String ? thumbnail : null,
    );
  }
}
