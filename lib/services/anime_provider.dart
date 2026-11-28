import '../models/anime_stream.dart';

/// Interface for anime streaming extensions/providers.
///
/// Each provider can expose its own search, episode list, available dub/sub
/// modes, and stream resolution logic.
abstract class AnimeProvider {
  String get id;
  String get name;

  /// One-line note shown in the source picker.
  String get description;

  /// True for providers loaded from an extension file.
  bool get isExtension;

  /// Audio languages this provider can offer, as ISO codes (`ja`, `en`, ...).
  List<String> get supportedLanguages;

  Future<List<AnimeSearchResult>> search(String query);
  Future<List<AnimeEpisode>> episodes(AnimeSearchResult show);
  Future<List<AnimeSeasonOption>> relatedSeasons(String title) async =>
      const [];
  Future<List<String>> availableModes(AnimeEpisode episode);
  Future<AnimeStreamSource> resolveStream(
    AnimeEpisode episode, {
    String mode = 'sub',
  });
  void dispose();
}

/// Registry of installed anime streaming providers.
class AnimeProviderRegistry {
  AnimeProviderRegistry(List<AnimeProvider> providers)
      : _providers = List<AnimeProvider>.unmodifiable(providers);

  final List<AnimeProvider> _providers;

  List<AnimeProvider> get providers => _providers;

  AnimeProvider byId(String id) {
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
