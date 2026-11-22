class MediaTitle {
  const MediaTitle({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.format,
    required this.status,
    required this.season,
    required this.seasonYear,
    required this.genres,
    required this.startDate,
    required this.episodes,
    required this.airings,
  });

  final int id;
  final String title;
  final String? imageUrl;
  final String format;
  final String status;
  final String? season;
  final int? seasonYear;
  final List<String> genres;
  final DateTime? startDate;
  final int? episodes;
  final List<EpisodeAiring> airings;

  EpisodeAiring? get nextAiring {
    final upcoming = airings.where(
      (airing) => airing.airingAt.isAfter(DateTime.now()),
    );
    return upcoming.isEmpty ? null : upcoming.first;
  }

  bool get isMovie => format == 'MOVIE';
  bool get isUpcoming => status == 'NOT_YET_RELEASED';

  factory MediaTitle.fromJson(Map<String, dynamic> json) {
    final titleMap = json['title'] as Map<String, dynamic>? ?? const {};
    final dateMap = json['startDate'] as Map<String, dynamic>? ?? const {};
    final coverMap = json['coverImage'] as Map<String, dynamic>? ?? const {};
    final nextAiring = json['nextAiringEpisode'] as Map<String, dynamic>?;
    final scheduleMap = json['airingSchedule'] as Map<String, dynamic>?;
    final scheduleNodes =
        scheduleMap?['nodes'] as List<dynamic>? ?? const <dynamic>[];
    final airingMaps = [
      ?nextAiring,
      ...scheduleNodes.whereType<Map<String, dynamic>>(),
    ];
    final airings = <EpisodeAiring>[];
    final seenAirings = <String>{};

    for (final airing in airingMaps) {
      final episode = airing['episode'] as int?;
      final timestamp = airing['airingAt'] as int?;
      if (episode == null || timestamp == null) continue;
      final key = '$episode:$timestamp';
      if (seenAirings.add(key)) {
        airings.add(
          EpisodeAiring(
            episode: episode,
            airingAt: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
          ),
        );
      }
    }

    airings.sort((a, b) => a.airingAt.compareTo(b.airingAt));

    final year = dateMap['year'] as int?;
    final month = dateMap['month'] as int?;
    final day = dateMap['day'] as int?;
    final startDate = year == null || month == null || day == null
        ? null
        : DateTime(year, month, day, 9);
    final rawTitle =
        titleMap['english'] as String? ??
        titleMap['romaji'] as String? ??
        titleMap['native'] as String? ??
        'Untitled anime';

    return MediaTitle(
      id: json['id'] as int,
      title: rawTitle,
      imageUrl:
          coverMap['extraLarge'] as String? ??
          coverMap['large'] as String? ??
          coverMap['medium'] as String?,
      format: json['format'] as String? ?? 'UNKNOWN',
      status: json['status'] as String? ?? 'UNKNOWN',
      season: json['season'] as String?,
      seasonYear: json['seasonYear'] as int?,
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      startDate: startDate,
      episodes: json['episodes'] as int?,
      airings: airings,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'imageUrl': imageUrl,
    'format': format,
    'status': status,
    'season': season,
    'seasonYear': seasonYear,
    'genres': genres,
    'startDate': startDate?.millisecondsSinceEpoch,
    'episodes': episodes,
    'airings': airings.map((airing) => airing.toJson()).toList(),
  };

  factory MediaTitle.fromStoredJson(Map<String, dynamic> json) {
    return MediaTitle(
      id: json['id'] as int,
      title: json['title'] as String? ?? 'Untitled anime',
      imageUrl: json['imageUrl'] as String?,
      format: json['format'] as String? ?? 'UNKNOWN',
      status: json['status'] as String? ?? 'UNKNOWN',
      season: json['season'] as String?,
      seasonYear: json['seasonYear'] as int?,
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      startDate: json['startDate'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['startDate'] as int)
          : null,
      episodes: json['episodes'] as int?,
      airings: (json['airings'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EpisodeAiring.fromJson)
          .toList(),
    );
  }
}

class EpisodeAiring {
  const EpisodeAiring({required this.episode, required this.airingAt});

  final int episode;
  final DateTime airingAt;

  Map<String, dynamic> toJson() => {
    'episode': episode,
    'airingAt': airingAt.millisecondsSinceEpoch,
  };

  factory EpisodeAiring.fromJson(Map<String, dynamic> json) {
    return EpisodeAiring(
      episode: json['episode'] as int,
      airingAt: DateTime.fromMillisecondsSinceEpoch(json['airingAt'] as int),
    );
  }
}
