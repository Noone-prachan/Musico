import 'dart:convert';
import 'dart:io';

import 'package:musico/services/anime_stream_service.dart';

Future<int> _fetch(HttpClient client, Uri uri, {String? referer}) async {
  final request = await client.getUrl(uri);
  request.headers.set('User-Agent', AnimeStreamService.userAgent);
  if (referer != null) request.headers.set('Referer', referer);
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 200 && body.isNotEmpty) {
    stdout.writeln(body.split('\n').take(4).join('\n'));
  }
  return response.statusCode;
}

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'Dandadan' : args.first;
  final service = AnimeStreamService();
  final client = HttpClient();
  var exitCode = 0;
  try {
    final results = await service.search(query);
    stdout.writeln('search "$query" -> ${results.length} results');
    if (results.isEmpty) throw StateError('no search results');
    final show = results.first;
    stdout.writeln('show: ${show.title} (${show.slug})');

    final episodes = await service.episodes(show);
    stdout.writeln(
      'episodes: ${episodes.length}, first #${episodes.first.number}',
    );
    if (episodes.isEmpty) throw StateError('no episodes');

    final source = await service.resolveStream(episodes.first);
    stdout.writeln('playlist: ${source.url}');
    stdout.writeln('referer: ${source.referer}');
    stdout.writeln('subtitle: ${source.subtitleUrl ?? "(none)"}');

    final withReferer = await _fetch(
      client,
      Uri.parse(source.url),
      referer: source.referer,
    );
    stdout.writeln('playlist with referer -> HTTP $withReferer');
    final withoutReferer = await _fetch(client, Uri.parse(source.url));
    stdout.writeln('playlist without referer -> HTTP $withoutReferer');
    if (withReferer != 200) exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('FAILED: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  } finally {
    client.close(force: true);
    service.dispose();
  }
  exit(exitCode);
}
