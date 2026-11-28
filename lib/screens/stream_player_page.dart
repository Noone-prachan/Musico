import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/anime_stream.dart';
import '../models/stream_watch_progress.dart';
import '../models/watch_media.dart';
import '../services/anime_stream_service.dart';
import '../services/hls_playlist.dart';
import '../services/stream_watch_progress_service.dart';
import '../theme/app_theme.dart';

class PlayerEpisode {
  const PlayerEpisode({
    required this.label,
    required this.resolve,
    this.title,
    this.id,
    this.season,
    this.episodeNumber,
  });

  final String label;

  final String? title;

  final String? id;
  final int? season;
  final int? episodeNumber;

  final Future<AnimeStreamSource> Function() resolve;
}

class StreamPlayerPage extends StatefulWidget {
  const StreamPlayerPage({
    required this.title,
    required this.episodes,
    required this.initialIndex,
    required this.category,
    this.preferredAudioLanguage = 'en',
    required this.catalogId,
    this.badge,
    this.posterUrl,
    this.initialPositionMs = 0,
    super.key,
  });

  final String title;
  final String preferredAudioLanguage;
  final String? badge;
  final String? posterUrl;
  final List<PlayerEpisode> episodes;
  final int initialIndex;
  final StreamWatchCategory category;
  final String catalogId;
  final int initialPositionMs;

  @override
  State<StreamPlayerPage> createState() => _StreamPlayerPageState();
}

class _StreamPlayerPageState extends State<StreamPlayerPage> {
  static const Color _playerForeground = Color(0xFFF9F6EE);
  static const Color _playerMuted = Color(0xFFD2CCC2);
  static const MethodChannel _pictureInPictureChannel = MethodChannel(
    'sideb/picture_in_picture',
  );

  late final Player _player;
  late final VideoController _controller;
  late final _StreamPlaybackHandler _backgroundHandler;
  late int _index;
  AnimeStreamSource? _source;
  HlsPlaylist _playlist = HlsPlaylist.empty;
  int? _selectedBitrate;
  bool _loading = true;
  String? _error;
  String _selectedSubtitleId = 'auto';
  bool _muted = false;
  double _volume = 100;
  bool _controlsVisible = true;
  bool _isClosing = false;
  bool _hasLoadedEpisode = false;
  bool _progressSaveFailed = false;
  bool _subtitleSelectionMade = false;
  int _loadGeneration = 0;
  Future<void>? _progressSave;
  final StreamWatchProgressService _progressService =
      StreamWatchProgressService();
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _watchdog;
  Timer? _frameTimer;
  Timer? _controlsTimer;
  Timer? _progressTimer;
  Timer? _backgroundTimer;

