library;

class WatchTitle {
  const WatchTitle({
    required this.imdbId,
    required this.title,
    this.year,
    this.kind = '',
    this.posterUrl,
    this.tmdbId,
  });

  final String imdbId;
  final String title;
  final int? year;

  final String kind;
  final String? posterUrl;

  /// TMDB numeric ID – populated lazily via [TmdbService].
  final int? tmdbId;

  /// Returns a copy with the given [tmdbId] set.
  WatchTitle withTmdbId(int id) => WatchTitle(
        imdbId: imdbId,
        title: title,
        year: year,
        kind: kind,
        posterUrl: posterUrl,
        tmdbId: id,
      );

  bool get isSeries =>
      kind == 'tvSeries' || kind == 'tvMiniSeries' || kind == 'tvShort';

  bool get isMovie => !isSeries;

  String get typeLabel {
    switch (kind) {
      case 'tvSeries':
        return 'TV series';
      case 'tvMiniSeries':
        return 'Mini-series';
      case 'tvMovie':
        return 'TV movie';
      case 'tvShort':
        return 'TV short';
      case 'short':
        return 'Short';
      case 'video':
        return 'Video';
      default:
        return 'Movie';
    }
  }

  String get subtitleLine {
    final parts = [if (year != null) '$year', typeLabel];
    return parts.join(' · ');
  }
}

class WatchEpisode {
  const WatchEpisode({
    required this.season,
    required this.number,
    this.name,
    this.airdate,
  });

  final int season;
  final int number;
  final String? name;
  final String? airdate;

  String get label => 'S$season · E$number';

  String get displayTitle =>
      name == null || name!.trim().isEmpty ? 'Episode $number' : name!.trim();
}

class WatchSeasonPremiere {
  const WatchSeasonPremiere({
    required this.show,
    required this.season,
    required this.episode,
  });

  final WatchTitle show;
  final int season;
  final WatchEpisode episode;
}

class WatchException implements Exception {
  const WatchException(this.message);

  final String message;

  @override
  String toString() => message;
}
