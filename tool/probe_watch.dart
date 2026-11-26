import 'dart:convert';
import 'dart:io';

import 'package:musico/services/watch_service.dart';

Future<int> _status(String url, {String? referer}) async {
  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  request.headers.set('User-Agent', WatchService.userAgent);
  if (referer != null) request.headers.set('Referer', referer);
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 200) {
    stdout.writeln(body.split('\n').take(3).join('\n'));
  }
  client.close(force: true);
  return response.statusCode;
}

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'Game of Thrones' : args.first;
  final service = WatchService();
  var code = 0;
  try {
    final shows = await service.search(query, series: true);
    stdout.writeln('series results: ${shows.length}');
    if (shows.isEmpty) throw StateError('no series results');
    final show = shows.first;
    stdout.writeln('show: ${show.title} (${show.imdbId}) ${show.subtitleLine}');

    final episodes = await service.episodes(show);
    stdout.writeln('episodes: ${episodes.length}');
    if (episodes.isEmpty) throw StateError('no episodes');

    final source = await service.resolveEpisode(show, episodes.first);
    stdout.writeln('playlist: ${source.url}');
    final status = await _status(source.url);
    stdout.writeln('playlist -> HTTP $status');
    if (status != 200) code = 1;

    final movies = await service.search('Inception', series: false);
    stdout.writeln('movie results: ${movies.length}');
    if (movies.isNotEmpty) {
      final movie = movies.first;
      final movieSource = await service.resolveMovie(movie);
      stdout.writeln('movie: ${movie.title} -> ${movieSource.url}');
      final movieStatus = await _status(movieSource.url);
      stdout.writeln('movie playlist -> HTTP $movieStatus');
      if (movieStatus != 200) code = 1;
    }
  } on Object catch (error, stackTrace) {
    stderr.writeln('FAILED: $error');
    stderr.writeln(stackTrace);
    code = 2;
  } finally {
    service.dispose();
  }
  exit(code);
}
