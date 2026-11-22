import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/media_download.dart';
import '../models/media_title.dart';
import '../models/music_playlist.dart';
import '../models/music_track.dart';
import '../models/spotify_playlist.dart';
import '../models/video_track.dart';
import '../models/youtube_download.dart';
import '../models/youtube_media.dart';
import '../models/youtube_video_metadata.dart';
import '../services/backup_service.dart';
import '../services/direct_media_download_service.dart';
import '../services/lyrics_title_matcher.dart';
import '../services/openverse_artwork_service.dart';
import '../services/youtube_download_service.dart';
import '../services/youtube_metadata_service.dart';
import '../services/youtube_search_service.dart';

enum ReleaseCollection { weekly, upcomingSeries, upcomingMovies, search }

enum LyricsStatus { idle, networkRequired, loading, loaded, notFound, error }

class AppState extends ChangeNotifier {
  static const _seasonCacheKey = 'sideb.native.anime.season.v1';
  static const _upcomingCacheKey = 'sideb.native.anime.upcoming.v1';
  static const _watchlistKey = 'sideb.native.watchlist.v1';
  static const _tracksKey = 'sideb.native.tracks.v1';
  static const _videosKey = 'sideb.native.videos.v1';
  static const _spotifyPlaylistsKey = 'sideb.native.spotify.playlists.v1';
  static const _musicPlaylistsKey = 'sideb.native.music.playlists.v1';
  static const _backgroundKey = 'sideb.native.desktop.background-sync.v1';
  static const _notificationPermissionKey = 'sideb.native.notifications.v1';
  static const _sortAlphabeticallyKey = 'sideb.native.music.sort.v1';
  static const _shuffleKey = 'sideb.native.music.shuffle.v1';
  static const _repeatOneKey = 'sideb.native.music.repeat-one.v1';
  static const _autoplayKey = 'sideb.native.music.autoplay.v1';
  static const _volumeKey = 'sideb.native.music.volume.v1';
  static const _mediaStorageRootKey = 'sideb.native.media-storage-root.v1';
  static const _setupCompletedKey = 'sideb.native.setup-completed.v1';
  static const _aniListApi = 'https://graphql.anilist.co';
  static const _backupChannel = MethodChannel('sideb/backup');
  static const _pictureInPictureChannel = MethodChannel(
    'sideb/picture_in_picture',
  );
  static const _windowsMediaControlsChannel = MethodChannel(
    'musico/windows_media_controls',
  );

  static const _mediaFields = '''
    id
    title { english romaji native }
    coverImage { extraLarge large medium }
    genres
    status
    season
    seasonYear
    format
    episodes
    startDate { year month day }
    nextAiringEpisode { episode airingAt timeUntilAiring }
    airingSchedule(notYetAired: true, perPage: 3) {
      nodes { episode airingAt timeUntilAiring }
    }
  ''';

  static const _seasonQuery =
      '''
    query CurrentSeason(\$season: MediaSeason!, \$year: Int!) {
      Page(page: 1, perPage: 50) {
        media(
          type: ANIME,
          season: \$season,
          seasonYear: \$year,
          status: RELEASING,
          sort: POPULARITY_DESC
        ) { $_mediaFields }
      }
    }
  ''';

  static const _upcomingQuery =
      '''
    query UpcomingAnime {
      Page(page: 1, perPage: 30) {
        media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) {
          $_mediaFields
        }
      }
    }
  ''';

  static const _searchQuery =
      '''
    query SearchAnime(\$search: String!) {
      Page(page: 1, perPage: 20) {
        media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
          $_mediaFields
        }
      }
    }
  ''';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer player = AudioPlayer();
  Player? _videoPlayer;
  VideoController? _videoController;
  bool _videoPlayerListenersInitialized = false;

  Player get videoPlayer => _videoPlayer ??= Player();
  VideoController get videoController =>
      _videoController ??= VideoController(videoPlayer);
  final Connectivity _connectivity = Connectivity();
  final http.Client _client = http.Client();
  final MusicoBackupService _backupService = MusicoBackupService();
  late final DirectMediaDownloadService _directDownloadService =
      DirectMediaDownloadService(_client);
  late final YouTubeMetadataService _youtubeMetadataService =
      YouTubeMetadataService(_client);
  late final YouTubeSearchService _youtubeSearchService = YouTubeSearchService(
    _client,
  );
  late final YouTubeDownloadService _youtubeDownloadService =
      YouTubeDownloadService();
  late final OpenverseArtworkService _artworkService = OpenverseArtworkService(
    _client,
  );

  List<MusicTrack> tracks = [];
  List<MediaTitle> seasonTitles = [];
  List<MediaTitle> upcomingTitles = [];
  List<MediaTitle> searchResults = [];
  List<MediaTitle> watchlist = [];
  List<SpotifyPlaylist> spotifyPlaylists = [];
  List<MusicPlaylist> musicPlaylists = [];
  String? selectedMusicPlaylistId;
  final Set<String> artworkLookupsInProgress = {};
  final Set<String> artworkLookupAttempts = {};
  final Map<String, String> artworkErrors = {};
  List<VideoTrack> videoTracks = [];
  Set<int> downloadingIds = {};
  Map<int, double> downloadProgress = {};
  Set<String> notifiedAiringKeys = {};

  MusicTrack? currentTrack;
  VideoTrack? currentVideo;
  ReleaseCollection releaseCollection = ReleaseCollection.weekly;
  DateTime selectedDate = _dayStart(DateTime.now());
  String searchQuery = '';
  String trackQuery = '';
  String? errorMessage;
  String? musicErrorMessage;
  String? commonsSearchError;
  String? commonsEmptyMessage;
  String commonsQuery = '';
  String? mediaDownloadConfigPath;
  String? mediaDownloadErrorMessage;
  String? configuredDownloadErrorMessage;
  String? spotifyPlaylistImportErrorMessage;
  final Map<String, double?> configuredDownloadProgress = {};
  Set<String> downloadingConfiguredIds = {};
  final Map<String, double?> youtubeDownloadProgress = {};
  Set<String> downloadingYouTubeIds = {};
  String? youtubeDownloadError;
  String? settingsErrorMessage;
  String? backupMessage;
  String? backupErrorMessage;
  String? lyrics;
  String? lyricsErrorMessage;
  String? videoErrorMessage;
  LyricsStatus lyricsStatus = LyricsStatus.idle;
  bool isSearchingMusic = false;
  bool hasSearchedCommons = false;
  bool isImportingVideos = false;
  bool isCreatingBackup = false;
  bool isRestoringBackup = false;
  bool isWifiConnected = false;
  bool hasNetworkConnection = false;
  bool isLoadingSchedule = false;
  bool isSearching = false;
  bool notificationsEnabled = false;
  bool notificationsAvailable = false;
  bool backgroundAutoRefresh = false;
  bool isOnline = true;
  bool sortAlphabetically = false;
  bool shuffle = false;
  bool repeatOne = false;
  bool autoplay = true;
  double volume = 0.8;
  Timer? _desktopRefreshTimer;
  Timer? _notificationTimer;
  Timer? _volumePersistTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<void> _windowsMediaControlsUpdateQueue = Future<void>.value();
  bool _windowsMediaControlsPublished = false;
  bool _notificationsInitialized = false;
  bool _isDisposed = false;
  DateTime? _lyricsRetryAfter;
  MediaDownloadConfig? mediaDownloadConfig;
  String? mediaStorageRoot;
  bool setupCompleted = false;

  bool get supportsDesktopBackgroundRefresh =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get isPlaying => player.playing;

  bool get isPlayingVideo => _videoPlayer?.state.playing ?? false;

  Duration get duration => player.duration ?? Duration.zero;

  static const musicSuggestions = [
    'piano',
    'ambient',
    'jazz',
    'lo-fi',
    'classical',
    'acoustic guitar',
    'soundtrack',
    'nature sounds',
  ];

  List<MusicResult> commonsResults = [];
  List<YouTubeSearchResult> youtubeSearchResults = [];
  String youtubeSearchQuery = '';
  bool isSearchingYouTube = false;
  bool hasSearchedYouTube = false;
  String? youtubeSearchError;

  List<MusicTrack> get visibleTracks {
    final query = trackQuery.trim().toLowerCase();
    final selectedPlaylist = musicPlaylists
        .where((playlist) => playlist.id == selectedMusicPlaylistId)
        .firstOrNull;
    final playlistTrackIds = selectedPlaylist?.trackIds.toSet();
    final filtered = tracks.where((track) {
      if (playlistTrackIds != null && !playlistTrackIds.contains(track.id)) {
        return false;
      }
      final metadata = track.displayMetadata;
      return query.isEmpty ||
          '${metadata.title} ${metadata.artist} ${track.license ?? ""}'
              .toLowerCase()
              .contains(query);
    }).toList();
    filtered.sort(
      (a, b) => sortAlphabetically
          ? a.displayMetadata.title.toLowerCase().compareTo(
              b.displayMetadata.title.toLowerCase(),
            )
          : b.addedAtMs.compareTo(a.addedAtMs),
    );
    return filtered;
  }

  List<MediaTitle> get visibleReleaseTitles {
    if (isUpcomingCollection) {
      final movies = releaseCollection == ReleaseCollection.upcomingMovies;
      return _applyTitleSearch(
        upcomingTitles.where((media) => media.isMovie == movies).toList(),
      );
    }
    if (releaseCollection == ReleaseCollection.search) {
      return searchResults;
    }
    final date = _dayStart(selectedDate);
    final scheduled = <({MediaTitle media, EpisodeAiring airing})>[];
    for (final media in seasonTitles) {
      for (final airing in media.airings) {
        if (_dayStart(airing.airingAt) == date) {
          scheduled.add((media: media, airing: airing));
        }
      }
    }
    scheduled.sort((a, b) => a.airing.airingAt.compareTo(b.airing.airingAt));
    return _applyTitleSearch(scheduled.map((entry) => entry.media).toList());
  }

  bool get isUpcomingCollection =>
      releaseCollection == ReleaseCollection.upcomingSeries ||
      releaseCollection == ReleaseCollection.upcomingMovies;

  List<MediaTitle> get visibleWatchlist => _applyTitleSearch(watchlist);

  static DateTime _dayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<MediaTitle> _applyTitleSearch(List<MediaTitle> items) {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where((title) => title.title.toLowerCase().contains(query))
        .toList();
  }

  Future<void> initialize() async {
    isOnline = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      watchlist = _decodeMediaList(preferences.getString(_watchlistKey));
      tracks = _decodeTrackList(preferences.getString(_tracksKey));
      videoTracks = _decodeVideoList(preferences.getString(_videosKey));
      spotifyPlaylists = _decodeSpotifyPlaylistList(
        preferences.getString(_spotifyPlaylistsKey),
      );
      final savedMusicPlaylists = _decodeMusicPlaylistState(
        preferences.getString(_musicPlaylistsKey),
      );
      musicPlaylists = savedMusicPlaylists.playlists;
      selectedMusicPlaylistId = savedMusicPlaylists.selectedId;
      backgroundAutoRefresh = preferences.getBool(_backgroundKey) ?? false;
      notificationsEnabled =
          preferences.getBool(_notificationPermissionKey) ?? false;
      sortAlphabetically = preferences.getBool(_sortAlphabeticallyKey) ?? false;
      shuffle = preferences.getBool(_shuffleKey) ?? false;
      repeatOne = preferences.getBool(_repeatOneKey) ?? false;
      autoplay = preferences.getBool(_autoplayKey) ?? true;
      final savedMediaStorageRoot = preferences.getString(_mediaStorageRootKey);
      setupCompleted = preferences.getBool(_setupCompletedKey) ?? false;
      if (savedMediaStorageRoot != null &&
          savedMediaStorageRoot.trim().isNotEmpty) {
        mediaStorageRoot = savedMediaStorageRoot;
      }
      volume = (preferences.getDouble(_volumeKey) ?? 0.8)
          .clamp(0, 1)
          .toDouble();
    } catch (error, stackTrace) {
      debugPrint('Could not load the Musico library: $error\n$stackTrace');
      musicErrorMessage = 'Your saved library could not be loaded.';
    }

    try {
      await _loadMediaDownloadConfig();
    } on Object catch (error, stackTrace) {
      debugPrint('Direct media links could not be loaded: $error\n$stackTrace');
      mediaDownloadErrorMessage =
          'The download links file could not be loaded. Check its JSON format.';
    }

