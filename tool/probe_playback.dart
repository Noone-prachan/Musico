import 'dart:io';

import 'package:musico/services/watch_service.dart';

Future<(int, List<int>)> _get(String url, {String? referer}) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', WatchService.userAgent);
  if (referer != null) request.headers.set('Referer', referer);
  final response = await request.close();
  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
  }
  client.close(force: true);
  return (response.statusCode, bytes);
}

String _abs(String base, String path) {
  if (RegExp('^https?://', caseSensitive: false).hasMatch(path)) return path;
  final uri = Uri.parse(base);
  if (path.startsWith('/')) return '${uri.scheme}://${uri.host}$path';
  return '${base.substring(0, base.lastIndexOf('/') + 1)}$path';
}

String _text(List<int> bytes) => String.fromCharCodes(bytes);

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'Severance' : args.first;
  final service = WatchService();
  try {
    final titles = await service.search(query, series: true);
    final show = titles.first;
    final episodes = await service.episodes(show);
    final source = await service.resolveEpisode(show, episodes.first);
    stdout.writeln('playlist: ${source.url}');

    final (mCode, mBytes) = await _get(source.url, referer: source.referer);
    final master = _text(mBytes);
    stdout.writeln('master -> HTTP $mCode');
    final variantPath = master
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .first;
    final variantUrl = _abs(source.url, variantPath);
    final (vCode, vBytes) = await _get(variantUrl, referer: source.referer);
    final variant = _text(vBytes);
    stdout.writeln('variant -> HTTP $vCode');

    final keyLine = variant
        .split('\n')
        .where((l) => l.startsWith('#EXT-X-KEY'))
        .first;
    stdout.writeln(keyLine);
    final keyPath = RegExp(r'URI="([^"]+)"').firstMatch(keyLine)?.group(1);
    if (keyPath != null) {
      final keyUrl = _abs(variantUrl, keyPath);
      final (kCode, kBytes) = await _get(keyUrl, referer: source.referer);
      stdout.writeln('key -> HTTP $kCode (${kBytes.length} bytes) $keyUrl');
      final (kNoRef, _) = await _get(keyUrl);
      stdout.writeln('key without referer -> HTTP $kNoRef');
    }

    final segment = variant
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .first;
    final segmentUrl = _abs(variantUrl, segment);
    final (sCode, sBytes) = await _get(segmentUrl, referer: source.referer);
    final header = sBytes.take(4).toList();
    stdout.writeln(
      'segment -> HTTP $sCode (${sBytes.length} bytes) '
      'magic=${header.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );
    stdout.writeln('segment url: $segmentUrl');
  } on Object catch (error, stackTrace) {
    stderr.writeln('FAILED: $error');
    stderr.writeln(stackTrace);
  } finally {
    service.dispose();
  }
}
