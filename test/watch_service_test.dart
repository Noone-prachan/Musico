import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/watch_media.dart';
import 'package:musico/services/watch_service.dart';

void main() {
  group('parseImdbSuggestions', () {
    final body = jsonEncode({
      'd': [
        {
          'id': 'tt0944947',
          'l': 'Game of Thrones',
          'y': 2011,
          'q': 'TV series',
          'qid': 'tvSeries',
          'i': {'imageUrl': 'https://img.example/got.jpg'},
        },
        {
          'id': 'tt1160419',
          'l': 'Dune',
          'y': 2021,
          'q': 'feature',
          'qid': 'movie',
          'i': {'imageUrl': 'https://img.example/dune.jpg'},
        },
        {'id': 'nm0290227', 'l': 'Leigh Francis'},
        {'id': 'in0000274', 'l': 'Breaking Bad'},
        {'l': 'No id'},
      ],
    });

    test('keeps only series when asked for series', () {
      final results = WatchService.parseImdbSuggestions(body, series: true);
      expect(results.map((title) => title.title), ['Game of Thrones']);
      expect(results.first.isSeries, isTrue);
      expect(results.first.year, 2011);
      expect(results.first.posterUrl, 'https://img.example/got.jpg');
    });

    test('keeps only movies when asked for movies', () {
      final results = WatchService.parseImdbSuggestions(body, series: false);
      expect(results.map((title) => title.title), ['Dune']);
      expect(results.first.isMovie, isTrue);
      expect(results.first.subtitleLine, '2021 · Movie');
    });

    test('survives malformed payloads', () {
      expect(
        WatchService.parseImdbSuggestions('not json', series: true),
        isEmpty,
      );
      expect(
        WatchService.parseImdbSuggestions('{"d": "nope"}', series: true),
        isEmpty,
      );
    });
  });

  group('parseTvmazeEpisodes', () {
    final body = jsonEncode([
      {
        'season': 1,
        'number': 2,
        'name': 'The Kingsroad',
        'airdate': '2011-04-24',
      },
      {'season': 1, 'number': 1, 'name': 'Winter is Coming', 'airdate': null},
      {'season': 2, 'number': 1, 'name': 'The North Remembers'},
      {'season': null, 'number': 3, 'name': 'Special'},
      {'season': 2, 'number': null, 'name': 'Broken'},
    ]);

    test('sorts by season then episode and skips invalid rows', () {
      final episodes = WatchService.parseTvmazeEpisodes(body);
      expect(episodes.length, 3);
      expect(episodes.first.season, 1);
      expect(episodes.first.number, 1);
      expect(episodes[1].displayTitle, 'The Kingsroad');
      expect(episodes.last.label, 'S2 · E1');
    });

    test('falls back to a generic title when the name is blank', () {
      final episodes = WatchService.parseTvmazeEpisodes(
        jsonEncode([
          {'season': 1, 'number': 4, 'name': '   '},
        ]),
      );
      expect(episodes.single.displayTitle, 'Episode 4');
    });
  });

  group('parseVixsrcEmbed', () {
    test('builds the playlist url from the masterPlaylist block', () {
      const html = '''
        window.masterPlaylist = {
          params: {
            'token': 'abc123',
            'expires': '1800674491',
            'asn': '',
          },
          url: 'https://vixsrc.to/playlist/790935',
        }
      ''';
      expect(
        WatchService.parseVixsrcEmbed(html),
        'https://vixsrc.to/playlist/790935?token=abc123&expires=1800674491&asn=',
      );
    });

    test('falls back to the direct server playlist', () {
      const html =
          'window.streams = [{"name":"Server1","url":"https:\\/\\/vixsrc.to\\/playlist\\/42?cf=1"}]';
      expect(
        WatchService.parseVixsrcEmbed(html),
        'https://vixsrc.to/playlist/42?cf=1',
      );
    });

    test('returns null when the embed is unplayable', () {
      expect(WatchService.parseVixsrcEmbed('<html></html>'), isNull);
    });
  });

  group('WatchTitle', () {
    test('treats mini-series and tv shorts as series', () {
      const mini = WatchTitle(imdbId: 'tt1', title: 'X', kind: 'tvMiniSeries');
      const short = WatchTitle(imdbId: 'tt2', title: 'Y', kind: 'tvShort');
      const movie = WatchTitle(
        imdbId: 'tt3',
        title: 'Z',
        kind: 'tvMovie',
        year: 2020,
      );
      expect(mini.isSeries, isTrue);
      expect(short.isSeries, isTrue);
      expect(movie.isMovie, isTrue);
      expect(movie.typeLabel, 'TV movie');
      expect(movie.subtitleLine, '2020 · TV movie');
    });
  });

  group('parseTvmazeSearch', () {
    final body = jsonEncode([
      {
        'score': 0.9,
        'show': {
          'name': 'Severance',
          'premiered': '2022-02-18',
          'type': 'Scripted',
          'image': {'medium': 'https://img.example/severance.jpg'},
          'externals': {'imdb': 'tt11280740'},
        },
      },
      {
        'show': {'name': 'No IMDb id', 'externals': <String, dynamic>{}},
      },
    ]);

    test('maps TVMaze shows onto playable titles', () {
      final titles = WatchService.parseTvmazeSearch(body);
      expect(titles.length, 1);
      expect(titles.single.title, 'Severance');
      expect(titles.single.imdbId, 'tt11280740');
      expect(titles.single.year, 2022);
      expect(titles.single.isSeries, isTrue);
      expect(titles.single.posterUrl, 'https://img.example/severance.jpg');
    });

    test('survives malformed payloads', () {
      expect(WatchService.parseTvmazeSearch('nope'), isEmpty);
      expect(WatchService.parseTvmazeSearch('{}'), isEmpty);
    });
  });

  group('parseTvmazeSeasonPremieres', () {
    final firstDay = jsonEncode([
      {
        'season': 3,
        'number': 1,
        'name': 'The Return',
        'airdate': '2026-11-27',
        '_embedded': {
          'show': {
            'name': 'Severance',
            'premiered': '2022-02-18',
            'externals': {'imdb': 'tt11280740'},
            'image': {'medium': 'https://img.example/severance.jpg'},
          },
        },
      },
      {
        'season': 3,
        'number': 2,
        'name': 'Second episode',
        'airdate': '2026-11-28',
        '_embedded': {
          'show': {
            'name': 'Severance',
            'externals': {'imdb': 'tt11280740'},
          },
        },
      },
      {
        'season': 1,
        'number': 1,
        'airdate': '2026-11-29',
        '_embedded': {
          'show': {
            'name': 'New series',
            'externals': {'imdb': 'tt1234567'},
          },
        },
      },
    ]);

    test('keeps scheduled first episodes of returning seasons', () {
      final premieres = WatchService.parseTvmazeSeasonPremieres([firstDay]);
      expect(premieres, hasLength(1));
      expect(premieres.single.show.title, 'Severance');
      expect(
        premieres.single.show.posterUrl,
        'https://img.example/severance.jpg',
      );
      expect(premieres.single.season, 3);
      expect(premieres.single.episode.airdate, '2026-11-27');
    });

    test('deduplicates seasons and tolerates malformed schedule days', () {
      final premieres = WatchService.parseTvmazeSeasonPremieres([
        firstDay,
        firstDay,
        'not json',
        '{"not":"a schedule"}',
      ]);
      expect(premieres, hasLength(1));
    });
  });
}
