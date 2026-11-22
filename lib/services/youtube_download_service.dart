import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'yt_dlp_executable_resolver.dart';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_download.dart';
import '../models/youtube_media.dart';

/// Final files produced for one YouTube download.
class YouTubeDownloadOutcome {
  const YouTubeDownloadOutcome({
    required this.file,
    required this.byteSize,
    required this.extension,
    required this.metadataFile,
    this.artwork,
  });

  final File file;
  final int byteSize;
  final String extension;

  /// JSON sidecar holding the requested name and the original video metadata.
  final File metadataFile;
  final File? artwork;
}

/// Resolves YouTube stream manifests with `youtube_explode_dart`, downloads the
/// chosen streams with ranged requests (which avoids YouTube's plain-GET 403),
/// and turns them into MP3 (FFmpeg + libmp3lame) or MP4 (FFmpeg `-c copy` mux).
class YouTubeDownloadService {
  YouTubeDownloadService({http.Client? client})
    : _client = client ?? http.Client(),
      _youtube = YoutubeExplode();

  final http.Client _client;
  final YoutubeExplode _youtube;
  final Map<String, StreamManifest> _manifests = {};

  static const _chunkBytes = 512 * 1024;

  void dispose() {
    _youtube.close();
    _client.close();
  }

  /// MP4 qualities available for [videoId], best resolution first.
  Future<List<YouTubeQuality>> availableQualities(String videoId) async {
    final manifest = await _manifest(videoId);
    final seen = <String>{};
    final qualities = <YouTubeQuality>[];
    for (final stream in manifest.videoOnly) {
      final label = stream.qualityLabel;
      if (label.isEmpty || !seen.add(label)) continue;
      qualities.add(
        YouTubeQuality(
          label: label,
          height: _height(label),
          itag: stream.tag,
          codec: stream.videoCodec,
          container: stream.container.name,
          bitrateKbps: stream.bitrate.kiloBitsPerSecond,
          sizeBytes: stream.size.totalBytes,
        ),
      );
    }
    qualities.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      return b.bitrateKbps.compareTo(a.bitrateKbps);
    });
    return qualities;
  }

  /// Downloads the best available audio stream and encodes it to MP3.
  Future<YouTubeDownloadOutcome> downloadAudio({
    required YouTubeRipRequest request,
    required Directory directory,
    required Directory artworkDirectory,
    required void Function(double?) onProgress,
  }) async {
    await directory.create(recursive: true);
    final videoId = request.videoId;
    if (Platform.isWindows) {
      final operationDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        'tmp_yt_${DateTime.now().microsecondsSinceEpoch}',
      );
      await operationDirectory.create(recursive: true);
      try {
        final tempTemplate = File(
          '${operationDirectory.path}${Platform.pathSeparator}'
          'yt_audio.%(ext)s',
        ).path;
        onProgress(null);
        final tempAudio = await _runYtDlpAudio(request.videoUrl, tempTemplate);
        final artwork = await _downloadThumbnail(
          videoId,
          request.thumbnailUrl,
          artworkDirectory,
        );
        final tempMp3 = File(
          '${operationDirectory.path}${Platform.pathSeparator}'
          'download.mp3',
        );
        await _transcode(
          input: tempAudio.path,
          output: tempMp3.path,
          title: request.requestedName,
          artist: request.channel,
          artwork: artwork?.path,
        );
        final output = _uniqueFile(directory, request.safeFileName, 'mp3');
        await tempMp3.copy(output.path);
        final byteSize = await output.length();
        await _deleteQuietly(tempAudio);
        await _deleteQuietly(tempMp3);
        final metadata = _metadata(
          request,
          mediaFile: output,
          byteSize: byteSize,
          artworkPath: artwork?.path,
        );
        final metadataFile = await metadata.writeNextTo(output);
        onProgress(1);
        return YouTubeDownloadOutcome(
          file: output,
          byteSize: byteSize,
          extension: 'mp3',
          artwork: artwork,
          metadataFile: metadataFile,
        );
      } finally {
        try {
          if (await operationDirectory.exists()) {
            await operationDirectory.delete(recursive: true);
          }
        } on FileSystemException catch (error) {
          debugPrint(
            'Temporary YouTube download directory could not be removed: $error',
          );
        }
      }
    }
    onProgress(null);
    final manifest = await _manifest(videoId);
    final audio = _pickAudio(manifest);
    final sourceExt = audio.container.name == 'webm' ? 'webm' : 'm4a';
    final tempAudio = File(
      '${directory.path}${Platform.pathSeparator}'
      'yt_$videoId.$sourceExt',
    );

    try {
      await _downloadStream(
        audio,
        tempAudio,
        onProgress: (progress) =>
            onProgress(progress == null ? null : progress * .7),
      );
    } on Object catch (streamError) {
      debugPrint(
        'Direct stream download failed: $streamError. Falling back to range download.',
      );
      if (await tempAudio.exists()) await tempAudio.delete();
      await _downloadRange(
        audio.url,
        tempAudio,
        totalBytes: audio.size.totalBytes,
        onProgress: (progress) =>
            onProgress(progress == null ? null : progress * .7),
      );
    }

    final artwork = await _downloadThumbnail(
      videoId,
      request.thumbnailUrl,
      artworkDirectory,
    );
    final output = _uniqueFile(directory, request.safeFileName, 'mp3');
    onProgress(null);
    await _transcode(
      input: tempAudio.path,
      output: output.path,
      title: request.requestedName,
      artist: request.channel,
      artwork: artwork?.path,
    );

    final byteSize = await output.length();
    await _deleteQuietly(tempAudio);
    final metadata = _metadata(
      request,
      mediaFile: output,
      byteSize: byteSize,
      artworkPath: artwork?.path,
    );
    final metadataFile = await metadata.writeNextTo(output);
    onProgress(1);
    return YouTubeDownloadOutcome(
      file: output,
      byteSize: byteSize,
      extension: 'mp3',
      artwork: artwork,
      metadataFile: metadataFile,
    );
  }

  /// Downloads the selected MP4 quality by muxing a video-only stream with the
  /// best audio stream (no re-encode; `-c copy`).
  Future<YouTubeDownloadOutcome> downloadVideo({
    required YouTubeRipRequest request,
    required Directory directory,
    required Directory artworkDirectory,
    required void Function(double?) onProgress,
  }) async {
    await directory.create(recursive: true);
    final videoId = request.videoId;
    final qualityLabel = request.quality;
    if (qualityLabel == null || qualityLabel.isEmpty) {
      throw const FormatException('Choose a video quality first.');
    }
    if (Platform.isWindows) {
      final operationDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}'
        'tmp_yt_video_${DateTime.now().microsecondsSinceEpoch}',
      );
      await operationDirectory.create(recursive: true);
      try {
        final tempMp4 = File(
          '${operationDirectory.path}${Platform.pathSeparator}download.mp4',
        );
        await _runYtDlpVideo(
          request.videoUrl,
          tempMp4.path,
          qualityLabel,
          onProgress,
        );
        final output = _uniqueFile(directory, request.safeFileName, 'mp4');
        await tempMp4.copy(output.path);
        final byteSize = await output.length();
        await _deleteQuietly(tempMp4);
        final artwork = await _downloadThumbnail(
          videoId,
          request.thumbnailUrl,
          artworkDirectory,
        );
        final metadata = _metadata(
          request,
          mediaFile: output,
          byteSize: byteSize,
          artworkPath: artwork?.path,
        );
        final metadataFile = await metadata.writeNextTo(output);
        onProgress(1);
        return YouTubeDownloadOutcome(
          file: output,
          byteSize: byteSize,
          extension: 'mp4',
          artwork: artwork,
          metadataFile: metadataFile,
        );
      } finally {
        try {
          if (await operationDirectory.exists()) {
            await operationDirectory.delete(recursive: true);
          }
        } on FileSystemException catch (error) {
          debugPrint(
            'Temporary YouTube video directory could not be removed: $error',
          );
        }
      }
    }
    final manifest = await _manifest(videoId);
    final video = _pickVideo(manifest, qualityLabel);
    if (video == null) {
      throw FormatException(
        'Quality "$qualityLabel" is not available for this video.',
      );
    }
    final audio = _pickAudio(manifest);

    final videoExt = video.container.name == 'webm' ? 'webm' : 'mp4';
    final audioExt = audio.container.name == 'webm' ? 'webm' : 'm4a';
    final tempVideo = File(
      '${directory.path}${Platform.pathSeparator}'
      '.yt-$videoId-video.$videoExt',
    );
    final tempAudio = File(
      '${directory.path}${Platform.pathSeparator}'
      '.yt-$videoId-audio.$audioExt',
    );

    try {
      await _downloadStream(
        video,
        tempVideo,
        onProgress: (progress) =>
            onProgress(progress == null ? null : progress * .6),
      );
    } on Object catch (streamError) {
      debugPrint(
        'Direct video stream download failed: $streamError. Falling back to range download.',
      );
      if (await tempVideo.exists()) await tempVideo.delete();
      await _downloadRange(
        video.url,
        tempVideo,
        totalBytes: video.size.totalBytes,
        onProgress: (progress) =>
            onProgress(progress == null ? null : progress * .6),
      );
    }

    try {
      await _downloadStream(
        audio,
        tempAudio,
        onProgress: (progress) =>
            onProgress(progress == null ? null : .6 + progress * .1),
      );
    } on Object catch (streamError) {
      debugPrint(
        'Direct audio stream download failed: $streamError. Falling back to range download.',
      );
      if (await tempAudio.exists()) await tempAudio.delete();
      await _downloadRange(
        audio.url,
        tempAudio,
        totalBytes: audio.size.totalBytes,
        onProgress: (progress) =>
            onProgress(progress == null ? null : .6 + progress * .1),
      );
    }

    final output = _uniqueFile(directory, request.safeFileName, 'mp4');
    onProgress(null);
    await _mux(
      videoPath: tempVideo.path,
      audioPath: tempAudio.path,
      output: output.path,
      title: request.requestedName,
      artist: request.channel,
    );

    final byteSize = await output.length();
    await _deleteQuietly(tempVideo);
    await _deleteQuietly(tempAudio);
    final artwork = await _downloadThumbnail(
      videoId,
      request.thumbnailUrl,
      artworkDirectory,
    );
    final metadata = _metadata(
      request,
      mediaFile: output,
      byteSize: byteSize,
      artworkPath: artwork?.path,
    );
    final metadataFile = await metadata.writeNextTo(output);
    return YouTubeDownloadOutcome(
      file: output,
      byteSize: byteSize,
      extension: 'mp4',
      artwork: artwork,
      metadataFile: metadataFile,
    );
  }

  /// Picks a non-colliding `Name.ext` / `Name (1).ext` path.
  File _uniqueFile(Directory directory, String baseName, String extension) {
    var candidate = File(
      '${directory.path}${Platform.pathSeparator}$baseName.$extension',
    );
    var suffix = 1;
    while (candidate.existsSync()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}'
        '$baseName ($suffix).$extension',
      );
      suffix++;
    }
    return candidate;
  }

  YouTubeDownloadMetadata _metadata(
    YouTubeRipRequest request, {
    required File mediaFile,
    required int byteSize,
    String? artworkPath,
  }) {
    return YouTubeDownloadMetadata(
      requestedName: request.requestedName,
      originalTitle: request.originalTitle,
      channel: request.channel,
      videoId: request.videoId,
      videoUrl: request.videoUrl,
      format: request.format.name,
      quality: request.quality,
      durationMs: request.durationMs,
      thumbnailUrl: request.thumbnailUrl,
      artworkPath: artworkPath,
      mediaFileName: _fileName(mediaFile),
      byteSize: byteSize,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _fileName(File file) {
    final path = file.path;
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    return index == -1 ? path : path.substring(index + 1);
  }

  Future<StreamManifest> _manifest(String videoId) async {
    final cached = _manifests[videoId];
    if (cached != null) return cached;

    // 1. Try standard getManifest first with strict timeout
    try {
      final manifest = await _youtube.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 8));
      if (manifest.audioOnly.isNotEmpty || manifest.muxed.isNotEmpty) {
        _manifests[videoId] = manifest;
        return manifest;
      }
    } on Object catch (error) {
      debugPrint('Standard streamsClient.getManifest failed: $error');
    }

    // 2. Fall back to clients that do not enforce strict bot checks
    final fallbackClients = [
      YoutubeApiClient.androidSdkless,
      YoutubeApiClient.androidMusic,
      YoutubeApiClient.safari,
      YoutubeApiClient.ios,
    ];

    Object? lastError;
    for (final client in fallbackClients) {
      try {
        final manifest = await _youtube.videos.streamsClient
            .getManifest(videoId, ytClients: [client], requireWatchPage: false)
            .timeout(const Duration(seconds: 6));
        if (manifest.audioOnly.isNotEmpty || manifest.muxed.isNotEmpty) {
          _manifests[videoId] = manifest;
          return manifest;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError!;
    throw const FormatException(
      'YouTube did not expose downloadable streams for this video. Try again shortly.',
    );
  }

  AudioStreamInfo _pickAudio(StreamManifest manifest) {
    final audioOnly = manifest.audioOnly;
    final pool = audioOnly.isNotEmpty ? audioOnly : manifest.muxed;
    final aac = pool
        .where((s) => s.audioCodec.toLowerCase().startsWith('mp4a'))
        .toList();
    final candidates = aac.isNotEmpty ? aac : pool;
    if (audioOnly.isEmpty) {
      final selected = candidates.sortByBitrate().last;
      debugPrint(
        'No audio-only YouTube stream is available; using the smallest '
        'muxed stream (${selected.qualityLabel}, ${selected.size}).',
      );
      return selected;
    }
    return candidates.withHighestBitrate();
  }

  VideoOnlyStreamInfo? _pickVideo(
    StreamManifest manifest,
    String qualityLabel,
  ) {
    final matches = manifest.videoOnly
        .where((s) => s.qualityLabel == qualityLabel)
        .toList();
    if (matches.isEmpty) return null;
    final preferred = matches
        .where((s) => _codecRank(s.videoCodec) < 4)
        .toList();
    final pool = preferred.isNotEmpty ? preferred : matches;
    return pool.withHighestBitrate();
  }

  int _codecRank(String codec) {
    final lower = codec.toLowerCase();
    if (lower.contains('avc')) return 0;
    if (lower.contains('vp9')) return 1;
    if (lower.contains('av01') || lower.contains('av1')) return 2;
    return 3;
  }

  String _resolveYtDlpExecutable() {
    final userProfile = Platform.environment['USERPROFILE'];
    return findYtDlpExecutable(
          applicationDirectory: File(Platform.resolvedExecutable).parent.path,
          userProfile: userProfile,
        ) ??
        (throw const FormatException(
          'yt-dlp is not installed for this Windows user.',
        ));
  }

  Future<File> _runYtDlpAudio(String url, String outputTemplate) async {
    final executable = _resolveYtDlpExecutable();
    final result = await Process.run(executable, [
      '--no-playlist',
      '--no-warnings',
      '--newline',
      '-f',
      'bestaudio/best',
      '-o',
      outputTemplate,
      url,
    ]);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw FormatException(
        stderr.isNotEmpty
            ? stderr.split('\n').last
            : stdout.isNotEmpty
            ? stdout.split('\n').last
            : 'yt-dlp could not download this YouTube audio.',
      );
    }

    final directory = File(outputTemplate).parent;
    final prefix = File(outputTemplate).uri.pathSegments.last
        .replaceAll('.%(ext)s', '.');
    final entities = await directory.list().toList();
    final candidates = entities
        .whereType<File>()
        .where((entity) => entity.uri.pathSegments.last.startsWith(prefix))
        .toList();
    if (candidates.isEmpty) {
      throw const FormatException(
        'yt-dlp finished without creating an audio file.',
      );
    }
    candidates.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return candidates.first;
  }

  Future<void> _runYtDlpVideo(
    String url,
    String outputPath,
    String qualityLabel,
    void Function(double?) onProgress,
  ) async {
    final height = _height(qualityLabel);
    final format = height > 0
        ? 'best[height<=?$height][ext=mp4]/best[ext=mp4]/best'
        : 'best[ext=mp4]/best';
    final executable = _resolveYtDlpExecutable();
    final result = await Process.run(executable, [
      '--no-playlist',
      '--no-warnings',
      '--newline',
      '-f',
      format,
      '-o',
      outputPath,
      url,
    ]);
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw FormatException(
        stderr.isNotEmpty
            ? stderr.split('\n').last
            : stdout.isNotEmpty
            ? stdout.split('\n').last
            : 'yt-dlp could not download this YouTube video.',
      );
    }
    if (!await File(outputPath).exists()) {
      throw const FormatException(
        'yt-dlp finished without creating a video file.',
      );
    }
    onProgress(1);
  }

  Future<void> _downloadStream(
    StreamInfo streamInfo,
    File destination, {
    required void Function(double?) onProgress,
  }) async {
    final sink = destination.openWrite();
    var received = 0;
    final totalBytes = streamInfo.size.totalBytes;
    final total = totalBytes > 0 ? totalBytes : null;
    try {
      final stream = _youtube.videos.streamsClient.get(streamInfo);
      // Timeout per chunk: abort if stalled for more than 15s instead of hanging indefinitely
      await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
        sink.add(chunk);
        received += chunk.length;
        _reportProgress(received, total, onProgress);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) {
      throw const FormatException('YouTube returned an empty media stream.');
    }
  }

  Future<void> _downloadRange(
    Uri url,
    File destination, {
    required int totalBytes,
    required void Function(double?) onProgress,
  }) async {
    final sink = destination.openWrite();
    var offset = 0;
    var received = 0;
    final total = totalBytes > 0 ? totalBytes : null;
    try {
      while (true) {
        final currentOffset = offset;
        final response = await _sendWithRetry(() {
          final request = http.Request('GET', url)..followRedirects = true;
          request.headers['Range'] =
              'bytes=$currentOffset-${currentOffset + _chunkBytes - 1}';
          request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
          return request;
        });
        if (response.statusCode == 200 && currentOffset == 0) {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 60),
          )) {
            sink.add(chunk);
            received += chunk.length;
            _reportProgress(received, total, onProgress);
          }
          break;
        }
        if (response.statusCode == 206) {
          final chunk = await response.stream.toBytes().timeout(
            const Duration(seconds: 60),
          );
          if (chunk.isEmpty) break;
          sink.add(chunk);
          received += chunk.length;
          offset += chunk.length;
          _reportProgress(received, total, onProgress);
          if (chunk.length < _chunkBytes) break;
          continue;
        }
        throw HttpException(
          'The YouTube media server returned ${response.statusCode}.',
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (received == 0) {
      throw const FormatException('YouTube returned an empty media stream.');
    }
  }

  Future<http.StreamedResponse> _sendWithRetry(
    http.Request Function() requestBuilder, {
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final request = requestBuilder();
        final response = await _client
            .send(request)
            .timeout(const Duration(seconds: 45));
        if (response.statusCode == 403 || response.statusCode == 429) {
          await response.stream.drain<void>();
          lastError = HttpException(
            'YouTube is throttling this download (${response.statusCode}).',
          );
          await Future<void>.delayed(const Duration(milliseconds: 900));
          continue;
        }
        return response;
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw lastError ?? const HttpException('The download failed.');
  }

  void _reportProgress(
    int received,
    int? total,
    void Function(double?) onProgress,
  ) {
    if (total == null || total <= 0) {
      onProgress(null);
      return;
    }
    onProgress((received / total).clamp(0, 1).toDouble());
  }

  Future<File?> _downloadThumbnail(
    String videoId,
    String? fallbackUrl,
    Directory artworkDirectory,
  ) async {
    final candidates = <String>[
      'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg',
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
      ?fallbackUrl,
    ];
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    for (final candidate in candidates) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        final response = await _client
            .get(Uri.parse(candidate))
            .timeout(remaining);
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) continue;
        await artworkDirectory.create(recursive: true);
        final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final file = File(
          '${artworkDirectory.path}${Platform.pathSeparator}$safeId.jpg',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file;
      } on Object catch (error) {
        debugPrint('YouTube thumbnail request failed for $candidate: $error');
        continue;
      }
    }
    return null;
  }

  Future<void> _transcode({
    required String input,
    required String output,
    required String title,
    required String artist,
    String? artwork,
  }) async {
    final success = await _runFfmpeg(
      _transcodeArgs(
        input: input,
        output: output,
        title: title,
        artist: artist,
        artwork: artwork,
      ),
    );
    if (success) return;
    if (artwork != null) {
      final retried = await _runFfmpeg(
        _transcodeArgs(
          input: input,
          output: output,
          title: title,
          artist: artist,
        ),
      );
      if (retried) return;
    }
    throw const FormatException('MP3 conversion failed. Try again shortly.');
  }

  List<String> _transcodeArgs({
    required String input,
    required String output,
    required String title,
    required String artist,
    String? artwork,
  }) => [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    input,
    if (artwork != null) ...['-i', artwork],
    '-map',
    '0:a:0',
    if (artwork != null) ...['-map', '1:v:0'],
    '-c:a',
    'libmp3lame',
    '-b:a',
    '192k',
    '-id3v2_version',
    '3',
    '-metadata',
    'title=${_escapeMetadata(title)}',
    '-metadata',
    'artist=${_escapeMetadata(artist)}',
    if (artwork != null) ...const [
      '-metadata:s:v',
      'title=Album cover',
      '-metadata:s:v',
      'comment=Cover (front)',
    ],
    output,
  ];

  Future<void> _mux({
    required String videoPath,
    required String audioPath,
    required String output,
    required String title,
    required String artist,
  }) async {
    final success = await _runFfmpeg(
      _muxArgs(
        videoPath: videoPath,
        audioPath: audioPath,
        output: output,
        title: title,
        artist: artist,
      ),
    );
    if (success) return;
    final retried = await _runFfmpeg(
      _muxArgs(videoPath: videoPath, audioPath: audioPath, output: output),
    );
    if (!retried) {
      throw const FormatException(
        'The video could not be combined. Try again.',
      );
    }
  }

  List<String> _muxArgs({
    required String videoPath,
    required String audioPath,
    required String output,
    String? title,
    String? artist,
  }) => [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    videoPath,
    '-i',
    audioPath,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c',
    'copy',
    '-movflags',
    '+faststart',
    if (title != null) ...['-metadata', 'title=${_escapeMetadata(title)}'],
    if (artist != null) ...['-metadata', 'artist=${_escapeMetadata(artist)}'],
    output,
  ];

  Future<bool> _runFfmpeg(List<String> args) async {
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) return true;
      debugPrint('FFmpeg failed: ${await session.getLogsAsString()}');
      return false;
    } on Object catch (error) {
      debugPrint('FFmpeg unavailable: $error');
      throw const FormatException(
        'FFmpeg is unavailable on this device, so the media could not be converted.',
      );
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort only.
    }
  }

  String _escapeMetadata(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('=', r'\=')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(':', r'\:')
      .replaceAll('#', r'\#');

  int _height(String label) {
    final match = RegExp(r'^\d+').firstMatch(label.trim());
    return match == null ? 0 : int.parse(match.group(0)!);
  }
}
