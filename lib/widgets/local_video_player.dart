import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' show Player;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/video_track.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LocalVideoPlayer extends StatelessWidget {
  const LocalVideoPlayer({
    required this.appState,
    required this.video,
    super.key,
  });

  final AppState appState;
  final VideoTrack video;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Video(
          controller: appState.videoController,
          fill: Colors.black,
          fit: BoxFit.contain,
          controls: (videoState) => _MusicoVideoControls(
            appState: appState,
            video: video,
            videoState: videoState,
          ),
        ),
      ),
    );
  }
}

class LocalVideoArtwork extends StatelessWidget {
  const LocalVideoArtwork({required this.video, this.size = 46, super.key});

  final VideoTrack video;
  final double size;

  @override
  Widget build(BuildContext context) {
    final artworkPath = video.artworkPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: size,
        height: size,
        child: artworkPath == null
            ? _placeholder()
            : Image.file(
                File(artworkPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: MusicoPalette.canvasAlt,
    child: const Center(
      child: Icon(Icons.movie_outlined, color: MusicoPalette.forestLight),
    ),
  );
}

class _MusicoVideoControls extends StatefulWidget {
  const _MusicoVideoControls({
    required this.appState,
    required this.video,
    required this.videoState,
  });

  final AppState appState;
  final VideoTrack video;
  final VideoState videoState;

  @override
  State<_MusicoVideoControls> createState() => _MusicoVideoControlsState();
}

class _MusicoVideoControlsState extends State<_MusicoVideoControls> {
  late final Player _player;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _hideTimer;
  bool _controlsVisible = true;
  String? _controlError;

  @override
  void initState() {
    super.initState();
    _player = widget.videoState.widget.controller.player;
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (!_controlsVisible) setState(() => _controlsVisible = true);
      }
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    unawaited(_playingSubscription?.cancel());
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_controlsVisible || !_player.state.playing) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _runControl(
    Future<void> Function() action,
    String failureMessage,
  ) async {
    try {
      await action();
      if (_controlError != null && mounted) {
        setState(() => _controlError = null);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Local video control failed: $error\n$stackTrace');
      if (mounted) setState(() => _controlError = failureMessage);
    }
    _scheduleHide();
  }

  Future<void> _seek(Duration offset) async {
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    final target = (_player.state.position + offset).inMilliseconds.clamp(
      0,
      duration.inMilliseconds,
    );
    await _runControl(
      () => _player.seek(Duration(milliseconds: target)),
      'Could not seek this video.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final position = _player.state.position;
        final duration = _player.state.duration;
        final hasDuration = duration > Duration.zero;
        final maxMilliseconds = hasDuration ? duration.inMilliseconds : 1;
        final currentMilliseconds = position.inMilliseconds
            .clamp(0, maxMilliseconds)
            .toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: .2),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 9, 8, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.video.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: MusicoPalette.paper),
                                ),
                              ),
                              if (widget.video.quality case final quality?)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    quality,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: MusicoPalette.paper),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Back 10 seconds',
                                  onPressed: () => unawaited(
                                    _seek(const Duration(seconds: -10)),
                                  ),
                                  color: MusicoPalette.paper,
                                  icon: const Icon(Icons.replay_10_rounded),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: _player.state.playing
                                      ? 'Pause'
                                      : 'Play',
                                  onPressed: () => unawaited(
                                    _runControl(
                                      () => _player.playOrPause(),
                                      'Could not change video playback.',
                                    ),
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: MusicoPalette.forest,
                                    foregroundColor: MusicoPalette.paper,
                                  ),
                                  iconSize: 32,
                                  icon: Icon(
                                    _player.state.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Forward 10 seconds',
                                  onPressed: () => unawaited(
                                    _seek(const Duration(seconds: 10)),
                                  ),
                                  color: MusicoPalette.paper,
                                  icon: const Icon(Icons.forward_10_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ColoredBox(
                          color: Colors.black.withValues(alpha: .76),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 4, 3),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_controlError != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      _controlError!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: MusicoPalette.paper,
                                          ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Text(
                                      _formatVideoTime(position),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: MusicoPalette.paper,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: MusicoPalette.olive,
                                          inactiveTrackColor: MusicoPalette
                                              .paper
                                              .withValues(alpha: .38),
                                          thumbColor: MusicoPalette.paper,
                                          overlayColor: MusicoPalette.olive
                                              .withValues(alpha: .18),
                                          trackHeight: 3,
                                        ),
                                        child: Slider(
                                          min: 0,
                                          max: maxMilliseconds.toDouble(),
                                          value: currentMilliseconds,
                                          onChanged: hasDuration
                                              ? (value) => unawaited(
                                                  _runControl(
                                                    () => _player.seek(
                                                      Duration(
                                                        milliseconds: value
                                                            .round(),
                                                      ),
                                                    ),
                                                    'Could not seek this video.',
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatVideoTime(duration),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: MusicoPalette.paper,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                    IconButton(
                                      tooltip: widget.videoState.isFullscreen()
                                          ? 'Exit full screen'
                                          : 'Full screen',
                                      onPressed: () => unawaited(
                                        _runControl(
                                          widget.videoState.toggleFullscreen,
                                          'Could not change full-screen mode.',
                                        ),
                                      ),
                                      color: MusicoPalette.paper,
                                      icon: Icon(
                                        widget.videoState.isFullscreen()
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatVideoTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
