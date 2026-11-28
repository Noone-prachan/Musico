import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anime_provider.dart';
import 'anime_stream_service.dart';
import 'extension_loader.dart';
import 'watch_provider.dart';
import 'watch_service.dart';

/// Every streaming source the app knows about: built-in providers plus the
/// declarative extensions found on disk, with the user's chosen source per
/// category remembered between launches.
class StreamingCatalog extends ChangeNotifier {
  StreamingCatalog._();

  static final StreamingCatalog instance = StreamingCatalog._();

  static const _animeKey = 'musico.stream.provider.anime.v1';
  static const _tvKey = 'musico.stream.provider.tv.v1';
  static const _movieKey = 'musico.stream.provider.movie.v1';

  final AnimeProviderRegistry _builtInAnime = AnimeProviderRegistry([
    AnimeStreamService(),
  ]);
  final WatchProviderRegistry _builtInWatch = WatchProviderRegistry([
    WatchService(),
  ]);

  LoadedExtensions _extensions = LoadedExtensions.empty;
  bool _initialized = false;
  bool _loading = false;
  String? _lastError;
  String? _animeId;
  String? _tvId;
  String? _movieId;
  SharedPreferences? _prefs;

  bool get isInitialized => _initialized;
  bool get isLoading => _loading;
  String? get lastError => _lastError;
  LoadedExtensions get extensions => _extensions;

  List<String> get extensionDirectories => _extensions.directories;

  List<AnimeProvider> get animeProviders => [
    ..._builtInAnime.providers,
    ..._extensions.animeProviders,
  ];

  List<WatchProvider> get watchProviders => [
    ..._builtInWatch.providers,
    ..._extensions.watchProviders,
  ];

  List<WatchProvider> watchProvidersFor({required bool series}) => [
    for (final provider in watchProviders)
      if (series ? provider.supportsSeries : provider.supportsMovies) provider,
  ];

  /// Provider currently used by the anime tab.
  AnimeProvider get animeProvider {
    final providers = animeProviders;
    for (final provider in providers) {
      if (provider.id == _animeId) return provider;
    }
    return providers.first;
  }

  /// Provider currently used by the TV or movie tab.
  WatchProvider watchProviderFor({required bool series}) {
    final providers = watchProvidersFor(series: series);
    final wanted = series ? _tvId : _movieId;
    for (final provider in providers) {
      if (provider.id == wanted) return provider;
    }
    return providers.first;
  }

  Future<void> initialize() async {
    if (_initialized || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      _prefs = await SharedPreferences.getInstance();
    } on Object {
      _prefs = null;
    }
    _animeId = _prefs?.getString(_animeKey);
    _tvId = _prefs?.getString(_tvKey);
    _movieId = _prefs?.getString(_movieKey);
    await _loadExtensions();
    _initialized = true;
    _loading = false;
    notifyListeners();
  }

  /// Re-reads the extensions folder without restarting the app.
  Future<void> reload() async {
    _loading = true;
    notifyListeners();
    await _loadExtensions();
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadExtensions() async {
    try {
      await ExtensionLoader.ensureExampleFile();
      _extensions = await ExtensionLoader().load();
      _lastError = null;
    } on Object catch (error) {
      _extensions = LoadedExtensions.empty;
      _lastError = 'Extensions could not be loaded: $error';
      debugPrint(_lastError);
    }
  }

  Future<void> selectAnime(String id) async {
    if (_animeId == id) return;
    _animeId = id;
    notifyListeners();
    await _prefs?.setString(_animeKey, id);
  }

  Future<void> selectWatch(String id, {required bool series}) async {
    if (series) {
      if (_tvId == id) return;
      _tvId = id;
      notifyListeners();
      await _prefs?.setString(_tvKey, id);
    } else {
      if (_movieId == id) return;
      _movieId = id;
      notifyListeners();
      await _prefs?.setString(_movieKey, id);
    }
  }

  /// Opens the user extensions folder in Explorer (Windows-only convenience).
  Future<bool> openExtensionsFolder() async {
    if (!Platform.isWindows) return false;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) return false;
    final path = [appData, 'Musico', 'extensions'].join(
      Platform.pathSeparator,
    );
    try {
      await Directory(path).create(recursive: true);
      await Process.start('explorer.exe', [path], mode: ProcessStartMode.detached);
      return true;
    } on Object catch (error) {
      debugPrint('Extensions folder could not be opened: $error');
      return false;
    }
  }

  @override
  void dispose() {
    _builtInAnime.dispose();
    _builtInWatch.dispose();
    for (final provider in _extensions.animeProviders) {
      provider.dispose();
    }
    for (final provider in _extensions.watchProviders) {
      provider.dispose();
    }
    super.dispose();
  }
}
