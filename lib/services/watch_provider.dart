import '../models/anime_stream.dart';
import '../models/watch_media.dart';

/// Interface every TV / movie streaming source implements.
///
/// Built-in sources (vixsrc) implement this directly, and declarative
/// extensions loaded from disk implement it through the JSON engine, so the
/// rest of the app never needs to know where a stream came from.
abstract class WatchProvider {
  String get id;
  String get name;

  /// One-line note shown in the source picker.
  String get description;

  /// True for providers loaded from an extension file.
  bool get isExtension;

  bool get supportsSeries;

  bool get supportsMovies;

  Future<List<WatchTitle>> search(String query, {required bool series});

  Future<List<WatchEpisode>> episodes(WatchTitle show);

  Future<List<AnimeSeasonOption>> seasons(WatchTitle show);

  Future<AnimeStreamSource> resolveEpisode(
    WatchTitle show,
    WatchEpisode episode,
  );

  Future<AnimeStreamSource> resolveMovie(WatchTitle movie);

  void dispose();
}

/// Registry of installed TV / movie sources.
class WatchProviderRegistry {
  WatchProviderRegistry(List<WatchProvider> providers)
    : _providers = List<WatchProvider>.unmodifiable(providers);

  final List<WatchProvider> _providers;

  List<WatchProvider> get providers => _providers;

  /// Providers that can play [series] content.
  List<WatchProvider> forKind({required bool series}) {
    return [
      for (final provider in _providers)
        if (series ? provider.supportsSeries : provider.supportsMovies) provider,
    ];
  }

  WatchProvider byId(String id) {
    for (final provider in _providers) {
      if (provider.id == id) return provider;
    }
    return _providers.first;
  }

  void dispose() {
    for (final provider in _providers) {
      provider.dispose();
    }
  }
}