    await _initializeAudio();
    await _initializeConnectivity();
    unawaited(_lookupMissingTrackArtwork());
    if (Platform.isWindows) {
      notificationsEnabled = false;
      notificationsAvailable = false;
    } else {
      await _initializeNotifications();
    }
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkBackgroundAiringNotifications(),
    );
    if (supportsDesktopBackgroundRefresh && backgroundAutoRefresh) {
      _startDesktopRefresh();
    }
    await refreshAnime(silent: true, initialLoad: true);
    if (notificationsEnabled && _notificationsInitialized) {
      await syncWatchlistNotifications();
    }
    _notify();
  }

  Future<void> _initializeAudio() async {
    player.playerStateStream.listen((_) => _notify());
    player.playingStream.listen((_) => _scheduleWindowsMediaControlsSync());
    player.durationStream.listen((duration) {
      final track = currentTrack;
      if (track != null && duration != null && track.durationMs == 0) {
        currentTrack = track.copyWith(durationMs: duration.inMilliseconds);
        _persistTracks();
      }
      _notify();
    });
    player.positionStream.listen((_) => _notify());
    player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed &&
          (autoplay || repeatOne)) {
        unawaited(_playNext(automatic: true));
      }
    });
  }

  Future<void> _initializeConnectivity() async {
    try {
      _setConnectivity(await _connectivity.checkConnectivity());
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _setConnectivity,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Network state monitoring failed: $error\n$stackTrace');
          isWifiConnected = false;
          hasNetworkConnection = false;
          if (currentTrack != null || currentVideo != null) {
            lyricsStatus = LyricsStatus.networkRequired;
          }
          _notify();
        },
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Network state could not be read: $error\n$stackTrace');
      isWifiConnected = false;
      hasNetworkConnection = false;
    }
  }

  void _setConnectivity(List<ConnectivityResult> results) {
    final wasOnline = isOnline;
    isWifiConnected = results.contains(ConnectivityResult.wifi);
    hasNetworkConnection = results.any(
      (result) => result != ConnectivityResult.none,
    );
    isOnline = hasNetworkConnection;
    if (hasNetworkConnection &&
        !wasOnline &&
        (currentTrack != null || currentVideo != null)) {
      unawaited(fetchLyricsForCurrent());
    }
    if (isOnline && !wasOnline) {
      unawaited(refreshAnime(silent: true));
      unawaited(_lookupMissingTrackArtwork());
    }
    if (!hasNetworkConnection && lyricsStatus == LyricsStatus.loading) {
      lyricsStatus = LyricsStatus.networkRequired;
    }
    _notify();
  }

  void _initializeVideoPlayer() {
    if (_videoPlayerListenersInitialized) return;
    final videoPlayer = this.videoPlayer;
    videoPlayer.stream.playing.listen((_) => _notify());
    videoPlayer.stream.position.listen((_) => _notify());
    videoPlayer.stream.error.listen((message) {
      debugPrint('Video playback failed: $message');
      videoErrorMessage = 'This video could not be played on this device.';
      _notify();
    });
    _videoPlayerListenersInitialized = true;
  }

  Future<void> _initializeNotifications() async {
    tz_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(
        tz.getLocation(_canonicalTimeZone(localTimezone.identifier)),
      );
      final settings = InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Musico',
          appUserModelId: 'app.sideb.side_b',
          guid: '35dc883d-c849-42c6-a2fc-6ca87424d30e',
        ),
      );
      await _notifications.initialize(settings: settings);
      notificationsAvailable = true;
      _notificationsInitialized = true;
    } catch (error, stackTrace) {
      debugPrint(
        'Airing notifications could not be initialized: $error\n$stackTrace',
      );
      errorMessage = 'Airing notifications are unavailable on this device. Check app permissions.';
    }
  }

  /// Older IANA aliases are dropped from recent timezone databases.
  static String _canonicalTimeZone(String identifier) {
    const aliases = <String, String>{
      'Asia/Katmandu': 'Asia/Kathmandu',
      'Asia/Calcutta': 'Asia/Kolkata',
      'Asia/Rangoon': 'Asia/Yangon',
      'Asia/Saigon': 'Asia/Ho_Chi_Minh',
      'Europe/Kiev': 'Europe/Kyiv',
      'US/Eastern': 'America/New_York',
      'US/Central': 'America/Chicago',
      'US/Mountain': 'America/Denver',
      'US/Pacific': 'America/Los_Angeles',
    };
    final canonical = aliases[identifier] ?? identifier;
    try {
      tz.getLocation(canonical);
      return canonical;
    } on Object {
      return 'UTC';
    }
  }

  List<MusicTrack> _decodeTrackList(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .where((track) => File(track.path).existsSync())
          .toList();
    } on FormatException catch (error) {
      debugPrint('Saved music metadata is invalid: $error');
      return [];
    } on TypeError catch (error) {
      debugPrint('Saved music metadata has unexpected types: $error');
      return [];
    }
  }

  List<VideoTrack> _decodeVideoList(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(VideoTrack.fromJson)
          .where((video) => File(video.path).existsSync())
          .toList();
    } on FormatException catch (error) {
      debugPrint('Saved video metadata is invalid: $error');
      return [];
    } on TypeError catch (error) {
      debugPrint('Saved video metadata has unexpected types: $error');
      return [];
    }
  }

  ({List<MusicPlaylist> playlists, String? selectedId})
  _decodeMusicPlaylistState(String? json) {
    if (json == null) return (playlists: [], selectedId: null);
    try {
      final payload = jsonDecode(json);
      if (payload is! Map<String, dynamic> || payload['playlists'] is! List) {
        throw const FormatException('The saved playlist list is invalid.');
      }
      final playlists = [
        for (final value in payload['playlists'] as List<dynamic>)
          if (value is Map<String, dynamic>) MusicPlaylist.fromJson(value),
      ];
      final selectedId = payload['selectedId'];
      if (selectedId != null && selectedId is! String) {
        throw const FormatException('The selected playlist ID is invalid.');
      }
      return (
        playlists: playlists,
        selectedId: playlists.any((playlist) => playlist.id == selectedId)
            ? selectedId as String?
            : null,
      );
    } on FormatException catch (error) {
      debugPrint('Saved music playlists are invalid: $error');
      return (playlists: [], selectedId: null);
    } on TypeError catch (error) {
      debugPrint('Saved music playlists have unexpected types: $error');
      return (playlists: [], selectedId: null);
    }
  }

  List<SpotifyPlaylist> _decodeSpotifyPlaylistList(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(SpotifyPlaylist.fromJson)
          .toList();
    } on FormatException catch (error) {
      debugPrint('Saved Spotify playlist metadata is invalid: $error');
      return [];
    } on TypeError catch (error) {
      debugPrint(
        'Saved Spotify playlist metadata has unexpected types: $error',
      );
      return [];
    }
  }

  List<MediaTitle> _decodeMediaList(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(MediaTitle.fromStoredJson)
          .toList();
    } on FormatException catch (error) {
      debugPrint('Saved anime metadata is invalid: $error');
      return [];
    } on TypeError catch (error) {
      debugPrint('Saved anime metadata has unexpected types: $error');
      return [];
    }
  }

  Future<void> pickAudioFiles() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.audio);
      if (result.isEmpty) return;
      final directory = await _libraryDirectory();
      var imported = 0;
      for (final file in result) {
        final destination = await _copyPickedAudio(file, directory);
        final fileName = _basename(file.name);
        final pieces = _parseTrackName(fileName);
        tracks.add(
          MusicTrack(
            id: 'import-${DateTime.now().microsecondsSinceEpoch}-$imported',
            title: pieces.title,
            artist: pieces.artist,
            path: destination.path,
            durationMs: 0,
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
            license: null,
            licenseUrl: null,
            sourceUrl: null,
            commonsPageId: null,
            byteSize: await destination.length(),
          ),
        );
        imported++;
      }

      await _persistTracks();
      musicErrorMessage = null;
      unawaited(_lookupMissingTrackArtwork());
      _notify();
    } on PlatformException catch (error, stackTrace) {
      debugPrint('The audio picker could not be opened: $error\n$stackTrace');
      musicErrorMessage = 'The audio picker could not be opened.';
      _notify();
    } on FileSystemException catch (error, stackTrace) {
      debugPrint(
        'Audio could not be saved to this device: $error\n$stackTrace',
      );
      musicErrorMessage =
          'Audio could not be saved. Check available device storage.';
      _notify();
    } catch (error, stackTrace) {
      debugPrint('Audio import failed: $error\n$stackTrace');
      musicErrorMessage =
          'Audio could not be imported. Try another audio file.';
      _notify();
    }
  }

  Future<int?> importSpotifyPlaylistMetadata() async {
    spotifyPlaylistImportErrorMessage = null;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return null;
      final picked = files.first;
      if (await picked.xFile.length() > SpotifyPlaylist.maxFileSize) {
        throw const FormatException(
          'The Spotify export exceeds the 10 MB limit.',
        );
      }
      final imported = SpotifyPlaylist.decodeExport(
        await picked.xFile.readAsString(),
      );
      final byId = {
        for (final playlist in spotifyPlaylists) playlist.id: playlist,
        for (final playlist in imported) playlist.id: playlist,
      };
      final updated = byId.values.toList();
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _spotifyPlaylistsKey,
        jsonEncode(updated.map((playlist) => playlist.toJson()).toList()),
      );
      if (!saved) throw StateError('The playlist metadata was not saved.');
      spotifyPlaylists = updated;
      _notify();
      return imported.length;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Spotify playlist metadata could not be imported: $error\n$stackTrace',
      );
      spotifyPlaylistImportErrorMessage = error is FormatException
          ? error.message
          : 'Spotify playlist metadata could not be imported.';
      _notify();
      return 0;
    }
  }

  Future<YouTubeVideoMetadata> lookupYouTubeMetadata(String input) =>
      _youtubeMetadataService.lookup(input);

  Future<void> searchYouTube(String rawQuery) async {
    final query = rawQuery.trim();
    youtubeSearchQuery = query;
    if (query.isEmpty) {
      youtubeSearchResults = [];
      youtubeSearchError = null;
      isSearchingYouTube = false;
      _notify();
      return;
    }
    isSearchingYouTube = true;
    hasSearchedYouTube = true;
    youtubeSearchError = null;
    youtubeSearchResults = [];
    _notify();
    try {
      final results = await _youtubeSearchService.search(query);
      youtubeSearchResults = results;
      if (results.isEmpty) {
        youtubeSearchError = 'No videos matched that search.';
      }
    } on Object catch (error, stackTrace) {
      debugPrint('YouTube search failed: $error\n$stackTrace');
      youtubeSearchError = _youtubeUserMessage(error);
    } finally {
      isSearchingYouTube = false;
      _notify();
    }
  }

  Future<List<YouTubeQuality>> youtubeQualities(String videoId) =>
      _youtubeDownloadService.availableQualities(videoId);

  bool isYouTubeSaved(String videoId, YouTubeDownloadFormat format) {
    final id = format == YouTubeDownloadFormat.mp3
        ? 'youtube-$videoId'
        : 'youtube-video-$videoId';
    return format == YouTubeDownloadFormat.mp3
        ? tracks.any((track) => track.id == id)
        : videoTracks.any((video) => video.id == id);
  }

  Future<bool> downloadYouTube({
    required YouTubeSearchResult result,
    required YouTubeDownloadFormat format,
    required String requestedName,
    String? qualityLabel,
  }) async {
    if (result.isLive) {
      youtubeDownloadError =
          'Live streams cannot be downloaded. Pick a regular video.';
      _notify();
      return false;
    }
    final key = '${result.videoId}:${format.name}:${qualityLabel ?? 'audio'}';
    if (downloadingYouTubeIds.contains(key)) return false;
    downloadingYouTubeIds = {...downloadingYouTubeIds, key};
    youtubeDownloadProgress[key] = 0;
    youtubeDownloadError = null;
    _notify();

    final trackId = format == YouTubeDownloadFormat.mp3
        ? 'youtube-${result.videoId}'
        : 'youtube-video-${result.videoId}';
    var registered = false;
    YouTubeDownloadOutcome? outcome;
    try {
      final mediaDirectory = await _mediaStorageDirectory(
        format == YouTubeDownloadFormat.mp3 ? 'music' : 'videos',
      );
      final artworkDirectory = await _mediaStorageDirectory('artwork');
      final title = requestedName.trim().isEmpty
          ? result.title
          : requestedName.trim();
      final artist = result.channel;

      String? chosenQuality;
      if (format == YouTubeDownloadFormat.mp4) {
        final qualities = await _youtubeDownloadService.availableQualities(
          result.videoId,
        );
        chosenQuality =
            qualityLabel ??
            (qualities.isNotEmpty ? qualities.first.label : null);
        if (chosenQuality == null) {
          throw const FormatException(
            'No downloadable video quality is available for this video.',
          );
        }
      }

      final ripRequest = YouTubeRipRequest(
        videoId: result.videoId,
        videoUrl: result.videoUrl,
        requestedName: title,
        originalTitle: result.title,
        channel: artist,
        format: format,
        quality: chosenQuality,
        durationMs: result.duration?.inMilliseconds,
        thumbnailUrl: result.thumbnailUrl,
      );

      if (format == YouTubeDownloadFormat.mp3) {
        outcome = await _youtubeDownloadService.downloadAudio(
          request: ripRequest,
          directory: mediaDirectory,
          artworkDirectory: artworkDirectory,
          onProgress: (progress) {
            youtubeDownloadProgress[key] = progress;
            _notify();
          },
        );
      } else {
        outcome = await _youtubeDownloadService.downloadVideo(
          request: ripRequest,
          directory: mediaDirectory,
          artworkDirectory: artworkDirectory,
          onProgress: (progress) {
            youtubeDownloadProgress[key] = progress;
            _notify();
          },
        );
      }

      final savedAt = DateTime.now().millisecondsSinceEpoch;
      if (format == YouTubeDownloadFormat.mp3) {
        final artworkPath = outcome.artwork?.path;
        tracks = [
          MusicTrack(
            id: trackId,
            title: title,
            artist: artist,
            path: outcome.file.path,
            durationMs: result.duration?.inMilliseconds ?? 0,
            addedAtMs: savedAt,
            license: 'YouTube download',
            licenseUrl: null,
            sourceUrl: result.videoUrl,
            commonsPageId: null,
            byteSize: outcome.byteSize,
            attribution: artist,
            artworkPath: artworkPath,
            artworkTitle: artworkPath != null ? title : null,
            artworkCreator: artworkPath != null ? artist : null,
            artworkLicense: artworkPath != null ? 'YouTube thumbnail' : null,
            artworkAttribution: artworkPath != null ? artist : null,
            artworkLicenseUrl: artworkPath != null ? result.videoUrl : null,
            artworkSourceUrl: artworkPath != null ? result.videoUrl : null,
          ),
          ...tracks,
        ];
        registered = true;
        await _persistTracks();
      } else {
        videoTracks.insert(
          0,
          VideoTrack(
            id: trackId,
            title: title,
            path: outcome.file.path,
            addedAtMs: savedAt,
            byteSize: outcome.byteSize,
            rights: 'YouTube download',
            attribution: artist,
            sourceUrl: result.videoUrl,
          ),
        );
        registered = true;
        await _persistVideos();
      }
      youtubeDownloadError = null;
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'YouTube download failed for ${result.videoId}: $error\n$stackTrace',
      );
      if (registered) {
        tracks = tracks.where((track) => track.id != trackId).toList();
        videoTracks = videoTracks
            .where((video) => video.id != trackId)
            .toList();
        try {
          if (format == YouTubeDownloadFormat.mp3) {
            await _persistTracks();
          } else {
            await _persistVideos();
          }
        } on Object catch (persistError, persistStackTrace) {
          debugPrint(
            'The failed YouTube download could not be rolled back: '
            '$persistError\n$persistStackTrace',
          );
        }
        registered = false;
      }
      youtubeDownloadError = _youtubeUserMessage(error);
      return false;
    } finally {
      if (!registered && outcome != null) {
        try {
          if (await outcome.file.exists()) await outcome.file.delete();
          if (await outcome.metadataFile.exists()) {
            await outcome.metadataFile.delete();
          }
          if (outcome.artwork != null && await outcome.artwork!.exists()) {
            await outcome.artwork!.delete();
          }
        } on FileSystemException catch (error, stackTrace) {
          debugPrint(
            'Incomplete YouTube download could not be removed: $error\n$stackTrace',
          );
        }
      }
      downloadingYouTubeIds = {...downloadingYouTubeIds}..remove(key);
      youtubeDownloadProgress.remove(key);
      _notify();
    }
  }

  static String _youtubeUserMessage(Object error) {
    if (error is HttpException) return error.message;
    if (error is FormatException) return error.message;
    if (error is ProcessException) {
      return 'yt-dlp could not run: ${error.message} '
          '(exit ${error.errorCode}).';
    }
    if (error is FileSystemException) {
      final path = error.path == null || error.path!.isEmpty
          ? ''
          : ' Path: ${error.path}.';
      final osError = error.osError != null ? ' (${error.osError})' : '';
      return 'The download could not be written.$path ${error.message}$osError';
    }
    if (error is TimeoutException) {
      return 'YouTube took too long to respond. Check your connection and retry.';
    }
    if (error is SocketException) {
      return 'YouTube could not be reached. Check mobile data or Wi-Fi, then retry.';
    }
    if (error is http.ClientException) {
      return 'YouTube could not be reached. Check the network connection and retry.';
    }
    return 'YouTube could not be reached. Check your connection and retry.';
  }

  Future<Directory> _libraryDirectory() async {
    return _mediaStorageDirectory('music');
  }

  Future<Directory> _mediaStorageDirectory(String category) async {
    final userProfile = Platform.environment['USERPROFILE'];
    final localAppData = Platform.environment['LOCALAPPDATA'];

    if (Platform.isWindows) {
      final candidates = <Directory>[];

      // 1. If user configured a storage root, check if writable first
      if (mediaStorageRoot != null && mediaStorageRoot!.trim().isNotEmpty) {
        final selectedRoot = Directory(mediaStorageRoot!.trim());
        candidates.add(
          Directory('${selectedRoot.path}${Platform.pathSeparator}$category'),
        );
        candidates.add(selectedRoot);
      }

      // 2. User Music and Downloads folders
      if (userProfile != null && userProfile.isNotEmpty) {
        candidates.add(
          Directory(
            '$userProfile${Platform.pathSeparator}Music${Platform.pathSeparator}Musico${Platform.pathSeparator}$category',
          ),
        );
        candidates.add(
          Directory(
            '$userProfile${Platform.pathSeparator}Music${Platform.pathSeparator}Musico',
          ),
        );
        candidates.add(
          Directory(
            '$userProfile${Platform.pathSeparator}Downloads${Platform.pathSeparator}Musico${Platform.pathSeparator}$category',
          ),
        );
        candidates.add(
          Directory(
            '$userProfile${Platform.pathSeparator}Downloads${Platform.pathSeparator}Musico',
          ),
        );
      }

      // 3. Application directory fallback
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      candidates.add(
        Directory(
          '${executableDirectory.path}${Platform.pathSeparator}MusicoDownloads${Platform.pathSeparator}$category',
        ),
      );
      candidates.add(
        Directory(
          '${executableDirectory.path}${Platform.pathSeparator}MusicoDownloads',
        ),
      );

      // 4. LocalAppData/Musico
      if (localAppData != null && localAppData.isNotEmpty) {
        candidates.add(
          Directory(
            '$localAppData${Platform.pathSeparator}Musico${Platform.pathSeparator}$category',
          ),
        );
        candidates.add(
          Directory('$localAppData${Platform.pathSeparator}Musico'),
        );
      }

      // 5. System temp fallback
      final tempRoot = Directory.systemTemp.path;
      candidates.add(
        Directory(
          '$tempRoot${Platform.pathSeparator}Musico${Platform.pathSeparator}$category',
        ),
      );
      candidates.add(Directory('$tempRoot${Platform.pathSeparator}Musico'));

      for (final dir in candidates) {
        if (await _createWritableDirectory(dir)) {
          return dir;
        }
      }

      throw FileSystemException(
        'No writable Musico storage folder was found on this Windows device.',
        candidates.first.path,
      );
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}$category',
    );
    if (await _createWritableDirectory(directory)) return directory;

    final temp = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}Musico${Platform.pathSeparator}$category',
    );
    if (await _createWritableDirectory(temp)) return temp;

    throw FileSystemException(
      'No writable Musico storage folder was found.',
      directory.path,
    );
  }

  Future<String> recommendedMediaStorageRoot() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final music =
            '$userProfile${Platform.pathSeparator}Music${Platform.pathSeparator}Musico';
        if (await _createWritableDirectory(Directory(music))) {
          return music;
        }
        final downloads =
            '$userProfile${Platform.pathSeparator}Downloads${Platform.pathSeparator}Musico';
        if (await _createWritableDirectory(Directory(downloads))) {
          return downloads;
        }
      }
      final appDir = File(Platform.resolvedExecutable).parent.path;
      return '$appDir${Platform.pathSeparator}MusicoDownloads';
    }
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}Musico';
  }

  Future<bool> setMediaStorageRoot(String root) async {
    final directory = Directory(root);
    if (!await _createWritableDirectory(directory)) {
      settingsErrorMessage =
          'That folder is not writable. Choose another storage location.';
      _notify();
      return false;
    }
    mediaStorageRoot = root;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_mediaStorageRootKey, root);
    if (!saved) {
      settingsErrorMessage =
          'The storage location could not be saved. Try again.';
      _notify();
      return false;
    }
    settingsErrorMessage = null;
    _notify();
    return true;
  }

  Future<void> completeSetup() async {
    setupCompleted = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_setupCompletedKey, true);
    _notify();
  }

  Future<bool> _createWritableDirectory(Directory directory) async {
    Directory? probeDirectory;
    try {
      await directory.create(recursive: true);
      probeDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        '.musico-write-test-${DateTime.now().microsecondsSinceEpoch}',
      );
      await probeDirectory.create();
      final probe = File(
        '${probeDirectory.path}${Platform.pathSeparator}write-test',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      await probeDirectory.delete();
      return true;
    } on Object catch (error) {
      debugPrint('Storage folder is not writable: ${directory.path}: $error');
      if (probeDirectory != null) {
        try {
          if (await probeDirectory.exists()) {
            await probeDirectory.delete(recursive: true);
          }
        } on Object catch (cleanupError) {
          debugPrint(
            'Storage probe could not be cleaned up at '
            '${probeDirectory.path}: $cleanupError',
          );
        }
      }
      return false;
    }
  }

  Future<File> _copyPickedAudio(
    PlatformFile pickedFile,
    Directory directory,
  ) async {
    final path = pickedFile.path;
    final safeName = _sanitizeFilename(pickedFile.name);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    if (path != null && File(path).existsSync()) {
      return File(path).copy(destination.path);
    }
    final sink = destination.openWrite();
    await sink.addStream(pickedFile.xFile.openRead());
    await sink.close();
    return destination;
  }

  ({String title, String artist}) _parseTrackName(String fileName) {
    final cleanName = fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final separator = RegExp(r'\s[-–—]\s').firstMatch(cleanName);
    if (separator == null) {
      return (title: cleanName, artist: 'Imported audio');
    }
    final artist = cleanName.substring(0, separator.start).trim();
    final title = cleanName.substring(separator.end).trim();
    return (
      title: title.isEmpty ? cleanName : title,
      artist: artist.isEmpty ? 'Imported audio' : artist,
    );
  }

  String _sanitizeFilename(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _basename(String value) => value.split(RegExp(r'[/\\]')).last;

  String _mediaExtension(String mime) {
    switch (mime.toLowerCase()) {
      case 'audio/mpeg':
      case 'audio/mp3':
        return '.mp3';
      case 'audio/ogg':
      case 'audio/opus':
        return '.ogg';
      case 'audio/wav':
      case 'audio/x-wav':
        return '.wav';
      case 'audio/flac':
      case 'audio/x-flac':
        return '.flac';
      case 'audio/mp4':
      case 'audio/aac':
      case 'audio/x-m4a':
        return '.m4a';
      default:
        return '.audio';
    }
  }

  Future<void> removeTrack(MusicTrack track) async {
    final updatedPlaylists = musicPlaylists
        .map(
          (playlist) => playlist.copyWith(
            trackIds: playlist.trackIds.where((id) => id != track.id).toList(),
          ),
        )
        .toList();
    if (!await _saveMusicPlaylistState(
      updatedPlaylists,
      selectedMusicPlaylistId,
    )) {
      return;
    }
    tracks = tracks.where((item) => item.id != track.id).toList();
    artworkErrors.remove(track.id);
    artworkLookupsInProgress.remove(track.id);
    artworkLookupAttempts.remove(track.id);
    if (currentTrack?.id == track.id) {
      await player.stop();
      currentTrack = null;
      _scheduleWindowsMediaControlsSync();
    }
    try {
      await File(track.path).delete();
    } on FileSystemException catch (error) {
      debugPrint('Removed audio could not be deleted: $error');
      musicErrorMessage =
          'Removed audio could not be deleted from this device.';
    }
    final artworkPath = track.artworkPath;
    if (artworkPath != null) {
      try {
        await File(artworkPath).delete();
      } on FileSystemException catch (error) {
        debugPrint('Removed artwork could not be deleted: $error');
      }
    }
    await _persistTracks();
    _notify();
  }

  Future<bool> renameTrack(
    String trackId, {
    required String title,
    required String artist,
  }) async {
    final normalizedTitle = title.trim();
    final normalizedArtist = artist.trim();
    if (normalizedTitle.isEmpty || normalizedArtist.isEmpty) {
      musicErrorMessage = 'Enter both a song title and an artist.';
      _notify();
      return false;
    }

    final trackIndex = tracks.indexWhere((track) => track.id == trackId);
    if (trackIndex < 0) {
      musicErrorMessage = 'That track is no longer available.';
      _notify();
      return false;
    }

    final original = tracks[trackIndex];
    final updated = original.copyWith(
      title: normalizedTitle,
      artist: normalizedArtist,
    );
    final updatedTracks = List<MusicTrack>.from(tracks)..[trackIndex] = updated;
    final isCurrentTrack = currentTrack?.id == trackId;
    final wasPlaying = isCurrentTrack && player.playing;
    final originalPosition = isCurrentTrack ? player.position : Duration.zero;
    SharedPreferences? preferences;
    String? originalTrackData;
    var preferencesUpdated = false;
    var audioMetadataUpdateAttempted = false;

    try {
      preferences = await SharedPreferences.getInstance();
      originalTrackData = preferences.getString(_tracksKey);
      final saved = await preferences.setString(
        _tracksKey,
        jsonEncode(updatedTracks.map((track) => track.toJson()).toList()),
      );
      if (!saved) throw StateError('The renamed track could not be saved.');
      preferencesUpdated = true;

      if (isCurrentTrack) {
        if (wasPlaying) await player.pause();
        audioMetadataUpdateAttempted = true;
        await player.setClip(
          start: original.clipStartMs == null
              ? null
              : Duration(milliseconds: original.clipStartMs!),
          end: original.clipEndMs == null
              ? null
              : Duration(milliseconds: original.clipEndMs!),
          tag: _mediaItemForTrack(updated),
        );
        await player.seek(originalPosition);
        currentTrack = updated;
        if (wasPlaying) _startAudioPlayback();
      }

      tracks = updatedTracks;
      artworkErrors.remove(trackId);
      artworkLookupAttempts.remove(trackId);
      musicErrorMessage = null;
      _scheduleWindowsMediaControlsSync();
      _notify();

      final artworkPath = updated.artworkPath;
      if (artworkPath == null || !await File(artworkPath).exists()) {
        unawaited(_ensureArtworkFor(updated));
      }
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Track rename could not be applied: $error\n$stackTrace');
      if (audioMetadataUpdateAttempted && isCurrentTrack) {
        try {
          await player.setClip(
            start: original.clipStartMs == null
                ? null
                : Duration(milliseconds: original.clipStartMs!),
            end: original.clipEndMs == null
                ? null
                : Duration(milliseconds: original.clipEndMs!),
            tag: _mediaItemForTrack(original),
          );
          await player.seek(originalPosition);
          currentTrack = original;
          if (wasPlaying) _startAudioPlayback();
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'Previous playback metadata could not be restored: '
            '$rollbackError\n$rollbackStackTrace',
          );
          musicErrorMessage = 'The rename failed. Stop and replay the track to restore its details.';
        }
      }

      if (preferencesUpdated && preferences != null) {
        try {
          if (originalTrackData == null) {
            await preferences.remove(_tracksKey);
          } else {
            final restored = await preferences.setString(
              _tracksKey,
              originalTrackData,
            );
            if (!restored) {
              throw StateError('The previous track details were not restored.');
            }
          }
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'Previous track details could not be restored: '
            '$rollbackError\n$rollbackStackTrace',
          );
          musicErrorMessage = 'The rename failed, and the previous details could not be restored.';
        }
      }

      musicErrorMessage ??= 'The song details could not be saved.';
      _notify();
      return false;
    }
  }

  Future<void> playTrack(MusicTrack track) async {
    try {
      if (currentTrack?.id == track.id && player.playing) {
        await player.pause();
        return;
      }
      if (currentVideo != null) {
        await videoPlayer.stop();
        currentVideo = null;
        await _setPictureInPictureEnabled(false);
      }
      if (!await File(track.path).exists()) {
        throw FileSystemException('The audio file is missing.', track.path);
      }
      final artworkPath = track.artworkPath;
      final artworkUri = artworkPath != null && File(artworkPath).existsSync()
          ? Uri.file(artworkPath)
          : null;
      var playableTrack = track;
      final sourceDuration = await player.setAudioSource(
        AudioSource.file(
          track.path,
          tag: _mediaItemForTrack(track, artworkUri: artworkUri),
        ),
      );
      if (track.durationMs == 0 && sourceDuration != null) {
        playableTrack = track.copyWith(
          durationMs: sourceDuration.inMilliseconds,
        );
        tracks = tracks
            .map((item) => item.id == track.id ? playableTrack : item)
            .toList();
        await _persistTracks();
      }
      if (playableTrack.clipStartMs != null ||
          playableTrack.clipEndMs != null) {
        await player.setClip(
          start: playableTrack.clipStartMs == null
              ? null
              : Duration(milliseconds: playableTrack.clipStartMs!),
          end: playableTrack.clipEndMs == null
              ? null
              : Duration(milliseconds: playableTrack.clipEndMs!),
          tag: _mediaItemForTrack(playableTrack),
        );
      }
      await player.setVolume(volume);
      currentTrack = playableTrack;
      musicErrorMessage = null;
      _scheduleWindowsMediaControlsSync();
      unawaited(_ensureArtworkFor(playableTrack));
      unawaited(fetchLyricsForCurrent());
      _notify();
      _startAudioPlayback();
    } on Object catch (error, stackTrace) {
      _reportAudioPlaybackError(error, stackTrace);
    }
  }

  Future<void> togglePlayback() async {
    if (currentTrack == null) {
      final firstTrack = visibleTracks.firstOrNull;
      if (firstTrack != null) await playTrack(firstTrack);
      return;
    }
    try {
      if (player.playing) {
        await player.pause();
      } else {
        _startAudioPlayback();
      }
    } on Object catch (error, stackTrace) {
      _reportAudioPlaybackError(error, stackTrace);
    }
  }

  void _startAudioPlayback() {
    unawaited(
      player.play().catchError((Object error, StackTrace stackTrace) {
        _reportAudioPlaybackError(error, stackTrace);
      }),
    );
  }

  void _reportAudioPlaybackError(Object error, StackTrace stackTrace) {
    debugPrint('Audio playback failed: $error\n$stackTrace');
    musicErrorMessage = error is FileSystemException
        ? 'The audio file is missing or can’t be read. Import it again.'
        : error is PlayerInterruptedException
        ? 'Audio playback was interrupted. Try playing the track again.'
        : error is PlayerException
        ? 'This audio format could not be decoded on this device.'
        : 'Audio could not be played. Try the track again or import another file.';
    _notify();
  }

  MediaItem _mediaItemForTrack(MusicTrack track, {Uri? artworkUri}) {
    final startMs = track.clipStartMs ?? 0;
    final endMs = track.clipEndMs ?? track.durationMs;
    final durationMs = endMs > 0 ? endMs - startMs : null;
    final trackArtworkPath = track.artworkPath;
    final metadata = track.displayMetadata;
    final artUri =
        artworkUri ??
        (trackArtworkPath != null && File(trackArtworkPath).existsSync()
            ? Uri.file(trackArtworkPath)
            : null);
    return MediaItem(
      id: track.id,
      album: 'Musico',
      title: metadata.title,
      artist: metadata.artist,
      artUri: artUri,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }

  void _scheduleWindowsMediaControlsSync() {
    if (!Platform.isWindows) return;
    _windowsMediaControlsUpdateQueue = _windowsMediaControlsUpdateQueue
        .then<void>((_) => _syncWindowsMediaControls())
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint(
            'Windows media controls could not be updated: $error\n$stackTrace',
          );
        });
  }

  Future<void> _syncWindowsMediaControls() async {
    if (!Platform.isWindows) return;
    try {
      final track = currentTrack;
      if (track == null) {
        if (!_windowsMediaControlsPublished) return;
        await _windowsMediaControlsChannel.invokeMethod<void>('clear');
        _windowsMediaControlsPublished = false;
        return;
      }

      final artworkPath = track.artworkPath;
      await _windowsMediaControlsChannel.invokeMethod<void>('update', {
        'title': track.displayMetadata.title,
        'artist': track.displayMetadata.artist,
        'artworkPath': artworkPath != null && File(artworkPath).existsSync()
            ? artworkPath
            : '',
        'isPlaying': player.playing,
      });
      _windowsMediaControlsPublished = true;
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Windows media details could not be updated: '
        '${error.message ?? error.code}\n$stackTrace',
      );
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Windows media controls are unavailable: $error\n$stackTrace');
    }
  }

  Future<void> retryArtworkLookup(String trackId) async {
    final track = tracks.where((item) => item.id == trackId).firstOrNull;
    if (track != null) {
      artworkLookupAttempts.remove(trackId);
      await _ensureArtworkFor(track);
    }
  }

  Future<bool> setTrackTrim(
    String trackId, {
    required Duration start,
    required Duration? end,
  }) async {
    final track = tracks.where((item) => item.id == trackId).firstOrNull;
    if (track == null) {
      musicErrorMessage = 'That track is no longer available.';
      _notify();
      return false;
    }
    final sourceDurationMs = track.durationMs > 0
        ? track.durationMs
        : currentTrack?.id == trackId
        ? player.duration?.inMilliseconds ?? 0
        : 0;
    final startMs = start.inMilliseconds;
    final endMs = end?.inMilliseconds;
    if (sourceDurationMs <= 0 ||
        startMs < 0 ||
        startMs >= sourceDurationMs ||
        (endMs != null && (endMs <= startMs || endMs > sourceDurationMs))) {
      musicErrorMessage = 'Play the track once to load its duration, then choose a valid trim range.';
      _notify();
      return false;
    }

    final updated = track.withTrim(startMs: startMs, endMs: endMs);
    final updatedTracks = tracks
        .map((item) => item.id == trackId ? updated : item)
        .toList();
    SharedPreferences? preferences;
    String? originalTrackData;
    var preferencesUpdated = false;
    var audioChangeAttempted = false;
    final isCurrentTrack = currentTrack?.id == trackId;
    final wasPlaying = isCurrentTrack && player.playing;
    try {
      preferences = await SharedPreferences.getInstance();
      originalTrackData = preferences.getString(_tracksKey);
      final saved = await preferences.setString(
        _tracksKey,
        jsonEncode(updatedTracks.map((item) => item.toJson()).toList()),
      );
      if (!saved) throw StateError('The track trim could not be saved.');
      preferencesUpdated = true;

      if (isCurrentTrack) {
        if (wasPlaying) await player.pause();
        audioChangeAttempted = true;
        await player.setClip(
          start: startMs == 0 ? null : Duration(milliseconds: startMs),
          end: endMs == null ? null : Duration(milliseconds: endMs),
          tag: _mediaItemForTrack(updated),
        );
        await player.seek(Duration.zero);
        currentTrack = updated;
        if (wasPlaying) _startAudioPlayback();
      }

      tracks = updatedTracks;
      musicErrorMessage = null;
      _notify();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Track trim could not be applied: $error\n$stackTrace');
      if (audioChangeAttempted && isCurrentTrack) {
        try {
          await player.setClip(
            start: track.clipStartMs == null
                ? null
                : Duration(milliseconds: track.clipStartMs!),
            end: track.clipEndMs == null
                ? null
                : Duration(milliseconds: track.clipEndMs!),
            tag: _mediaItemForTrack(track),
          );
          if (wasPlaying) _startAudioPlayback();
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'The previous audio trim could not be restored: '
            '$rollbackError\n$rollbackStackTrace',
          );
          musicErrorMessage =
              'The trim could not be restored. Stop and replay the track.';
        }
      }
      if (preferencesUpdated && preferences != null) {
        try {
          if (originalTrackData == null) {
            await preferences.remove(_tracksKey);
          } else {
            await preferences.setString(_tracksKey, originalTrackData);
          }
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'The previous track metadata could not be restored: '
            '$rollbackError\n$rollbackStackTrace',
          );
          musicErrorMessage = 'The trim could not be saved, and previous track data could not be restored.';
        }
      }
      musicErrorMessage ??= 'The trim could not be saved or applied.';
      _notify();
      return false;
    }
  }

  Future<void> _lookupMissingTrackArtwork() async {
    for (final track in tracks) {
      await _ensureArtworkFor(track);
    }
  }

  Future<void> _ensureArtworkFor(MusicTrack track) async {
    final existingPath = track.artworkPath;
    if (existingPath != null && await File(existingPath).exists()) return;
    if (!isOnline ||
        artworkLookupsInProgress.contains(track.id) ||
        !artworkLookupAttempts.add(track.id)) {
      return;
    }
    artworkLookupsInProgress.add(track.id);
    artworkErrors.remove(track.id);
    _notify();

    try {
      final metadata = track.displayMetadata;
      final artwork = await _artworkService
          .findForTrack(title: metadata.title, artist: metadata.artist)
          .timeout(const Duration(seconds: 15));
      if (artwork == null) return;
      final directory = await _mediaStorageDirectory('artwork');
      final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File(
        '${directory.path}${Platform.pathSeparator}$safeId${artwork.extension}',
      );
      await file.writeAsBytes(artwork.bytes, flush: true);
      final updated = track.withArtwork(
        path: file.path,
        title: artwork.title,
        creator: artwork.creator,
        license: artwork.license,
        licenseUrl: artwork.licenseUrl,
        sourceUrl: artwork.sourceUrl,
        attribution: artwork.attribution,
      );
      tracks = tracks
          .map((item) => item.id == track.id ? updated : item)
          .toList();
      if (currentTrack?.id == track.id) currentTrack = updated;
      await _persistTracks();
      if (currentTrack?.id == track.id) {
        if (Platform.isWindows) _scheduleWindowsMediaControlsSync();
        if (Platform.isAndroid) {
          await _refreshAndroidNowPlayingArtwork(updated);
        }
      }
      artworkErrors.remove(track.id);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Licensed artwork lookup failed for "${track.title}": $error\n$stackTrace',
      );
      final statusCode = error is HttpException
          ? RegExp(r'Openverse returned (\d{3})')
                .firstMatch(error.message)
                ?.group(1)
          : null;
      artworkErrors[track.id] = statusCode != null
          ? 'Openverse returned $statusCode. Try the artwork search again later.'
          : error is TimeoutException
          ? 'Artwork search timed out. Check your connection and retry.'
          : 'Artwork could not be loaded. Check your connection and retry.';
    } finally {
      artworkLookupsInProgress.remove(track.id);
      _notify();
    }
  }

  Future<void> _refreshAndroidNowPlayingArtwork(MusicTrack track) async {
    if (currentTrack?.id != track.id) return;

    final position = player.position;
    final wasPlaying = player.playing;
    final mediaItem = _mediaItemForTrack(track);
    try {
      await player.setAudioSource(
        AudioSource.file(track.path, tag: mediaItem),
        initialPosition: position,
      );
      if (track.clipStartMs != null || track.clipEndMs != null) {
        await player.setClip(
          start: track.clipStartMs == null
              ? null
              : Duration(milliseconds: track.clipStartMs!),
          end: track.clipEndMs == null
              ? null
              : Duration(milliseconds: track.clipEndMs!),
          tag: mediaItem,
        );
        await player.seek(position);
      }
      if (wasPlaying && currentTrack?.id == track.id && !player.playing) {
        await player.play();
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Android now-playing artwork could not be refreshed: '
        '$error\n$stackTrace',
      );
      if (currentTrack?.id == track.id) {
        musicErrorMessage = 'Artwork was saved, but the now-playing thumbnail could not be updated. Replay the track.';
      }
    }
  }

  Future<void> _playNext({bool automatic = false}) async {
    final queue = visibleTracks;
    if (currentTrack == null || queue.isEmpty) return;
    if (automatic && repeatOne) {
      await player.seek(Duration.zero);
      await player.play();
      return;
    }
    if (automatic && !autoplay) return;
    if (shuffle) {
      final choices = queue
          .where((track) => track.id != currentTrack?.id)
          .toList();
      if (choices.isNotEmpty) {
        await playTrack(choices[math.Random().nextInt(choices.length)]);
      }
      return;
    }
    final index = queue.indexWhere((track) => track.id == currentTrack?.id);
    if (index >= 0 && index + 1 < queue.length) {
      await playTrack(queue[index + 1]);
    }
  }

  Future<void> playPrevious() async {
    final current = currentTrack;
    final queue = visibleTracks;
    if (current == null || queue.isEmpty) return;
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    final index = queue.indexWhere((track) => track.id == current.id);
    if (index > 0) await playTrack(queue[index - 1]);
  }

  Future<void> playNext() => _playNext();

  Future<void> seek(Duration position) async => player.seek(position);

  Future<void> pickVideoFiles() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.video);
      if (result.isEmpty) return;
      isImportingVideos = true;
      videoErrorMessage = null;
      _notify();
      final directory = await _mediaStorageDirectory('videos');
      for (final picked in result) {
        final safeName = _sanitizeFilename(picked.name);
        final destination = File(
          '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$safeName',
        );
        final sourcePath = picked.path;
        if (sourcePath != null && File(sourcePath).existsSync()) {
          await File(sourcePath).copy(destination.path);
        } else {
          final sink = destination.openWrite();
          await sink.addStream(picked.xFile.openRead());
          await sink.close();
        }
        videoTracks.insert(
          0,
          VideoTrack(
            id: 'video-${DateTime.now().microsecondsSinceEpoch}',
            title: _basename(picked.name).replaceFirst(RegExp(r'\.[^.]+$'), ''),
            path: destination.path,
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
            byteSize: await destination.length(),
          ),
        );
      }
      await _persistVideos();
    } on PlatformException catch (error, stackTrace) {
      debugPrint('The video picker could not be opened: $error\n$stackTrace');
      videoErrorMessage = 'The video picker could not be opened.';
    } on FileSystemException catch (error, stackTrace) {
      debugPrint(
        'Video could not be saved to this device: $error\n$stackTrace',
      );
      videoErrorMessage =
          'Video could not be saved. Check available device storage.';
    } on Object catch (error, stackTrace) {
      debugPrint('Video import failed: $error\n$stackTrace');
      videoErrorMessage = 'This video could not be imported. Try another file.';
    } finally {
      isImportingVideos = false;
      _notify();
    }
  }

  Future<void> playVideo(VideoTrack video) async {
    try {
      await player.stop();
      currentTrack = null;
      _scheduleWindowsMediaControlsSync();
      final videoPlayer = this.videoPlayer;
      _initializeVideoPlayer();
      lyrics = null;
      lyricsErrorMessage = null;
      lyricsStatus = LyricsStatus.idle;
      videoErrorMessage = null;
      await videoPlayer.open(Media(video.path));
      currentVideo = video;
      await _setPictureInPictureEnabled(true);
      unawaited(fetchLyricsForCurrent());
      musicErrorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint('Video playback could not start: $error\n$stackTrace');
      videoErrorMessage = 'This video could not be played on this device.';
      lyricsStatus = LyricsStatus.idle;
    } finally {
      _notify();
    }
  }

  Future<void> stopVideo() async {
    final videoPlayer = _videoPlayer;
    if (videoPlayer != null) await videoPlayer.stop();
    await _setPictureInPictureEnabled(false);
    currentVideo = null;
    lyrics = null;
    lyricsErrorMessage = null;
    lyricsStatus = LyricsStatus.idle;
    _notify();
  }

  Future<void> removeVideo(VideoTrack video) async {
    videoTracks = videoTracks.where((item) => item.id != video.id).toList();
    if (currentVideo?.id == video.id) {
      final videoPlayer = _videoPlayer;
      if (videoPlayer != null) await videoPlayer.stop();
      await _setPictureInPictureEnabled(false);
      currentVideo = null;
      lyrics = null;
      lyricsStatus = LyricsStatus.idle;
    }
    try {
      await File(video.path).delete();
    } on FileSystemException catch (error, stackTrace) {
      debugPrint('Removed video could not be deleted: $error\n$stackTrace');
      videoErrorMessage =
          'Removed video could not be deleted from this device.';
    }
    await _persistVideos();
    _notify();
  }

  Future<void> _setPictureInPictureEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _pictureInPictureChannel.invokeMethod<void>('setEnabled', {
        'enabled': enabled,
      });
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Picture-in-Picture could not be updated: $error\n$stackTrace',
      );
      videoErrorMessage =
          'Background video controls are unavailable on this device.';
    }
  }

  Future<void> fetchLyricsForCurrent() async {
    final track = currentTrack;
    final video = currentVideo;
    if (track == null && video == null) {
      lyricsStatus = LyricsStatus.idle;
      lyrics = null;
      lyricsErrorMessage = null;
      _notify();
      return;
    }

    lyrics = null;
    lyricsErrorMessage = null;
    try {
      final connection = await _connectivity.checkConnectivity();
      isWifiConnected = connection.contains(ConnectivityResult.wifi);
      hasNetworkConnection = connection.any(
        (result) => result != ConnectivityResult.none,
      );
      isOnline = hasNetworkConnection;
      if (!hasNetworkConnection) {
        lyricsStatus = LyricsStatus.networkRequired;
        _notify();
        return;
      }

      final metadata = track != null
          ? (
              track.displayMetadata.title,
              track.displayMetadata.artist,
              track.durationMs > 0
                  ? track.durationMs
                  : player.duration?.inMilliseconds ?? 0,
            )
          : _videoLyricsMetadata(video!);
      lyricsStatus = LyricsStatus.loading;
      _notify();
      final payload = await _findLyricsRecord(metadata);
      if (payload == null) {
        lyricsStatus = LyricsStatus.notFound;
        return;
      }
      final plainLyrics = payload['plainLyrics'] as String?;
      final syncedLyrics = payload['syncedLyrics'] as String?;
      final foundLyrics = plainLyrics?.trim().isNotEmpty == true
          ? plainLyrics
          : syncedLyrics
                ?.replaceAll(RegExp(r'\[\d{2}:\d{2}(?:\.\d{2,3})?\]'), '')
                .trim();
      if (foundLyrics == null || foundLyrics.isEmpty) {
        lyricsStatus = LyricsStatus.notFound;
        return;
      }
      lyrics = foundLyrics;
      lyricsStatus = LyricsStatus.loaded;
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Automatic lyrics lookup timed out: $error\n$stackTrace');
      lyricsErrorMessage = 'The lyrics request timed out. Check your internet connection and try again.';
      lyricsStatus = LyricsStatus.error;
    } on SocketException catch (error, stackTrace) {
      debugPrint(
        'Automatic lyrics lookup could not reach the service: $error\n$stackTrace',
      );
      lyricsErrorMessage = 'Could not reach the lyrics service. Check your internet connection and retry.';
      lyricsStatus = LyricsStatus.error;
    } on Object catch (error, stackTrace) {
      debugPrint('Automatic lyrics lookup failed: $error\n$stackTrace');
      lyricsErrorMessage = error is HttpException ? error.message : 'Lyrics could not be loaded. Check your internet connection and retry.';
      lyricsStatus = LyricsStatus.error;
    } finally {
      _notify();
    }
  }

  Future<Map<String, dynamic>?> _findLyricsRecord(
    (String, String, int) metadata,
  ) async {
    final title = normalizeLyricsTitle(metadata.$1);
    final artist = metadata.$2.trim();
    const genericArtists = {'imported audio', 'wikimedia commons contributor'};
    final knownArtist =
        artist.isNotEmpty && !genericArtists.contains(artist.toLowerCase());
    final durationSeconds = (metadata.$3 / 1000).round();
    final headers = const {'User-Agent': 'Musico/1.0 (offline media player)'};

    if (knownArtist) {
      final query = <String, String>{
        'track_name': title,
        'artist_name': artist,
      };
      if (durationSeconds >= 1 && durationSeconds <= 3600) {
        query['duration'] = durationSeconds.toString();
      }
      final exact = await _getLyricsResponse(
        Uri.https('lrclib.net', '/api/get', query),
        headers,
      );
      if (exact.statusCode == 200) {
        return jsonDecode(exact.body) as Map<String, dynamic>;
      }
      if (exact.statusCode != 404) {
        throw HttpException('The lyrics service returned ${exact.statusCode}.');
      }
    }

    final query = artist.isEmpty || !knownArtist
        ? {'q': title}
        : {'q': '$title $artist'};
    final search = await _getLyricsResponse(
      Uri.https('lrclib.net', '/api/search', query),
      headers,
    );
    if (search.statusCode != 200) {
      throw HttpException('The lyrics service returned ${search.statusCode}.');
    }
    final records = (jsonDecode(search.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where(
          (record) => lyricsTitleMatches(
            title,
            record['trackName'] as String? ?? record['name'] as String? ?? '',
          ),
        )
        .toList();
    final matchingArtist = knownArtist
        ? records
              .where(
                (record) =>
                    (record['artistName'] as String? ?? '')
                        .trim()
                        .toLowerCase() ==
                    artist.toLowerCase(),
              )
              .toList()
        : records;
    if (knownArtist && matchingArtist.isEmpty) return null;
    final candidates = matchingArtist.isNotEmpty ? matchingArtist : records;
    if (candidates.isEmpty) return null;

    if (durationSeconds > 0) {
      final durationMatches = candidates
          .where(
            (record) =>
                (((record['duration'] as num?)?.toDouble() ?? -100) -
                        durationSeconds)
                    .abs() <=
                2,
          )
          .toList();
      if (durationMatches.isNotEmpty) return durationMatches.first;
    }
    if (candidates.length == 1 || knownArtist) return candidates.first;
    return null;
  }

  Future<http.Response> _getLyricsResponse(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final retryAfter = _lyricsRetryAfter;
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      final seconds = retryAfter.difference(DateTime.now()).inSeconds;
      throw HttpException(
        'The lyrics service is busy. Try again in about ${seconds + 1} seconds.',
      );
    }
    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 429 || response.statusCode == 503) {
      final retrySeconds =
          int.tryParse(response.headers['retry-after'] ?? '') ?? 1;
      _lyricsRetryAfter = DateTime.now().add(
        Duration(seconds: retrySeconds.clamp(1, 3600).toInt()),
      );
    }
    return response;
  }

  (String, String, int) _videoLyricsMetadata(VideoTrack video) {
    final name = video.title;
    final separator = RegExp(r'\s[-–—]\s').firstMatch(name);
    if (separator == null) {
      return (name, '', videoPlayer.state.duration.inMilliseconds);
    }
    final artist = name.substring(0, separator.start).trim();
    final title = name.substring(separator.end).trim();
    return (
      title.isEmpty ? name : title,
      artist,
      videoPlayer.state.duration.inMilliseconds,
    );
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1).toDouble();
    if (currentTrack != null) await player.setVolume(volume);
    _volumePersistTimer?.cancel();
    _volumePersistTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistVolume());
    });
    _notify();
  }

  Future<void> _persistVolume() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble(_volumeKey, volume);
    } on Object catch (error, stackTrace) {
      debugPrint('Playback volume could not be saved: $error\n$stackTrace');
      settingsErrorMessage = 'The volume preference could not be saved.';
      _notify();
    }
  }

  Future<void> setSortAlphabetically(bool value) async {
    sortAlphabetically = value;
    await _saveBooleanPreference(
      _sortAlphabeticallyKey,
      value,
      'music sorting',
    );
    _notify();
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    await _saveBooleanPreference(_shuffleKey, shuffle, 'shuffle');
    _notify();
  }

  Future<void> toggleRepeatOne() async {
    repeatOne = !repeatOne;
    await _saveBooleanPreference(_repeatOneKey, repeatOne, 'repeat-one');
    _notify();
  }

  Future<void> setAutoplay(bool value) async {
    autoplay = value;
    await _saveBooleanPreference(_autoplayKey, value, 'autoplay');
    _notify();
  }

  void setTrackQuery(String query) {
    trackQuery = query;
    _notify();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _notify();
  }

  void setCollection(ReleaseCollection collection) {
    releaseCollection = collection;
    if (collection != ReleaseCollection.search) searchQuery = '';
    _notify();
  }

  void setSelectedDate(DateTime date) {
    selectedDate = _dayStart(date);
    _notify();
  }

  Future<void> searchAnime(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      searchQuery = '';
      setCollection(ReleaseCollection.weekly);
      return;
    }
    searchQuery = query;
    releaseCollection = ReleaseCollection.search;
    isSearching = true;
    errorMessage = null;
    _notify();
    try {
      final data = await _requestAniList(_searchQuery, {'search': query});
      searchResults = _mediaFromData(data);
    } on Object catch (error, stackTrace) {
      debugPrint('AniList search failed: $error\n$stackTrace');
      errorMessage = _userFriendlyError(error);
    } finally {
      isSearching = false;
      _notify();
    }
  }

  Future<void> refreshAnime({
    bool silent = false,
    bool initialLoad = false,
  }) async {
    if (isLoadingSchedule) return;
    final preferences = await SharedPreferences.getInstance();
    if (initialLoad) {
      seasonTitles = _decodeMediaList(preferences.getString(_seasonCacheKey));
      upcomingTitles = _decodeMediaList(
        preferences.getString(_upcomingCacheKey),
      );
      if (seasonTitles.isNotEmpty || upcomingTitles.isNotEmpty) _notify();
    }
    if (!isOnline) {
      if (seasonTitles.isEmpty && upcomingTitles.isEmpty) {
        errorMessage =
            'Connect to the internet to load the latest anime schedule.';
      }
      return;
    }
    isLoadingSchedule = true;
    if (!silent && !initialLoad) errorMessage = null;
    _notify();
    try {
      final now = DateTime.now();
      final seasonInfo = _currentSeason(now);
      final seasonData = await _requestAniList(_seasonQuery, seasonInfo);
      final upcomingData = await _requestAniList(_upcomingQuery, const {});
      seasonTitles = _mediaFromData(seasonData);
      upcomingTitles = _mediaFromData(upcomingData);
      isOnline = true;
      final byId = {
        for (final title in [...seasonTitles, ...upcomingTitles])
          title.id: title,
      };
      watchlist = watchlist.map((saved) => byId[saved.id] ?? saved).toList();
      await preferences.setString(
        _seasonCacheKey,
        jsonEncode(seasonTitles.map((title) => title.toJson()).toList()),
      );
      await preferences.setString(
        _upcomingCacheKey,
        jsonEncode(upcomingTitles.map((title) => title.toJson()).toList()),
      );
      await _persistWatchlist();
      if (notificationsEnabled) await syncWatchlistNotifications();
      errorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint('AniList schedule refresh failed: $error\n$stackTrace');
      if (error is SocketException || error is http.ClientException) {
        isOnline = false;
      }
      if (seasonTitles.isEmpty && upcomingTitles.isEmpty) {
        errorMessage = _userFriendlyError(error);
      } else if (!silent) {
        errorMessage =
            'Showing your saved release schedule. ${_userFriendlyError(error)}';
      }
    } finally {
      isLoadingSchedule = false;
      _notify();
    }
  }

  Map<String, dynamic> _currentSeason(DateTime date) {
    final month = date.month;
    final season = month < 4
        ? 'WINTER'
        : month < 7
        ? 'SPRING'
        : month < 10
        ? 'SUMMER'
        : 'FALL';
    return {'season': season, 'year': date.year};
  }

  List<MediaTitle> _mediaFromData(Map<String, dynamic> data) {
    final page = data['Page'] as Map<String, dynamic>?;
    final media = page?['media'] as List<dynamic>? ?? const [];
    return media
        .whereType<Map<String, dynamic>>()
        .map(MediaTitle.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _requestAniList(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_aniListApi),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(const Duration(seconds: 24));
    if (response.statusCode == 429) {
      throw const HttpException(
        'AniList is busy. Wait a moment and try again.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'AniList returned an error (${response.statusCode}).',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final errors = payload['errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      final message =
          (errors.first as Map<String, dynamic>)['message'] as String? ??
          'AniList returned an error.';
      throw HttpException(message);
    }
    return payload['data'] as Map<String, dynamic>? ??
        (throw const FormatException('AniList returned no schedule data.'));
  }

  String _userFriendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The request timed out. Check your connection.';
    }
    if (error is SocketException || error is http.ClientException) {
      return 'Could not reach the schedule service. Check your internet connection.';
    }
    if (error is HttpException) return error.message;
    return 'Something went wrong while loading new releases.';
  }

  Future<void> addToWatchlist(MediaTitle title) async {
    if (watchlist.any((item) => item.id == title.id)) return;
    watchlist = [...watchlist, title];
    await _persistWatchlist();
    if (notificationsEnabled) await syncWatchlistNotifications();
    _notify();
  }

  Future<void> removeFromWatchlist(MediaTitle title) async {
    watchlist = watchlist.where((item) => item.id != title.id).toList();
    await _persistWatchlist();
    if (notificationsEnabled) await syncWatchlistNotifications();
    _notify();
  }

  bool isSaved(MediaTitle title) =>
      watchlist.any((item) => item.id == title.id);

  Future<void> requestAiringNotifications() async {
    if (!notificationsAvailable || !_notificationsInitialized) {
      errorMessage = 'Native notifications are not available on this device.';
      _notify();
      return;
    }
    try {
      if (Platform.isAndroid) {
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final permitted =
            await android?.requestNotificationsPermission() ?? false;
        if (!permitted) {
          errorMessage = 'Allow Musico notifications in Android settings to enable airing reminders.';
          _notify();
          return;
        }
      }
      notificationsEnabled = true;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_notificationPermissionKey, true);
      await syncWatchlistNotifications();
      errorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint('Could not enable native notifications: $error\n$stackTrace');
      errorMessage = 'Musico could not enable native airing notifications.';
    }
    _notify();
  }

  Future<void> disableAiringNotifications() async {
    notificationsEnabled = false;
    errorMessage = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_notificationPermissionKey, false);
    if (_notificationsInitialized) await _notifications.cancelAll();
    _notify();
  }

  Future<void> syncWatchlistNotifications() async {
    if (!notificationsEnabled ||
        !_notificationsInitialized ||
        watchlist.isEmpty) {
      return;
    }
    try {
      await _notifications.cancelAll();
      for (final title in watchlist) {
        final airing = title.nextAiring;
        final scheduledDate = airing?.airingAt ?? title.startDate;
        if (scheduledDate == null || !scheduledDate.isAfter(DateTime.now())) {
          continue;
        }
        final message = airing == null
            ? '${title.title} is scheduled to premiere today.'
            : 'Episode ${airing.episode} of ${title.title} is scheduled to air.';
        await _scheduleReminder(title, scheduledDate, message, airing?.episode);
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Airing reminders could not be scheduled: $error\n$stackTrace',
      );
      errorMessage = 'Airing reminders could not be scheduled on this device.';
      _notify();
    }
  }

  Future<void> _scheduleReminder(
    MediaTitle title,
    DateTime scheduledDate,
    String body,
    int? episode,
  ) async {
    final notificationId = _notificationId(title.id, episode ?? 0);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return;
    }
    final scheduled = tz.TZDateTime.from(scheduledDate, tz.local);
    await _notifications.zonedSchedule(
      id: notificationId,
      title: 'On your list · ${title.title}',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'sideb_anime_airings',
          'Anime airing reminders',
          channelDescription:
              'Reminders for anime movies and series saved to your watchlist',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'anime:${title.id}',
    );
  }

  int _notificationId(int mediaId, int episode) =>
      (mediaId * 7919 + episode * 104729) & 0x7fffffff;

  void checkBackgroundAiringNotifications() {
    if (!_notificationsInitialized || !notificationsEnabled) return;
    for (final title in watchlist) {
      final airing = title.nextAiring;
      if (airing == null) continue;
      final diff = airing.airingAt.difference(DateTime.now());
      if (diff.isNegative || diff > const Duration(minutes: 5)) continue;
      final key =
          '${title.id}:${airing.episode}:${airing.airingAt.millisecondsSinceEpoch}';
      if (!notifiedAiringKeys.add(key)) continue;
      unawaited(
        _notifications.show(
          id: _notificationId(title.id, airing.episode),
          title: 'On your list · ${title.title}',
          body: 'Episode ${airing.episode} is scheduled to air now.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'sideb_anime_airings',
              'Anime airing reminders',
              channelDescription: 'Episode reminders for your anime watchlist',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        ),
      );
    }
  }

  Future<void> searchCommons(String query) async {
    commonsQuery = query.trim();
    hasSearchedCommons = true;
    isSearchingMusic = true;
    commonsResults = [];
    commonsSearchError = null;
    commonsEmptyMessage = null;
    if (query.trim().isEmpty) {
      commonsEmptyMessage =
          'Enter a music style, instrument, or artist to search.';
      isSearchingMusic = false;
      _notify();
      return;
    }
    musicErrorMessage = null;
    _notify();
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'generator': 'search',
        'gsrnamespace': '6',
        'gsrlimit': '20',
        'gsrsearch': 'filetype:audio ${query.trim()}',
        'prop': 'imageinfo',
        'iiprop': 'url|mime|size|duration|extmetadata',
      });
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': 'Musico/1.0 (desktop and Android music player)',
            },
          )
          .timeout(const Duration(seconds: 24));
      if (response.statusCode != 200) {
        throw HttpException(
          'Wikimedia Commons search failed (${response.statusCode}).',
        );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final pages =
          (payload['query'] as Map<String, dynamic>?)?['pages']
              as Map<String, dynamic>? ??
          const {};
      final results = <MusicResult>[];
      for (final page in pages.values.whereType<Map<String, dynamic>>()) {
        try {
          final item = MusicResult.fromJson(page);
          if (item.mime.startsWith('audio/')) results.add(item);
        } on FormatException {
          continue;
        }
      }
      commonsResults = results;
      if (results.isEmpty) {
        commonsEmptyMessage = 'No eligible CC BY, CC BY-SA, CC0, or public-domain audio matched. Try a broader search.';
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Free music search failed: $error\n$stackTrace');
      commonsSearchError = error is HttpException
          ? error.message
          : error is TimeoutException
          ? 'The music catalogue request timed out. Check your connection and retry.'
          : 'Wikimedia Commons could not be reached. Check your internet connection.';
    } finally {
      isSearchingMusic = false;
      _notify();
    }
  }

  Future<void> downloadMusic(MusicResult result) async {
    if (tracks.any((track) => track.commonsPageId == result.pageId) ||
        downloadingIds.contains(result.pageId)) {
      return;
    }
    final fileUri = Uri.tryParse(result.fileUrl);
    if (fileUri == null ||
        fileUri.scheme != 'https' ||
        fileUri.host != 'upload.wikimedia.org') {
      musicErrorMessage = 'This download does not come from Wikimedia Commons.';
      _notify();
      return;
    }
    downloadingIds = {...downloadingIds, result.pageId};
    downloadProgress[result.pageId] = 0;
    musicErrorMessage = null;
    _notify();
    File? destination;
    try {
      final response = await _client
          .send(http.Request('GET', fileUri))
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw HttpException(
          'The audio download failed (${response.statusCode}).',
        );
      }
      final contentType = response.headers['content-type'] ?? result.mime;
      if (!contentType.toLowerCase().startsWith('audio/')) {
        throw const FormatException('The source did not return an audio file.');
      }
      if (response.contentLength != null &&
          response.contentLength! > 100 * 1024 * 1024) {
        throw const FormatException(
          'This audio file is too large to download in the app.',
        );
      }
      final directory = await _libraryDirectory();
      final destinationName =
          '${result.pageId}-${_sanitizeFilename(result.title)}${_mediaExtension(contentType)}';
      destination = File(
        '${directory.path}${Platform.pathSeparator}$destinationName',
      );
      final output = destination.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > 100 * 1024 * 1024) {
          throw const FormatException(
            'This audio file exceeds the 100 MB download limit.',
          );
        }
        output.add(chunk);
        final length = response.contentLength;
        if (length != null && length > 0) {
          downloadProgress[result.pageId] = (received / length).clamp(0, 1);
          if (received % (512 * 1024) < chunk.length) _notify();
        }
      }
      await output.flush();
      await output.close();
      if (received == 0) {
        throw const FormatException('The source returned an empty audio file.');
      }
      final licenseUri = Uri.tryParse(result.licenseUrl);
      if (licenseUri == null ||
          licenseUri.scheme != 'https' ||
          !{
            'creativecommons.org',
            'commons.wikimedia.org',
          }.contains(licenseUri.host)) {
        throw const FormatException('The license could not be verified.');
      }
      tracks = [
        MusicTrack(
          id: 'commons-${result.pageId}',
          title: result.title,
          artist: result.artist,
          path: destination.path,
          durationMs: result.duration * 1000,
          addedAtMs: DateTime.now().millisecondsSinceEpoch,
          license: result.license,
          licenseUrl: licenseUri.toString(),
          sourceUrl: result.sourceUrl,
          commonsPageId: result.pageId,
          byteSize: received,
        ),
        ...tracks,
      ];
      await _persistTracks();
      musicErrorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint('Licensed audio download failed: $error\n$stackTrace');
      musicErrorMessage = error is HttpException
          ? error.message
          : error is FormatException
          ? error.message
          : 'This audio could not be saved. Check the connection and device storage.';
      if (destination != null && await destination.exists()) {
        await destination.delete();
      }
    } finally {
      downloadingIds = {...downloadingIds}..remove(result.pageId);
      downloadProgress.remove(result.pageId);
      _notify();
    }
  }

  bool isConfiguredDownloadSaved(MediaDownloadLink item) {
    final id = 'direct-${item.progressKey.replaceAll(':', '-')}';
    return switch (item.category) {
      MediaDownloadCategory.music => tracks.any((track) => track.id == id),
      MediaDownloadCategory.video ||
      MediaDownloadCategory.anime => videoTracks.any((video) => video.id == id),
    };
  }

  MediaDownloadLink? configuredDownloadForSpotifyTrack(
    SpotifyPlaylistTrack track,
  ) {
    for (final download
        in mediaDownloadConfig?.forCategory(MediaDownloadCategory.music) ??
            const <MediaDownloadLink>[]) {
      if (track.matchesDownload(download)) return download;
    }
    return null;
  }

  Future<bool> downloadConfiguredMedia(MediaDownloadLink item) async {
    final configured = mediaDownloadConfig
        ?.forCategory(item.category)
        .any(
          (candidate) => candidate.id == item.id && candidate.url == item.url,
        );
    if (configured != true) {
      configuredDownloadErrorMessage =
          'This download link is not in the active configuration.';
      _notify();
      return false;
    }

    final key = item.progressKey;
    if (isConfiguredDownloadSaved(item)) {
      configuredDownloadErrorMessage = 'This media is already saved locally.';
      _notify();
      return false;
    }
    if (downloadingConfiguredIds.contains(key)) return false;

    downloadingConfiguredIds = {...downloadingConfiguredIds, key};
    configuredDownloadProgress[key] = null;
    configuredDownloadErrorMessage = null;
    _notify();

    final trackId = 'direct-${key.replaceAll(':', '-')}';
    File? destination;
    var registered = false;
    try {
      final mediaDirectory = await _mediaStorageDirectory(
        item.category == MediaDownloadCategory.music ? 'music' : 'videos',
      );
      final downloaded = await _directDownloadService.download(
        item,
        mediaDirectory,
        onProgress: (progress) {
          configuredDownloadProgress[key] = progress;
          _notify();
        },
      );
      destination = downloaded.file;

      final savedAt = DateTime.now().millisecondsSinceEpoch;
      if (item.category == MediaDownloadCategory.music) {
        tracks = [
          MusicTrack(
            id: trackId,
            title: item.title,
            artist: item.artist ?? 'Direct download',
            path: destination.path,
            durationMs: 0,
            addedAtMs: savedAt,
            license: item.rights.label,
            licenseUrl: item.licenseUrl,
            sourceUrl: item.url,
            commonsPageId: null,
            byteSize: downloaded.byteSize,
            attribution: item.attribution,
          ),
          ...tracks,
        ];
        registered = true;
        await _persistTracks();
      } else {
        videoTracks.insert(
          0,
          VideoTrack(
            id: trackId,
            title: item.title,
            path: destination.path,
            addedAtMs: savedAt,
            byteSize: downloaded.byteSize,
            rights: item.rights.label,
            attribution: item.attribution,
            sourceUrl: item.url,
          ),
        );
        registered = true;
        await _persistVideos();
      }
      configuredDownloadErrorMessage = null;
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Configured media download failed for ${item.id}: $error\n$stackTrace',
      );
      if (registered) {
        tracks = tracks.where((track) => track.id != trackId).toList();
        videoTracks = videoTracks
            .where((video) => video.id != trackId)
            .toList();
        try {
          if (item.category == MediaDownloadCategory.music) {
            await _persistTracks();
          } else {
            await _persistVideos();
          }
        } on Object catch (persistError, persistStackTrace) {
          debugPrint(
            'The failed direct download could not be removed from the library: $persistError\n$persistStackTrace',
          );
        }
        registered = false;
      }
      configuredDownloadErrorMessage = error is HttpException
          ? error.message
          : error is FormatException
          ? error.message
          : 'The media file could not be downloaded. Check the URL and your connection.';
      return false;
    } finally {
      if (destination != null && !registered && await destination.exists()) {
        try {
          await destination.delete();
        } on FileSystemException catch (error, stackTrace) {
          debugPrint(
            'Incomplete configured download could not be removed: $error\n$stackTrace',
          );
        }
      }
      downloadingConfiguredIds = {...downloadingConfiguredIds}..remove(key);
      configuredDownloadProgress.remove(key);
      _notify();
    }
  }

  bool hasTrack(MusicResult result) =>
      tracks.any((track) => track.commonsPageId == result.pageId);

  Future<void> setBackgroundAutoRefresh(bool value) async {
    if (!supportsDesktopBackgroundRefresh) return;
    backgroundAutoRefresh = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_backgroundKey, value);
    if (value) {
      _startDesktopRefresh();
      await refreshAnime(silent: true);
    } else {
      _desktopRefreshTimer?.cancel();
      _desktopRefreshTimer = null;
    }
    _notify();
  }

  void _startDesktopRefresh() {
    _desktopRefreshTimer?.cancel();
    _desktopRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (backgroundAutoRefresh) {
        unawaited(refreshAnime(silent: true));
      }
    });
  }

  Future<void> _persistTracks() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _tracksKey,
      jsonEncode(tracks.map((track) => track.toJson()).toList()),
    );
    if (!saved) {
      debugPrint('The music library could not be saved to this device.');
    }
  }

  Future<bool> _saveMusicPlaylistState(
    List<MusicPlaylist> playlists,
    String? selectedId,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _musicPlaylistsKey,
        jsonEncode({
          'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
          'selectedId': selectedId,
        }),
      );
      if (!saved) throw StateError('The music playlists were not saved.');
      musicPlaylists = playlists;
      selectedMusicPlaylistId = selectedId;
      musicErrorMessage = null;
      _notify();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Music playlists could not be saved: $error\n$stackTrace');
      musicErrorMessage =
          'Your playlist changes could not be saved. Musico could not write '
          'to its storage folder.';
      _notify();
      return false;
    }
  }

  Future<bool> createMusicPlaylist(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;
    if (musicPlaylists.any(
      (playlist) => playlist.name.toLowerCase() == normalizedName.toLowerCase(),
    )) {
      musicErrorMessage = 'A playlist with that name already exists.';
      _notify();
      return false;
    }
    final playlist = MusicPlaylist(
      id: 'playlist-${DateTime.now().microsecondsSinceEpoch}',
      name: normalizedName,
      trackIds: const [],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    return _saveMusicPlaylistState([...musicPlaylists, playlist], playlist.id);
  }

  Future<bool> renameMusicPlaylist(String id, String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return false;
    if (musicPlaylists.any(
      (playlist) =>
          playlist.id != id &&
          playlist.name.toLowerCase() == normalizedName.toLowerCase(),
    )) {
      musicErrorMessage = 'A playlist with that name already exists.';
      _notify();
      return false;
    }
    final updated = musicPlaylists
        .map(
          (playlist) => playlist.id == id
              ? playlist.copyWith(name: normalizedName)
              : playlist,
        )
        .toList();
    return _saveMusicPlaylistState(updated, selectedMusicPlaylistId);
  }

  Future<bool> deleteMusicPlaylist(String id) async {
    final updated = musicPlaylists
        .where((playlist) => playlist.id != id)
        .toList();
    if (updated.length == musicPlaylists.length) return false;
    final nextSelectedId = selectedMusicPlaylistId == id
        ? null
        : selectedMusicPlaylistId;
    return _saveMusicPlaylistState(updated, nextSelectedId);
  }

  Future<bool> selectMusicPlaylist(String? id) {
    if (id != null && !musicPlaylists.any((playlist) => playlist.id == id)) {
      musicErrorMessage = 'That playlist is no longer available.';
      _notify();
      return Future.value(false);
    }
    return _saveMusicPlaylistState(musicPlaylists, id);
  }

  Future<bool> addTrackToPlaylist(String playlistId, String trackId) =>
      _setTrackPlaylistMembership(playlistId, trackId, add: true);

  Future<bool> removeTrackFromPlaylist(String playlistId, String trackId) =>
      _setTrackPlaylistMembership(playlistId, trackId, add: false);

  Future<bool> _setTrackPlaylistMembership(
    String playlistId,
    String trackId, {
    required bool add,
  }) {
    final updated = musicPlaylists.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      final trackIds = playlist.trackIds.toSet();
      if (add) {
        trackIds.add(trackId);
      } else {
        trackIds.remove(trackId);
      }
      return playlist.copyWith(trackIds: trackIds.toList());
    }).toList();
    if (!updated.any((playlist) => playlist.id == playlistId) ||
        !tracks.any((track) => track.id == trackId)) {
      musicErrorMessage = 'The track or playlist could not be found.';
      _notify();
      return Future.value(false);
    }
    return _saveMusicPlaylistState(updated, selectedMusicPlaylistId);
  }

  Future<void> _persistVideos() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _videosKey,
      jsonEncode(videoTracks.map((video) => video.toJson()).toList()),
    );
  }

  Future<void> _persistWatchlist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _watchlistKey,
      jsonEncode(watchlist.map((title) => title.toJson()).toList()),
    );
  }

  Future<void> createBackup() async {
    if (isCreatingBackup || isRestoringBackup) return;
    isCreatingBackup = true;
    backupMessage = null;
    backupErrorMessage = null;
    _notify();

    Directory? operationDirectory;
    File? archiveFile;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      operationDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}musico-backup-${DateTime.now().microsecondsSinceEpoch}',
      );
      await operationDirectory.create(recursive: true);

      final assets = <BackupAsset>[];
      final trackEntries = <Map<String, dynamic>>[];
      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final path = _backupAssetPath('music', index, track.path);
        final metadata = track.toJson()..remove('path');
        final artworkPath = track.artworkPath;
        metadata.remove('artworkPath');
        final artworkFile = artworkPath == null ? null : File(artworkPath);
        String? artworkArchivePath;
        if (artworkFile != null && await artworkFile.exists()) {
          artworkArchivePath = _backupAssetPath(
            'artwork',
            index,
            artworkFile.path,
          );
        }
        trackEntries.add({
          'track': metadata,
          'archivePath': path,
          'artworkArchivePath': artworkArchivePath,
        });
        assets.add(BackupAsset(archivePath: path, file: File(track.path)));
        if (artworkArchivePath != null && artworkFile != null) {
          assets.add(
            BackupAsset(archivePath: artworkArchivePath, file: artworkFile),
          );
        }
      }

      final videoEntries = <Map<String, dynamic>>[];
      for (var index = 0; index < videoTracks.length; index++) {
        final video = videoTracks[index];
        final path = _backupAssetPath('videos', index, video.path);
        final metadata = video.toJson()..remove('path');
        videoEntries.add({'video': metadata, 'archivePath': path});
        assets.add(BackupAsset(archivePath: path, file: File(video.path)));
      }

      final downloadConfig = mediaDownloadConfig;
      if (downloadConfig == null) {
        throw StateError('The direct download links are not available.');
      }
      final manifest = <String, dynamic>{
        'format': 'side-b-backup',
        'schemaVersion': 4,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'settings': {
          'backgroundAutoRefresh': backgroundAutoRefresh,
          'notificationsEnabled': notificationsEnabled,
          'sortAlphabetically': sortAlphabetically,
          'shuffle': shuffle,
          'repeatOne': repeatOne,
          'autoplay': autoplay,
          'volume': volume,
        },
        'watchlist': watchlist.map((title) => title.toJson()).toList(),
        'seasonTitles': seasonTitles.map((title) => title.toJson()).toList(),
        'upcomingTitles': upcomingTitles
            .map((title) => title.toJson())
            .toList(),
        'tracks': trackEntries,
        'musicPlaylists': musicPlaylists
            .map((playlist) => playlist.toJson())
            .toList(),
        'selectedMusicPlaylistId': selectedMusicPlaylistId,
        'videoTracks': videoEntries,
        'mediaDownloads': downloadConfig.encode(),
        'spotifyPlaylists': spotifyPlaylists
            .map((playlist) => playlist.toJson())
            .toList(),
      };
      archiveFile = await _backupService.createArchive(
        temporaryDirectory: operationDirectory,
        manifest: manifest,
        assets: assets,
      );

      final destination = await FilePicker.saveFile(
        dialogTitle: 'Save Musico backup',
        fileName:
            'side-b-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip',
        bytes: Uint8List(0),
        mimeType: 'application/zip',
      );
      if (destination == null) return;
      if (Platform.isAndroid) {
        await _backupChannel.invokeMethod<void>('copyBackupToUri', {
          'sourcePath': archiveFile.path,
          'targetUri': destination.toString(),
        });
      } else if (destination.scheme == 'file') {
        final output = File(destination.toFilePath());
        await output.parent.create(recursive: true);
        final sink = output.openWrite();
        try {
          await sink.addStream(archiveFile.openRead());
          await sink.flush();
        } finally {
          await sink.close();
        }
      } else {
        throw const FormatException(
          'The selected backup destination is not a local file.',
        );
      }
      backupMessage =
          'Backup saved with settings, release data, and local media.';
    } on Object catch (error, stackTrace) {
      debugPrint('Musico backup failed: $error\n$stackTrace');
      backupErrorMessage = 'The backup could not be saved. Check storage access and available space.';
    } finally {
      if (archiveFile != null && await archiveFile.exists()) {
        await archiveFile.delete();
      }
      if (operationDirectory != null && await operationDirectory.exists()) {
        try {
          await operationDirectory.delete(recursive: true);
        } on FileSystemException catch (error, stackTrace) {
          debugPrint(
            'Backup temporary files could not be removed: $error\n$stackTrace',
          );
        }
      }
      isCreatingBackup = false;
      _notify();
    }
  }

  Future<void> restoreBackup() async {
    if (isCreatingBackup || isRestoringBackup) return;
    isRestoringBackup = true;
    backupMessage = null;
    backupErrorMessage = null;
    settingsErrorMessage = null;
    _notify();

    Directory? operationDirectory;
    final createdFiles = <File>[];
    String? downloadPathToRestore;
    String? originalDownloadConfig;
    bool downloadConfigReplaced = false;
    SharedPreferences? preferencesToRestore;
    Map<String, Object?>? originalPreferences;
    bool preferenceWritesStarted = false;
    bool restoreCommitted = false;
    try {
      final selectedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (selectedFiles.isEmpty) return;

      final temporaryDirectory = await getTemporaryDirectory();
      operationDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}musico-restore-${DateTime.now().microsecondsSinceEpoch}',
      );
      await operationDirectory.create(recursive: true);
      final archiveFile = File(
        '${operationDirectory.path}${Platform.pathSeparator}restore.zip',
      );
      final picked = selectedFiles.first;
      final pickedPath = picked.path;
      if (pickedPath != null && await File(pickedPath).exists()) {
        await File(pickedPath).copy(archiveFile.path);
      } else {
        final sink = archiveFile.openWrite();
        try {
          await sink.addStream(picked.xFile.openRead());
        } finally {
          await sink.close();
        }
      }

      final restored = await _backupService.extractArchive(
        archiveFile: archiveFile,
        stagingDirectory: Directory(
          '${operationDirectory.path}${Platform.pathSeparator}staged-media',
        ),
      );
      final manifest = restored.manifest;
      if (manifest['format'] != 'side-b-backup' ||
          !{1, 2, 3, 4}.contains(manifest['schemaVersion'])) {
        throw const FormatException('This is not a supported Musico backup.');
      }

      final settings = manifest['settings'];
      if (settings is! Map<String, dynamic>) {
        throw const FormatException('The backup settings are missing.');
      }
      bool settingBool(String key) {
        final value = settings[key];
        if (value is! bool) {
          throw FormatException('The backup setting "$key" is invalid.');
        }
        return value;
      }

      final restoredBackgroundRefresh =
          supportsDesktopBackgroundRefresh &&
          settingBool('backgroundAutoRefresh');
      var restoredNotificationsEnabled = settingBool('notificationsEnabled');
      final restoredSort = settingBool('sortAlphabetically');
      final restoredShuffle = settingBool('shuffle');
      final restoredRepeatOne = settingBool('repeatOne');
      final rawAutoplay = settings['autoplay'];
      if (rawAutoplay != null && rawAutoplay is! bool) {
        throw const FormatException('The backup autoplay setting is invalid.');
      }
      final restoredAutoplay = rawAutoplay as bool? ?? true;
      final rawVolume = settings['volume'];
      if (rawVolume is! num || !rawVolume.isFinite) {
        throw const FormatException('The backup volume setting is invalid.');
      }
      final restoredVolume = rawVolume.toDouble().clamp(0, 1).toDouble();

      final rawDownloadConfig = manifest['mediaDownloads'];
      final restoredDownloadConfig = rawDownloadConfig is String
          ? MediaDownloadConfig.decode(rawDownloadConfig)
          : rawDownloadConfig == null && manifest['schemaVersion'] == 1
          ? MediaDownloadConfig.empty()
          : throw const FormatException(
              'The direct download links are missing from the backup.',
            );

      final rawSpotifyPlaylists = manifest['spotifyPlaylists'];
      final restoredSpotifyPlaylists = rawSpotifyPlaylists is List
          ? [
              for (final playlist in rawSpotifyPlaylists)
                if (playlist case final Map<String, dynamic> map)
                  SpotifyPlaylist.fromJson(map)
                else
                  throw const FormatException(
                    'The backup contains invalid Spotify playlist metadata.',
                  ),
            ]
          : rawSpotifyPlaylists == null &&
                (manifest['schemaVersion'] as int) < 3
          ? <SpotifyPlaylist>[]
          : throw const FormatException(
              'The Spotify playlist metadata is missing from the backup.',
            );

      final rawMusicPlaylists = manifest['musicPlaylists'];
      final restoredMusicPlaylists = rawMusicPlaylists is List
          ? [
              for (final playlist in rawMusicPlaylists)
                if (playlist case final Map<String, dynamic> map)
                  MusicPlaylist.fromJson(map)
                else
                  throw const FormatException(
                    'The backup contains invalid music playlists.',
                  ),
            ]
          : rawMusicPlaylists == null && (manifest['schemaVersion'] as int) < 4
          ? <MusicPlaylist>[]
          : throw const FormatException(
              'The music playlist metadata is missing from the backup.',
            );
      final rawSelectedPlaylistId = manifest['selectedMusicPlaylistId'];
      if (rawSelectedPlaylistId != null && rawSelectedPlaylistId is! String) {
        throw const FormatException('The selected music playlist is invalid.');
      }
      final restoredSelectedPlaylistId =
          restoredMusicPlaylists.any(
            (playlist) => playlist.id == rawSelectedPlaylistId,
          )
          ? rawSelectedPlaylistId as String?
          : null;

      List<MediaTitle> decodeMediaList(String key) {
        final values = manifest[key];
        if (values is! List) {
          throw FormatException('The backup section "$key" is invalid.');
        }
        return [
          for (final value in values)
            if (value case final Map<String, dynamic> map)
              MediaTitle.fromStoredJson(map)
            else
              throw FormatException('The backup section "$key" is invalid.'),
        ];
      }

      final restoredWatchlist = decodeMediaList('watchlist');
      final restoredSeasonTitles = decodeMediaList('seasonTitles');
      final restoredUpcomingTitles = decodeMediaList('upcomingTitles');

      final rawTracks = manifest['tracks'];
      final rawVideos = manifest['videoTracks'];
      if (rawTracks is! List || rawVideos is! List) {
        throw const FormatException('The backup media lists are invalid.');
      }

      final expectedAssetPaths = <String>{};
      final pendingTracks =
          <({Map<String, dynamic> json, File file, File? artworkFile})>[];
      for (final entry in rawTracks) {
        if (entry is! Map<String, dynamic> ||
            entry['track'] is! Map<String, dynamic> ||
            entry['archivePath'] is! String) {
          throw const FormatException(
            'The backup contains invalid music data.',
          );
        }
        final archivePath = entry['archivePath'] as String;
        if (!archivePath.startsWith('media/music/') ||
            !expectedAssetPaths.add(archivePath)) {
          throw const FormatException(
            'The backup contains an invalid music path.',
          );
        }
        final asset = restored.assets[archivePath];
        if (asset == null) {
          throw const FormatException(
            'A music file is missing from the backup.',
          );
        }
        final metadata = Map<String, dynamic>.from(
          entry['track'] as Map<String, dynamic>,
        );
        final rawArtworkArchivePath = entry['artworkArchivePath'];
        File? artworkFile;
        if (rawArtworkArchivePath != null) {
          if (rawArtworkArchivePath is! String ||
              !rawArtworkArchivePath.startsWith('media/artwork/') ||
              !expectedAssetPaths.add(rawArtworkArchivePath)) {
            throw const FormatException(
              'The backup contains an invalid artwork path.',
            );
          }
          artworkFile = restored.assets[rawArtworkArchivePath];
          if (artworkFile == null) {
            throw const FormatException(
              'An artwork file is missing from the backup.',
            );
          }
        }
        pendingTracks.add((
          json: metadata,
          file: asset,
          artworkFile: artworkFile,
        ));
      }

      final pendingVideos = <({Map<String, dynamic> json, File file})>[];
      for (final entry in rawVideos) {
        if (entry is! Map<String, dynamic> ||
            entry['video'] is! Map<String, dynamic> ||
            entry['archivePath'] is! String) {
          throw const FormatException(
            'The backup contains invalid video data.',
          );
        }
        final archivePath = entry['archivePath'] as String;
        if (!archivePath.startsWith('media/videos/') ||
            !expectedAssetPaths.add(archivePath)) {
          throw const FormatException(
            'The backup contains an invalid video path.',
          );
        }
        final asset = restored.assets[archivePath];
        if (asset == null) {
          throw const FormatException(
            'A video file is missing from the backup.',
          );
        }
        final metadata = Map<String, dynamic>.from(
          entry['video'] as Map<String, dynamic>,
        );
        pendingVideos.add((json: metadata, file: asset));
      }
      if (expectedAssetPaths.length != restored.assets.length) {
        throw const FormatException(
          'The backup contains media that is not listed in its manifest.',
        );
      }
      final restoredTrackIds = pendingTracks
          .map((pending) => pending.json['id'])
          .whereType<String>()
          .toSet();
      if (restoredMusicPlaylists.any(
        (playlist) => playlist.trackIds.any(
          (trackId) => !restoredTrackIds.contains(trackId),
        ),
      )) {
        throw const FormatException(
          'The backup contains playlists that refer to missing tracks.',
        );
      }

      if (restoredNotificationsEnabled &&
          (!notificationsAvailable || !_notificationsInitialized)) {
        restoredNotificationsEnabled = false;
      } else if (restoredNotificationsEnabled && Platform.isAndroid) {
        final android = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        restoredNotificationsEnabled =
            await android?.requestNotificationsPermission() ?? false;
      }

      final musicDirectory = await _mediaStorageDirectory('music');
      final artworkDirectory = await _mediaStorageDirectory('artwork');
      final videosDirectory = await _mediaStorageDirectory('videos');
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final restoredTracks = <MusicTrack>[];
      for (var index = 0; index < pendingTracks.length; index++) {
        final pending = pendingTracks[index];
        final destination = File(
          '${musicDirectory.path}${Platform.pathSeparator}restore-$stamp-${index.toString().padLeft(6, '0')}${_backupExtension(pending.file.path)}',
        );
        await pending.file.copy(destination.path);
        createdFiles.add(destination);
        File? artworkDestination;
        if (pending.artworkFile case final artworkFile?) {
          artworkDestination = File(
            '${artworkDirectory.path}${Platform.pathSeparator}restore-$stamp-${index.toString().padLeft(6, '0')}${_backupExtension(artworkFile.path)}',
          );
          await artworkFile.copy(artworkDestination.path);
          createdFiles.add(artworkDestination);
        }
        restoredTracks.add(
          MusicTrack.fromJson({
            ...pending.json,
            'path': destination.path,
            'artworkPath': artworkDestination?.path,
            'byteSize': await destination.length(),
          }),
        );
      }

      final restoredVideos = <VideoTrack>[];
      for (var index = 0; index < pendingVideos.length; index++) {
        final pending = pendingVideos[index];
        final destination = File(
          '${videosDirectory.path}${Platform.pathSeparator}restore-$stamp-${index.toString().padLeft(6, '0')}${_backupExtension(pending.file.path)}',
        );
        await pending.file.copy(destination.path);
        createdFiles.add(destination);
        restoredVideos.add(
          VideoTrack.fromJson({
            ...pending.json,
            'path': destination.path,
            'byteSize': await destination.length(),
          }),
        );
      }

      final downloadPath = mediaDownloadConfigPath;
      if (downloadPath == null) {
        throw StateError('The direct download links are not initialized.');
      }
      downloadPathToRestore = downloadPath;
      originalDownloadConfig = await File(downloadPath).readAsString();

      final preferences = await SharedPreferences.getInstance();
      preferencesToRestore = preferences;
      originalPreferences = {
        _tracksKey: preferences.getString(_tracksKey),
        _videosKey: preferences.getString(_videosKey),
        _spotifyPlaylistsKey: preferences.getString(_spotifyPlaylistsKey),
        _musicPlaylistsKey: preferences.getString(_musicPlaylistsKey),
        _watchlistKey: preferences.getString(_watchlistKey),
        _seasonCacheKey: preferences.getString(_seasonCacheKey),
        _upcomingCacheKey: preferences.getString(_upcomingCacheKey),
        _backgroundKey: preferences.getBool(_backgroundKey),
        _notificationPermissionKey: preferences.getBool(
          _notificationPermissionKey,
        ),
        _sortAlphabeticallyKey: preferences.getBool(_sortAlphabeticallyKey),
        _shuffleKey: preferences.getBool(_shuffleKey),
        _repeatOneKey: preferences.getBool(_repeatOneKey),
        _autoplayKey: preferences.getBool(_autoplayKey),
        _volumeKey: preferences.getDouble(_volumeKey),
      };

      downloadConfigReplaced = true;
      await File(downloadPath)
          .writeAsString(restoredDownloadConfig.encode(), flush: true);

      preferenceWritesStarted = true;
      final preferenceWrites = await Future.wait([
        preferences.setString(
          _tracksKey,
          jsonEncode(restoredTracks.map((track) => track.toJson()).toList()),
        ),
        preferences.setString(
          _videosKey,
          jsonEncode(restoredVideos.map((video) => video.toJson()).toList()),
        ),
        preferences.setString(
          _spotifyPlaylistsKey,
          jsonEncode(
            restoredSpotifyPlaylists
                .map((playlist) => playlist.toJson())
                .toList(),
          ),
        ),
        preferences.setString(
          _musicPlaylistsKey,
          jsonEncode({
            'playlists': restoredMusicPlaylists
                .map((playlist) => playlist.toJson())
                .toList(),
            'selectedId': restoredSelectedPlaylistId,
          }),
        ),
        preferences.setString(
          _watchlistKey,
          jsonEncode(restoredWatchlist.map((title) => title.toJson()).toList()),
        ),
        preferences.setString(
          _seasonCacheKey,
          jsonEncode(
            restoredSeasonTitles.map((title) => title.toJson()).toList(),
          ),
        ),
        preferences.setString(
          _upcomingCacheKey,
          jsonEncode(
            restoredUpcomingTitles.map((title) => title.toJson()).toList(),
          ),
        ),
        preferences.setBool(_backgroundKey, restoredBackgroundRefresh),
        preferences.setBool(
          _notificationPermissionKey,
          restoredNotificationsEnabled,
        ),
        preferences.setBool(_sortAlphabeticallyKey, restoredSort),
        preferences.setBool(_shuffleKey, restoredShuffle),
        preferences.setBool(_repeatOneKey, restoredRepeatOne),
        preferences.setBool(_autoplayKey, restoredAutoplay),
        preferences.setDouble(_volumeKey, restoredVolume),
      ]);
      if (preferenceWrites.any((saved) => !saved)) {
        throw StateError(
          'One or more restored preferences could not be saved.',
        );
      }
      restoreCommitted = true;

      try {
        await player.stop();
      } on Object catch (error, stackTrace) {
        debugPrint(
          'Current audio could not be stopped during restore: $error\n$stackTrace',
        );
        settingsErrorMessage =
            'The backup was restored, but current audio could not be stopped.';
      }
      try {
        final videoPlayer = _videoPlayer;
        if (videoPlayer != null) await videoPlayer.stop();
        await _setPictureInPictureEnabled(false);
      } on Object catch (error, stackTrace) {
        debugPrint(
          'Current video could not be stopped during restore: $error\n$stackTrace',
        );
        settingsErrorMessage =
            'The backup was restored, but current video could not be stopped.';
      }
      currentTrack = null;
      currentVideo = null;
      lyrics = null;
      lyricsStatus = LyricsStatus.idle;
      tracks = restoredTracks;
      videoTracks = restoredVideos;
      spotifyPlaylists = restoredSpotifyPlaylists;
      musicPlaylists = restoredMusicPlaylists;
      selectedMusicPlaylistId = restoredSelectedPlaylistId;
      watchlist = restoredWatchlist;
      seasonTitles = restoredSeasonTitles;
      upcomingTitles = restoredUpcomingTitles;
      backgroundAutoRefresh = restoredBackgroundRefresh;
      notificationsEnabled = restoredNotificationsEnabled;
      sortAlphabetically = restoredSort;
      shuffle = restoredShuffle;
      repeatOne = restoredRepeatOne;
      autoplay = restoredAutoplay;
      volume = restoredVolume;
      mediaDownloadConfig = restoredDownloadConfig;
      mediaDownloadErrorMessage = null;
      try {
        await player.setVolume(volume);
      } on Object catch (error, stackTrace) {
        debugPrint(
          'Restored playback volume could not be applied: $error\n$stackTrace',
        );
        settingsErrorMessage = 'The backup was restored, but the playback volume could not be applied.';
      }
      if (backgroundAutoRefresh) {
        _startDesktopRefresh();
      } else {
        _desktopRefreshTimer?.cancel();
        _desktopRefreshTimer = null;
      }
      if (notificationsEnabled) {
        await syncWatchlistNotifications();
      } else if (_notificationsInitialized) {
        try {
          await _notifications.cancelAll();
        } on Object catch (error, stackTrace) {
          debugPrint(
            'Restored notifications could not be cleared: $error\n$stackTrace',
          );
          settingsErrorMessage = 'The backup was restored, but notifications could not be updated.';
        }
      }
      backupMessage = restoredNotificationsEnabled
          ? 'Backup restored, including local media and settings.'
          : 'Backup restored. Re-enable notifications in Settings if you want reminders.';
    } on Object catch (error, stackTrace) {
      debugPrint('Musico backup restore failed: $error\n$stackTrace');
      var rollbackFailed = false;
      if (!restoreCommitted &&
          preferenceWritesStarted &&
          preferencesToRestore != null &&
          originalPreferences != null) {
        try {
          for (final entry in originalPreferences.entries) {
            final value = entry.value;
            final preferences = preferencesToRestore;
            if (value is String) {
              if (!await preferences.setString(entry.key, value)) {
                rollbackFailed = true;
              }
            } else if (value is bool) {
              if (!await preferences.setBool(entry.key, value)) {
                rollbackFailed = true;
              }
            } else if (value is double) {
              if (!await preferences.setDouble(entry.key, value)) {
                rollbackFailed = true;
              }
            } else if (value == null && !await preferences.remove(entry.key)) {
              rollbackFailed = true;
            }
          }
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'The original settings could not be restored: $rollbackError\n$rollbackStackTrace',
          );
          rollbackFailed = true;
        }
      }
      if (!restoreCommitted &&
          downloadConfigReplaced &&
          downloadPathToRestore != null &&
          originalDownloadConfig != null) {
        try {
          await File(downloadPathToRestore)
              .writeAsString(originalDownloadConfig, flush: true);
        } on Object catch (rollbackError, rollbackStackTrace) {
          debugPrint(
            'The original download links could not be restored: $rollbackError\n$rollbackStackTrace',
          );
          rollbackFailed = true;
        }
      }
      backupErrorMessage = error is FormatException
          ? error.message
          : rollbackFailed
          ? 'Restore failed and rollback could not finish. Check your saved library and download links.'
          : 'The backup could not be restored. Your saved library was left unchanged.';
      if (!restoreCommitted) {
        for (final file in createdFiles) {
          try {
            if (await file.exists()) await file.delete();
          } on FileSystemException catch (cleanupError, cleanupStackTrace) {
            debugPrint(
              'Restored media staging file could not be removed: $cleanupError\n$cleanupStackTrace',
            );
          }
        }
      }
    } finally {
      if (operationDirectory != null && await operationDirectory.exists()) {
        try {
          await operationDirectory.delete(recursive: true);
        } on FileSystemException catch (error, stackTrace) {
          debugPrint(
            'Restore temporary files could not be removed: $error\n$stackTrace',
          );
        }
      }
      isRestoringBackup = false;
      _notify();
    }
  }

  String _backupAssetPath(String category, int index, String filePath) {
    final extension = _backupExtension(filePath);
    return 'media/$category/${index.toString().padLeft(6, '0')}$extension';
  }

  String _backupExtension(String filePath) {
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    final match = RegExp(r'\.([A-Za-z0-9]{1,10})$').firstMatch(fileName);
    return match == null ? '.bin' : '.${match.group(1)}';
  }

  Future<void> _loadMediaDownloadConfig() async {
    final support = await getApplicationSupportDirectory();
    final file = File(
      '${support.path}${Platform.pathSeparator}media_downloads.json',
    );
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        await rootBundle.loadString('config/media_downloads.json'),
        flush: true,
      );
    }
    mediaDownloadConfigPath = file.path;
    MediaDownloadConfig config;
    try {
      config = MediaDownloadConfig.decode(await file.readAsString());
    } on FormatException {
      // The stored file is not a download links file (for example another
      // import overwrote it). Keep a copy, then restore the bundled defaults
      // so the rest of the app keeps working.
      final backup = File(
        '${support.path}${Platform.pathSeparator}'
        'media_downloads.invalid.json',
      );
      await file.copy(backup.path);
      await file.writeAsString(
        await rootBundle.loadString('config/media_downloads.json'),
        flush: true,
      );
      debugPrint(
        'Direct media links were reset to the bundled defaults. '
        'The previous file was kept at ${backup.path}',
      );
      config = MediaDownloadConfig.decode(await file.readAsString());
    }
    mediaDownloadConfig = config;
    mediaDownloadErrorMessage = null;
  }

  Future<void> reloadMediaDownloadConfig() async {
    try {
      await _loadMediaDownloadConfig();
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Direct media links could not be reloaded: $error\n$stackTrace',
      );
      mediaDownloadConfig = null;
      mediaDownloadErrorMessage =
          'The download links file has invalid JSON or an unsupported URL.';
    }
    _notify();
  }

  Future<void> openMediaDownloadConfig() async {
    final path = mediaDownloadConfigPath;
    if (!Platform.isWindows || path == null) {
      mediaDownloadErrorMessage =
          'Use Import links on this device to load your edited JSON file.';
      _notify();
      return;
    }
    try {
      await Process.start('notepad.exe', [
        path,
      ], mode: ProcessStartMode.detached);
      mediaDownloadErrorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Download links file could not be opened: $error\n$stackTrace',
      );
      mediaDownloadErrorMessage =
          'The download links file could not be opened.';
    }
    _notify();
  }

  Future<void> importMediaDownloadConfig() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final contents = await files.first.xFile.readAsString();
      final config = MediaDownloadConfig.decode(contents);
      final path = mediaDownloadConfigPath;
      if (path == null) {
        throw StateError('The download links file has not been initialized.');
      }
      final temporary = File('$path.importing');
      await temporary.writeAsString(config.encode(), flush: true);
      await File(path).writeAsBytes(await temporary.readAsBytes(), flush: true);
      await temporary.delete();
      mediaDownloadConfig = config;
      mediaDownloadErrorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint('Download links could not be imported: $error\n$stackTrace');
      mediaDownloadErrorMessage = error is FormatException
          ? error.message
          : 'The download links file could not be imported.';
    }
    _notify();
  }

  Future<void> exportMediaDownloadConfig() async {
    final path = mediaDownloadConfigPath;
    if (path == null) {
      mediaDownloadErrorMessage = 'The download links file is not available.';
      _notify();
      return;
    }
    try {
      final contents = await File(path).readAsString();
      await FilePicker.saveFile(
        fileName: 'media_downloads.json',
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Download links could not be exported: $error\n$stackTrace');
      mediaDownloadErrorMessage =
          'The download links file could not be exported.';
    }
    _notify();
  }

  Future<void> _saveBooleanPreference(
    String key,
    bool value,
    String label,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(key, value);
      if (!saved) throw StateError('The preference was not saved.');
      settingsErrorMessage = null;
    } on Object catch (error, stackTrace) {
      debugPrint(
        'The $label preference could not be saved: $error\n$stackTrace',
      );
      settingsErrorMessage = 'The $label preference could not be saved.';
    }
  }

  void setOnline(bool online) {
    isOnline = online;
    hasNetworkConnection = online;
    if (online && supportsDesktopBackgroundRefresh && backgroundAutoRefresh) {
      unawaited(refreshAnime(silent: true));
    }
    _notify();
  }

  String get currentSeasonLabel {
    final season = _currentSeason(DateTime.now());
    final formattedSeason = (season['season'] as String).toLowerCase();
    return '${formattedSeason[0].toUpperCase()}${formattedSeason.substring(1)} ${season['year']}';
  }

  void dismissError() {
    errorMessage = null;
    musicErrorMessage = null;
    _notify();
  }

  void dismissSettingsError() {
    settingsErrorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scheduleWindowsMediaControlsSync();
    _desktopRefreshTimer?.cancel();
    _notificationTimer?.cancel();
    _volumePersistTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    _youtubeDownloadService.dispose();
    _client.close();
    unawaited(player.dispose());
    final videoPlayer = _videoPlayer;
    if (videoPlayer != null) unawaited(videoPlayer.dispose());
    super.dispose();
  }
}