  PlayerEpisode get _episode => widget.episodes[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.episodes.length - 1);
    _player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
    );
    _controller = VideoController(_player);
    _backgroundHandler = _StreamPlaybackHandler(
      _player.play,
      _player.pause,
      _player.seek,
      _close,
      _skipToNext,
      _skipToPrevious,
    );
    _playingSub = _player.stream.playing.listen((playing) {
      _publishBackgroundState();
      if (playing) {
        _scheduleControlsHide();
      } else {
        _controlsTimer?.cancel();
        unawaited(_saveProgress());
        if (mounted && !_controlsVisible) {
          setState(() => _controlsVisible = true);
        }
      }
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) unawaited(_handleCompleted());
    });
    _errorSub = _player.stream.error.listen((message) {
      if (!mounted || message.trim().isEmpty) return;
      if (_player.state.position > Duration.zero ||
          _player.state.duration > Duration.zero) {
        debugPrint('media_kit: $message');
        return;
      }
      _watchdog?.cancel();
      setState(() {
        _loading = false;
        _error ??= 'The stream could not be played.\n$message';
      });
    });
    unawaited(_load(_index));
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _backgroundTimer?.cancel();
    if (_hasLoadedEpisode) unawaited(_saveProgress());
    if (Platform.isAndroid) {
      _backgroundHandler.clear();
      JustAudioBackground.restorePlayerAudioHandler();
      unawaited(_setPictureInPictureEnabled(false));
    }
    _watchdog?.cancel();
    _frameTimer?.cancel();
    _controlsTimer?.cancel();
    unawaited(_completedSub?.cancel());
    unawaited(_errorSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _load(int index, {bool saveCurrent = true}) async {
    if (saveCurrent && _hasLoadedEpisode && index != _index) {
      await _saveProgress();
    }
    final generation = ++_loadGeneration;
    _watchdog?.cancel();
    _frameTimer?.cancel();
    _controlsTimer?.cancel();
    _progressTimer?.cancel();
    setState(() {
      _index = index;
      _loading = true;
      _error = null;
      _source = null;
      _playlist = HlsPlaylist.empty;
      _selectedBitrate = null;
      _selectedSubtitleId = 'auto';
      _subtitleSelectionMade = false;
      _controlsVisible = true;
    });
    final episode = widget.episodes[index];
    try {
      final source = await episode.resolve();
      final resumeAt = (index == widget.initialIndex && widget.initialPositionMs > 0)
          ? Duration(milliseconds: widget.initialPositionMs)
          : null;
      await _player
          .open(
            Media(
              source.url,
              start: resumeAt,
              httpHeaders: {
                if (source.referer.isNotEmpty) 'Referer': source.referer,
                'User-Agent': AnimeStreamService.userAgent,
              },
            ),
            play: true,
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw const WatchException(
              'This stream took too long to load. Check your connection and retry.',
            ),
          );
      if (!mounted) return;
      _hasLoadedEpisode = true;
      setState(() => _source = source);
      _startBackgroundSession();
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(_saveProgress());
      });
      _startWatchdog();
      _watchForFirstFrame();
      unawaited(_applyTracks(source, generation));
      unawaited(_loadPlaylistInfo(source, generation));
    } on WatchException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on AnimeStreamException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This video could not be played. ($error)';
      });
    }
  }

  Future<void> _handleCompleted() async {
    await _saveProgress(completed: true);
    if (_index + 1 < widget.episodes.length) {
      await _load(_index + 1, saveCurrent: false);
    }
  }

  Future<void> _skipToNext() async {
    if (_index + 1 < widget.episodes.length) {
      await _load(_index + 1);
    }
  }

  Future<void> _skipToPrevious() async {
    if (_index > 0) {
      await _load(_index - 1);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> _close() async {
    if (_isClosing) return;
    _isClosing = true;
    if (mounted) setState(() {});
    _progressTimer?.cancel();
    await _saveProgress();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveProgress({bool completed = false}) {
    final activeSave = _progressSave;
    if (activeSave != null) {
      return activeSave.then((_) => _saveProgress(completed: completed));
    }
    if (!_hasLoadedEpisode) return Future<void>.value();

    final state = _player.state;
    if (!completed && state.duration <= Duration.zero) {
      return Future<void>.value();
    }
    final episode = _episode;
    final progress = StreamWatchProgress(
      category: widget.category,
      catalogId: widget.catalogId,
      title: widget.title,
      episodeLabel: episode.label,
      episodeId: episode.id,
      episodeTitle: episode.title,
      season: episode.season,
      episodeNumber: episode.episodeNumber,
      episodeIndex: _index,
      positionMs: state.position.inMilliseconds.clamp(0, 1 << 62).toInt(),
      durationMs: state.duration.inMilliseconds.clamp(0, 1 << 62).toInt(),
      lastWatchedAtMs: DateTime.now().millisecondsSinceEpoch,
      posterUrl: widget.posterUrl,
    );
    final future = _writeProgress(progress, completed: completed);
    _progressSave = future;
    return future.whenComplete(() {
      if (identical(_progressSave, future)) _progressSave = null;
    });
  }

  Future<void> _writeProgress(
    StreamWatchProgress progress, {
    required bool completed,
  }) async {
    try {
      await _progressService.save(progress, completed: completed);
      _progressSaveFailed = false;
    } on Exception catch (error, stackTrace) {
      _reportProgressFailure(error, stackTrace);
    } on StateError catch (error, stackTrace) {
      _reportProgressFailure(error, stackTrace);
    }
  }

  void _reportProgressFailure(Object error, StackTrace stackTrace) {
    debugPrint('Stream watch progress could not be saved: $error\n$stackTrace');
    if (!mounted || _progressSaveFailed) return;
    _progressSaveFailed = true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Watch progress could not be saved.')),
    );
  }

  void _startBackgroundSession() {
    if (!Platform.isAndroid) return;
    JustAudioBackground.setExternalAudioHandler(_backgroundHandler);
    _backgroundTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      _publishBackgroundState();
    });
    unawaited(_setPictureInPictureEnabled(true));
    _publishBackgroundState();
  }

  void _publishBackgroundState() {
    if (!Platform.isAndroid || _source == null) return;
    final episode = _episode;
    final poster = widget.posterUrl;
    final posterUri = poster == null ? null : Uri.tryParse(poster);
    _backgroundHandler.publish(
      item: MediaItem(
        id: '${widget.category.name}:${widget.catalogId}:${episode.id ?? _index}',
        title: widget.title,
        album: [
          if (widget.badge != null) widget.badge!,
          episode.label,
        ].join(' · '),
        artist: 'Musico',
        duration: _player.state.duration > Duration.zero
            ? _player.state.duration
            : null,
        artUri: posterUri != null && posterUri.hasScheme ? posterUri : null,
      ),
      playing: _player.state.playing,
      buffering: _loading,
      position: _player.state.position,
      canPrevious: _index > 0,
      canNext: _index + 1 < widget.episodes.length,
    );
  }

  Future<void> _setPictureInPictureEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _pictureInPictureChannel.invokeMethod<void>('setEnabled', {
        'enabled': enabled,
      });
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Picture-in-picture is unavailable: $error\n$stackTrace');
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Picture-in-picture could not be updated: $error\n$stackTrace',
      );
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 45), () {
      if (!mounted || !_loading || _error != null) return;
      if (_player.state.position > Duration.zero ||
          _player.state.duration > Duration.zero) {
        _frameTimer?.cancel();
        setState(() => _loading = false);
        _scheduleControlsHide();
        return;
      }
      setState(() {
        _loading = false;
        _error ??=
            'The stream opened but never started playing. It may be offline '
            'right now — try another episode or hit retry.';
      });
    });
  }

  void _watchForFirstFrame() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted || !_loading) {
        timer.cancel();
        return;
      }
      final state = _player.state;
      if ((state.width ?? 0) <= 0 || (state.height ?? 0) <= 0) return;
      timer.cancel();
      _watchdog?.cancel();
      setState(() => _loading = false);
      _scheduleControlsHide();
    });
  }

  Future<void> _applyTracks(AnimeStreamSource source, int generation) async {
    try {
      final preferred = widget.preferredAudioLanguage.trim().toLowerCase();
      var audioTracks = _player.state.tracks.audio;
      if (audioTracks.where((t) => t.id != 'auto' && t.id != 'no').isEmpty) {
        final loaded = await _player.stream.tracks
            .firstWhere(
              (t) => t.audio.any((a) => a.id != 'auto' && a.id != 'no'),
            )
            .timeout(const Duration(seconds: 15));
        audioTracks = loaded.audio;
      }
      for (final track in audioTracks) {
        final language = track.language?.toLowerCase() ?? '';
        final title = track.title?.toLowerCase() ?? '';
        if (track.id == 'auto' || track.id == 'no') continue;
        if (preferred.isNotEmpty &&
            (language.startsWith(preferred) ||
                title.contains(preferred) ||
                (preferred == 'en' && title.contains('english')))) {
          if (generation != _loadGeneration) return;
          await _player.setAudioTrack(track);
          break;
        }
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Preferred audio track could not be selected: $error\n$stackTrace',
      );
    }
    try {
      if (source.subtitleUrl != null && source.subtitleUrl!.isNotEmpty) {
        final local = await _downloadSubtitle(
          source.subtitleUrl!,
          source.referer,
        );
        if (local != null) {
          if (generation != _loadGeneration || _subtitleSelectionMade) return;
          final track = SubtitleTrack.uri(local, title: 'English');
          await _player.setSubtitleTrack(track);
          if (mounted && generation == _loadGeneration) {
            setState(() => _selectedSubtitleId = track.id);
          }
          return;
        }
      }
      final tracks = _player.state.tracks.subtitle;
      for (final track in tracks) {
        final language = track.language?.toLowerCase() ?? '';
        final title = track.title?.toLowerCase() ?? '';
        if (track.id == 'auto' || track.id == 'no') continue;
        if (language.startsWith('en') || title.contains('english')) {
          if (generation != _loadGeneration || _subtitleSelectionMade) return;
          await _player.setSubtitleTrack(track);
          if (mounted && generation == _loadGeneration) {
            setState(() => _selectedSubtitleId = track.id);
          }
          return;
        }
      }
    } on Exception catch (error, stackTrace) {
      debugPrint(
        'Preferred English subtitles could not be selected: $error\n$stackTrace',
      );
    }
  }

  /// Reads the master playlist so the quality menu can offer real renditions.
  Future<void> _loadPlaylistInfo(
    AnimeStreamSource source,
    int generation,
  ) async {
    if (!source.url.toLowerCase().contains('.m3u8')) return;
    try {
      final response = await http
          .get(
            Uri.parse(source.url),
            headers: {
              if (source.referer.isNotEmpty) 'Referer': source.referer,
              'User-Agent': AnimeStreamService.userAgent,
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      if (!mounted || generation != _loadGeneration) return;
      final playlist = HlsPlaylist.parse(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (playlist.isEmpty || !mounted) return;
      setState(() => _playlist = playlist);
    } on Object catch (error) {
      debugPrint('Playlist details could not be read: $error');
    }
  }

  /// Switches the HLS rendition mpv should load. `null` restores automatic
  /// quality selection.
  Future<void> _selectQuality(int? bitrate) async {
    final platform = _player.platform;
    try {
      if (platform is NativePlayer) {
        await platform.setProperty(
          'hls-bitrate',
          bitrate == null ? 'auto' : '$bitrate',
        );
        if (mounted) setState(() => _selectedBitrate = bitrate);
      }
    } on Object catch (error) {
      debugPrint('Quality could not be changed: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That quality could not be selected.')),
      );
    }
  }

  Future<void> _selectAudio(AudioTrack track) async {
    try {
      await _player.setAudioTrack(track);
      if (mounted) setState(() {});
    } on Object catch (error) {
      debugPrint('Audio track could not be changed: $error');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That audio track is not available.')),
      );
    }
  }

  String _audioTrackLabel(AudioTrack track) {
    final title = track.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final language = track.language?.trim();
    if (language != null && language.isNotEmpty) {
      return _languageName(language);
    }
    return 'Audio ${track.id}';
  }

  static String _languageName(String code) {
    final primary = code.toLowerCase().split(RegExp(r'[-_]')).first;
    const names = {
      'en': 'English',
      'ja': 'Japanese',
      'it': 'Italian',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'pt': 'Portuguese',
      'hi': 'Hindi',
      'ar': 'Arabic',
      'ru': 'Russian',
      'ko': 'Korean',
      'zh': 'Chinese',
      'ta': 'Tamil',
      'te': 'Telugu',
      'id': 'Indonesian',
      'th': 'Thai',
      'pl': 'Polish',
      'tr': 'Turkish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'nb': 'Norwegian',
      'fi': 'Finnish',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'el': 'Greek',
      'he': 'Hebrew',
      'uk': 'Ukrainian',
      'vi': 'Vietnamese',
      'ms': 'Malay',
      'tl': 'Filipino',
      'fil': 'Filipino',
    };
    return names[primary] ?? code.toUpperCase();
  }

  Future<String?> _downloadSubtitle(String url, String referer) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              if (referer.isNotEmpty) 'Referer': referer,
              'User-Agent': AnimeStreamService.userAgent,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final directory = await Directory.systemTemp.createTemp('musico-subs');
      final file = File('${directory.path}${Platform.pathSeparator}subs.vtt');
      await file.writeAsBytes(response.bodyBytes);
      return Uri.file(file.path).toString();
    } on Exception catch (error, stackTrace) {
      debugPrint(
        'External subtitle could not be downloaded: $error\n$stackTrace',
      );
      return null;
    }
  }

  Future<void> _selectSubtitle(
    String id,
    List<SubtitleTrack> availableTracks,
  ) async {
    SubtitleTrack? selectedTrack;
    if (id == 'no') {
      selectedTrack = SubtitleTrack.no();
    } else if (id == 'auto') {
      selectedTrack = SubtitleTrack.auto();
    } else {
      for (final track in availableTracks) {
        if (track.id == id) {
          selectedTrack = track;
          break;
        }
      }
    }
    if (selectedTrack == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('That subtitle track is no longer available.'),
        ),
      );
      return;
    }
    _subtitleSelectionMade = true;
    try {
      await _player.setSubtitleTrack(selectedTrack);
      if (mounted) setState(() => _selectedSubtitleId = id);
    } on Exception catch (error, stackTrace) {
      _subtitleSelectionMade = false;
      debugPrint('Subtitle selection failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('The subtitle track could not be changed.'),
        ),
      );
    }
  }

  String _subtitleTrackLabel(SubtitleTrack track) {
    final title = track.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final language = track.language?.trim();
    if (language != null && language.isNotEmpty) return language;
    return 'Subtitle ${track.id}';
  }

  void _playRelative(int delta) {
    final next = (_index + delta).clamp(0, widget.episodes.length - 1);
    if (next == _index) return;
    unawaited(_load(next));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _isClosing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isClosing) unawaited(_close());
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          return Theme(
            data: _playerTheme(Theme.of(context)),
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Listener(
                  onPointerDown: _handlePointerDown,
                  onPointerHover: (_) {
                    if (!_controlsVisible && !_loading && _error == null) {
                      setState(() => _controlsVisible = true);
                    }
                    _scheduleControlsHide();
                  },
                  onPointerUp: (_) => _scheduleControlsHide(),
                  onPointerCancel: (_) => _scheduleControlsHide(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleControls,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildVideoSurface(context),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _controlsOverlay(
                            _buildTopBar(context, compact: isLandscape),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _controlsOverlay(
                            _buildControls(context, compact: isLandscape),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controlsOverlay(Widget child) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      excluding: !_controlsVisible,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: const Cubic(0.23, 1, 0.32, 1),
          child: child,
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_controlsVisible) _controlsTimer?.cancel();
  }

  void _toggleControls() {
    if (_loading || _error != null) {
      if (!_controlsVisible) setState(() => _controlsVisible = true);
      return;
    }

    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleControlsHide();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (!mounted ||
        !_controlsVisible ||
        !_player.state.playing ||
        _loading ||
        _error != null) {
      return;
    }
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          !_player.state.playing ||
          _loading ||
          _error != null ||
          !_controlsVisible) {
        return;
      }
      setState(() => _controlsVisible = false);
    });
  }

  ThemeData _playerTheme(ThemeData base) {
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: MusicoPalette.forestLight,
        onPrimary: Colors.white,
        surface: Colors.black,
        onSurface: _playerForeground,
      ),
      iconTheme: const IconThemeData(color: _playerForeground),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: const Color(0xFF242521),
        textStyle: const TextStyle(color: _playerForeground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: base.iconButtonTheme.style?.copyWith(
          foregroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.disabled)
                ? _playerMuted
                : _playerForeground,
          ),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: MusicoPalette.forestLight,
        thumbColor: _playerForeground,
        inactiveTrackColor: _playerMuted.withValues(alpha: .48),
        overlayColor: MusicoPalette.forestLight.withValues(alpha: .22),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: _playerForeground,
        displayColor: _playerForeground,
      ),
    );
  }

  Widget _buildVideoSurface(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (_source != null)
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        if (_loading)
          const Center(
            child: CircularProgressIndicator(color: MusicoPalette.forestLight),
          ),
        if (_error != null) Center(child: _buildError(context)),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, {bool compact = false}) {
    final subtitle = [
      if (widget.badge != null) widget.badge!,
      _episode.label,
      if (_episode.title != null && _episode.title != _episode.label)
        _episode.title!,
    ].join(' · ');
    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 2 : 10, 10, compact ? 2 : 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: _playerForeground),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: _playerMuted),
                ),
              ],
            ),
          ),
          StreamBuilder<Tracks>(
            stream: _player.stream.tracks,
            initialData: _player.state.tracks,
            builder: (context, snapshot) {
              final variants = _playlist.variants;
              if (variants.isNotEmpty) {
                return PopupMenuButton<String>(
                  tooltip: 'Video quality',
                  color: const Color(0xFF242521),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'auto') {
                      unawaited(_selectQuality(null));
                      return;
                    }
                    unawaited(_selectQuality(int.tryParse(value)));
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'auto',
                      child: _qualityRow(
                        label: 'Auto',
                        selected: _selectedBitrate == null,
                      ),
                    ),
                    for (final variant in variants)
                      if (variant.bandwidth != null)
                        PopupMenuItem<String>(
                          value: '${variant.bandwidth}',
                          child: _qualityRow(
                            label: variant.label,
                            selected: _selectedBitrate == variant.bandwidth,
                          ),
                        ),
                  ],
                  icon: const Icon(Icons.hd_outlined),
                );
              }
              final videoTracks = snapshot.data?.video ?? const <VideoTrack>[];
              final selectableVideoTracks = videoTracks
                  .where((track) => track.id != 'no' && track.id != 'auto')
                  .toList();
              final currentVideoId = _player.state.track.video.id;
              return PopupMenuButton<String>(
                tooltip: 'Video quality',
                color: const Color(0xFF242521),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (id) {
                  final selected = videoTracks
                      .where((track) => track.id == id)
                      .firstOrNull;
                  if (selected != null) {
                    unawaited(_player.setVideoTrack(selected));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'auto',
                    child: _qualityRow(
                      label: 'Auto',
                      selected: currentVideoId == 'auto',
                    ),
                  ),
                  if (selectableVideoTracks.isEmpty)
                    const PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        'Only one quality available',
                        style: TextStyle(color: _playerMuted),
                      ),
                    ),
                  for (final track in selectableVideoTracks)
                    PopupMenuItem<String>(
                      value: track.id,
                      child: _qualityRow(
                        label: track.h != null && track.h! > 0
                            ? '${track.h}p'
                            : (track.title?.isNotEmpty == true
                                  ? track.title!
                                  : track.id),
                        selected: currentVideoId == track.id,
                      ),
                    ),
                ],
                icon: const Icon(Icons.hd_outlined),
              );
            },
          ),
          StreamBuilder<Tracks>(
            stream: _player.stream.tracks,
            initialData: _player.state.tracks,
            builder: (context, snapshot) {
              final tracks = snapshot.data?.audio ?? const <AudioTrack>[];
              final selectable = tracks
                  .where((track) => track.id != 'no' && track.id != 'auto')
                  .toList();
              final currentId = _player.state.track.audio.id;
              return PopupMenuButton<String>(
                tooltip: 'Audio language',
                color: const Color(0xFF242521),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (id) {
                  if (id == 'auto') {
                    unawaited(_player.setAudioTrack(AudioTrack.auto()));
                    return;
                  }
                  final selected = selectable
                      .where((track) => track.id == id)
                      .firstOrNull;
                  if (selected != null) unawaited(_selectAudio(selected));
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'auto',
                    child: _qualityRow(
                      label: 'Auto',
                      selected: currentId == 'auto',
                    ),
                  ),
                  if (selectable.isEmpty)
                    const PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        'Only one audio track',
                        style: TextStyle(color: _playerMuted),
                      ),
                    ),
                  for (final track in selectable)
                    PopupMenuItem<String>(
                      value: track.id,
                      child: _qualityRow(
                        label: _audioTrackLabel(track),
                        selected: currentId == track.id,
                      ),
                    ),
                ],
                icon: const Icon(Icons.graphic_eq_rounded),
              );
            },
          ),
          StreamBuilder<Tracks>(
            stream: _player.stream.tracks,
            initialData: _player.state.tracks,
            builder: (context, snapshot) {
              final tracks = snapshot.data?.subtitle ?? const <SubtitleTrack>[];
              final selectableTracks = tracks
                  .where((track) => track.id != 'no' && track.id != 'auto')
                  .toList();
              return PopupMenuButton<String>(
                tooltip: 'Captions and subtitles',
                color: const Color(0xFF242521),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (id) => unawaited(_selectSubtitle(id, tracks)),
                itemBuilder: (context) => [
                  _subtitleMenuItem('no', 'Off'),
                  _subtitleMenuItem('auto', 'Auto'),
                  if (selectableTracks.isEmpty)
                    const PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        'No language tracks found',
                        style: TextStyle(color: _playerMuted),
                      ),
                    ),
                  for (final track in selectableTracks)
                    _subtitleMenuItem(track.id, _subtitleTrackLabel(track)),
                ],
                icon: Icon(
                  _selectedSubtitleId == 'no'
                      ? Icons.closed_caption_disabled_rounded
                      : Icons.closed_caption_rounded,
                ),
              );
            },
          ),
          IconButton(
            tooltip: _muted ? 'Unmute' : 'Mute',
            onPressed: () {
              setState(() => _muted = !_muted);
              unawaited(_player.setVolume(_muted ? 0 : _volume));
            },
            icon: Icon(
              _muted || _volume == 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 600)
            SizedBox(
              width: 90,
              child: Slider(
                min: 0,
                max: 100,
                value: _muted ? 0 : _volume,
                onChanged: (value) {
                  setState(() {
                    _volume = value;
                    _muted = value == 0;
                  });
                  unawaited(_player.setVolume(value));
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _qualityRow({required String label, required bool selected}) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: selected
              ? const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: _playerForeground,
                )
              : null,
        ),
        Text(label, style: const TextStyle(color: _playerForeground)),
      ],
    );
  }

  PopupMenuItem<String> _subtitleMenuItem(String id, String label) {
    return PopupMenuItem<String>(
      value: id,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: _selectedSubtitleId == id
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: _playerForeground,
                  )
                : null,
          ),
          Text(label, style: const TextStyle(color: _playerForeground)),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(
        color: const Color(0xE622211F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: _playerForeground),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (widget.episodes.length > 1)
                OutlinedButton(
                  onPressed: _index + 1 < widget.episodes.length
                      ? () => _playRelative(1)
                      : null,
                  child: const Text('Next episode'),
                ),
              FilledButton.icon(
                onPressed: _loading ? null : () => _load(_index),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, {bool compact = false}) {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration>(
          stream: _player.stream.duration,
          initialData: _player.state.duration,
          builder: (context, durationSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = durationSnapshot.data ?? Duration.zero;
            final max = duration.inMilliseconds
                .toDouble()
                .clamp(1.0, double.infinity)
                .toDouble();
            final value = position.inMilliseconds
                .toDouble()
                .clamp(0.0, max)
                .toDouble();
            return StreamBuilder<bool>(
              stream: _player.stream.playing,
              initialData: _player.state.playing,
              builder: (context, playingSnapshot) {
                final playing = playingSnapshot.data ?? false;
                return Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 0 : 8,
                    16,
                    compact ? 4 : 12,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            _format(position),
                            style: const TextStyle(
                              color: _playerMuted,
                              fontSize: 11,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: max,
                              value: value,
                              onChanged: (next) {
                                unawaited(
                                  _player.seek(
                                    Duration(milliseconds: next.round()),
                                  ),
                                );
                              },
                            ),
                          ),
                          Text(
                            _format(duration),
                            style: const TextStyle(
                              color: _playerMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous episode',
                            onPressed: _index > 0
                                ? () => _playRelative(-1)
                                : null,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                          IconButton(
                            tooltip: 'Back 10 seconds',
                            onPressed: () => _player.seek(
                              Duration(
                                milliseconds: (position.inMilliseconds - 10000)
                                    .clamp(0, duration.inMilliseconds),
                              ),
                            ),
                            icon: const Icon(Icons.replay_10_rounded),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: playing ? 'Pause' : 'Play',
                            onPressed: _loading && !playing
                                ? null
                                : () => _player.playOrPause(),
                            style: IconButton.styleFrom(
                              backgroundColor: MusicoPalette.forest,
                              foregroundColor: _playerForeground,
                              disabledBackgroundColor: MusicoPalette.forest
                                  .withValues(alpha: .58),
                              disabledForegroundColor: _playerMuted,
                            ),
                            iconSize: 28,
                            icon: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Forward 10 seconds',
                            onPressed: () => _player.seek(
                              Duration(
                                milliseconds: (position.inMilliseconds + 10000)
                                    .clamp(0, duration.inMilliseconds),
                              ),
                            ),
                            icon: const Icon(Icons.forward_10_rounded),
                          ),
                          IconButton(
                            tooltip: 'Next episode',
                            onPressed: _index + 1 < widget.episodes.length
                                ? () => _playRelative(1)
                                : null,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _StreamPlaybackHandler extends BaseAudioHandler {
  _StreamPlaybackHandler(
    this._onPlay,
    this._onPause,
    this._onSeek,
    this._onStop,
    this._onNext,
    this._onPrevious,
  );

  final Future<void> Function() _onPlay;
  final Future<void> Function() _onPause;
  final Future<void> Function(Duration) _onSeek;
  final Future<void> Function() _onStop;
  final Future<void> Function() _onNext;
  final Future<void> Function() _onPrevious;

  @override
  Future<void> play() => _onPlay();

  @override
  Future<void> pause() => _onPause();

  @override
  Future<void> seek(Duration position) => _onSeek(position);

  @override
  Future<void> stop() => _onStop();

  @override
  Future<void> skipToNext() => _onNext();

  @override
  Future<void> skipToPrevious() => _onPrevious();

  void publish({
    required MediaItem item,
    required bool playing,
    required bool buffering,
    required Duration position,
    required bool canPrevious,
    required bool canNext,
  }) {
    final controls = <MediaControl>[
      if (canPrevious) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      if (canNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];
    final playbackIndex = canPrevious ? 1 : 0;
    final compactIndices = <int>[
      if (canPrevious) 0,
      playbackIndex,
      if (canNext) playbackIndex + 1,
    ];
    mediaItem.add(item);
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: compactIndices,
        systemActions: const {MediaAction.seek},
        processingState: buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
        bufferedPosition: position,
        speed: 1,
      ),
    );
  }

  void clear() {
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }
}
