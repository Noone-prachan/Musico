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
  });

  final String id;
  final String title;
  final String path;
  final int addedAtMs;
  final int byteSize;
  final String? rights;
  final String? attribution;
  final String? sourceUrl;

  factory VideoTrack.fromJson(Map<String, dynamic> json) => VideoTrack(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled video',
    path: json['path'] as String,
    addedAtMs: json['addedAtMs'] as int? ?? 0,
    byteSize: json['byteSize'] as int? ?? 0,
    rights: json['rights'] as String?,
    attribution: json['attribution'] as String?,
    sourceUrl: json['sourceUrl'] as String?,
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
  };
}
