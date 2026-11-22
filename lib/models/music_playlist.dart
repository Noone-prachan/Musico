class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final int createdAtMs;

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTrackIds = json['trackIds'];
    if (rawTrackIds != null &&
        (rawTrackIds is! List || rawTrackIds.any((id) => id is! String))) {
      throw const FormatException('Playlist track IDs must be a list of text.');
    }

    return MusicPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      trackIds: (rawTrackIds as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet()
          .toList(),
      createdAtMs: json['createdAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'trackIds': trackIds,
    'createdAtMs': createdAtMs,
  };

  MusicPlaylist copyWith({String? name, List<String>? trackIds}) =>
      MusicPlaylist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        createdAtMs: createdAtMs,
      );
}
