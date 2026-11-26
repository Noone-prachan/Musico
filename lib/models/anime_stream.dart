library;

class AnimeSearchResult {
  const AnimeSearchResult({
    required this.slug,
    required this.title,
    this.japaneseTitle,
    this.posterUrl,
    this.type,
    this.duration,
    this.episodeCount,
  });

  final String slug;
  final String title;
  final String? japaneseTitle;
  final String? posterUrl;
  final String? type;
  final String? duration;
  final int? episodeCount;

  String get numericId {
    final dash = slug.lastIndexOf('-');
    if (dash < 0 || dash == slug.length - 1) return slug;
    return slug.substring(dash + 1);
  }

  String get subtitleLine {
    final parts = [
      if (type != null && type!.trim().isNotEmpty) type!.trim(),
      if (duration != null && duration!.trim().isNotEmpty) duration!.trim(),
    ];
    return parts.join(' · ');
  }
}

class AnimeEpisode {
  const AnimeEpisode({
    required this.id,
    required this.number,
    this.title,
    this.filler = false,
  });

  final String id;
  final int number;
  final String? title;
  final bool filler;

  String get label => 'Episode $number';
}

class AnimeStreamSource {
  const AnimeStreamSource({
    required this.url,
    required this.referer,
    this.subtitleUrl,
    this.malId,
  });

  final String url;
  final String referer;
  final String? subtitleUrl;
  final int? malId;
}

class AnimeSeasonOption {
  const AnimeSeasonOption({
    required this.title,
    this.year,
    this.format,
    this.coverUrl,
    this.episodeCount,
  });

  final String title;
  final int? year;
  final String? format;
  final String? coverUrl;
  final int? episodeCount;

  String get label {
    final suffix = [
      if (year != null) '$year',
      if (format != null && format != 'TV') format,
    ].join(' · ');
    return suffix.isEmpty ? title : '$title ($suffix)';
  }
}

class AnimeStreamException implements Exception {
  const AnimeStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}
