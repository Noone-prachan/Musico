import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/media_download.dart';

class DownloadedMediaFile {
  const DownloadedMediaFile({required this.file, required this.byteSize});

  final File file;
  final int byteSize;
}

class DirectMediaDownloadService {
  const DirectMediaDownloadService(this._client);

  final http.Client _client;

  Future<DownloadedMediaFile> download(
    MediaDownloadLink item,
    Directory directory, {
    required void Function(double? progress) onProgress,
  }) async {
    await directory.create(recursive: true);
    final fileName =
        '${_sanitizeFilename(item.progressKey)}-${DateTime.now().microsecondsSinceEpoch}-${_sanitizeFilename(item.title)}${_urlExtension(item.uri.path)}';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    var received = 0;
    var lastProgressReport = 0;
    try {
      final output = destination.openWrite();
      try {
        final response = await _sendRequest(item);
        final contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        final expectedType = item.category == MediaDownloadCategory.music
            ? 'audio/'
            : 'video/';
        if (contentType == null ||
            (contentType != 'application/octet-stream' &&
                contentType != 'binary/octet-stream' &&
                !contentType.startsWith(expectedType))) {
          await response.stream.drain<void>();
          throw const FormatException(
            'The link did not return a direct audio or video file.',
          );
        }

        final maxBytes = item.category == MediaDownloadCategory.music
            ? 500 * 1024 * 1024
            : 2 * 1024 * 1024 * 1024;
        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > maxBytes) {
          await response.stream.drain<void>();
          throw FormatException(
            'This file exceeds the ${item.category == MediaDownloadCategory.music ? '500 MB' : '2 GB'} download limit.',
          );
        }
        onProgress(contentLength != null && contentLength > 0 ? 0 : null);

        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 45),
        )) {
          received += chunk.length;
          if (received > maxBytes) {
            throw FormatException(
              'This file exceeds the ${item.category == MediaDownloadCategory.music ? '500 MB' : '2 GB'} download limit.',
            );
          }
          output.add(chunk);
          if (contentLength != null &&
              contentLength > 0 &&
              (received - lastProgressReport >= 512 * 1024 ||
                  received == contentLength)) {
            onProgress((received / contentLength).clamp(0, 1).toDouble());
            lastProgressReport = received;
          }
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (received == 0) {
        throw const FormatException('The source returned an empty media file.');
      }
      return DownloadedMediaFile(file: destination, byteSize: received);
    } on Object {
      try {
        if (await destination.exists()) await destination.delete();
      } on FileSystemException catch (error, stackTrace) {
        stderr.writeln(
          'Incomplete media download could not be removed: $error',
        );
        stderr.writeln(stackTrace);
      }
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendRequest(MediaDownloadLink item) async {
    var uri = item.uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      item.validateRedirectUri(uri);
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 40));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null) {
          throw const HttpException('The download redirect had no location.');
        }
        uri = uri.resolve(location);
        item.validateRedirectUri(uri);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException(
          'The media server returned ${response.statusCode}.',
        );
      }
      final responseUri = response.request?.url;
      if (responseUri != null) item.validateRedirectUri(responseUri);
      return response;
    }
    throw const HttpException('The media link redirected too many times.');
  }

  String _urlExtension(String path) =>
      '.${path.substring(path.lastIndexOf('/') + 1).split('.').last.toLowerCase()}';

  String _sanitizeFilename(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
