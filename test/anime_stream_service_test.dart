import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musico/models/anime_stream.dart';
import 'package:musico/services/anime_stream_service.dart';

String _xorEmbed(String plain, {String key = 'otaku-embed-v1'}) {
  final bytes = utf8.encode(plain);
  final keyBytes = utf8.encode(key);
  final out = List<int>.generate(
    bytes.length,
    (index) => bytes[index] ^ keyBytes[index % keyBytes.length],
  );
  return base64.encode(out);
}

void main() {
  group('AnimeSearchResult', () {
    test('extracts the numeric id from the slug', () {
      const result = AnimeSearchResult(slug: 'naruto-1335', title: 'Naruto');
      expect(result.numericId, '1335');
    });

    test('falls back to the whole slug when there is no id suffix', () {
      const result = AnimeSearchResult(slug: 'naruto', title: 'Naruto');
      expect(result.numericId, 'naruto');
    });

    test('builds a type/duration subtitle line', () {
      const result = AnimeSearchResult(
        slug: 'naruto-1335',
        title: 'Naruto',
        type: 'TV',
        duration: '23m',
      );
      expect(result.subtitleLine, 'TV · 23m');
    });
  });

  group('parseSearchHtml', () {
    const html = '''
      <div class="film_list-wrap">
        <div class="flw-item flw-item-big">
          <div class="film-poster">
            <img data-src="https://cdn.example/naruto.jpg" class="film-poster-img" src="https://cdn.example/naruto.jpg">
            <div class="tick ltr"><div class="tick-item tick-eps">220</div></div>
          </div>
          <div class="film-detail">
            <h3 class="film-name">
              <a href="/watch/naruto-1335" title="Naruto" data-jname="NARUTO">Naruto</a>
            </h3>
            <div class="fd-infor">
              <span class="fdi-item">TV</span>
              <span class="fdi-item fdi-duration">23m</span>
            </div>
          </div>
        </div>
        <div class="flw-item flw-item-big">
          <div class="film-poster">
            <img src="https://cdn.example/boruto.jpg">
          </div>
          <div class="film-detail">
            <h3 class="film-name">
              <a href="/watch/boruto-naruto-next-generations-650" title="Boruto: Naruto Next Generations">Boruto</a>
            </h3>
            <div class="fd-infor"><span class="fdi-item">TV</span></div>
          </div>
        </div>
      </div>
      <div id="main-sidebar"><div class="flw-item">
        <h3 class="film-name"><a href="/watch/sidebar-only" title="Sidebar">Sidebar</a></h3>
      </div></div>
    ''';

    test('reads every result before the sidebar', () {
      final results = AnimeStreamService.parseSearchHtml(html);
      expect(results.map((result) => result.slug), [
        'naruto-1335',
        'boruto-naruto-next-generations-650',
      ]);
    });

    test('captures title, artwork, type, duration and episode count', () {
      final first = AnimeStreamService.parseSearchHtml(html).first;
      expect(first.title, 'Naruto');
      expect(first.japaneseTitle, 'NARUTO');
      expect(first.posterUrl, 'https://cdn.example/naruto.jpg');
      expect(first.type, 'TV');
      expect(first.duration, '23m');
      expect(first.episodeCount, 220);
    });

    test('ignores malformed blocks instead of throwing', () {
      expect(
        AnimeStreamService.parseSearchHtml(
          '<div class="flw-item"><h3 class="film-name">no anchor</h3></div>',
        ),
        isEmpty,
      );
    });
  });

  group('parseEpisodeList', () {
    final apiBody = jsonEncode({
      'status': true,
      'html': '''
        <div class="ss-list">
          <a class="ep-item" data-number="2" data-id="22677" href="https://hianime.at/watch/naruto-1335?ep=22677">
            <div class="ssli-order">2</div>
            <div class="ssli-detail"><p>Enter the Ninja</p></div>
          </a>
          <a class="ep-item ssl-item-filler" data-number="1" data-id="22676" href="https://hianime.at/watch/naruto-1335?ep=22676">
            <div class="ssli-order">1</div>
            <div class="ssli-detail"><p>Prologue</p></div>
          </a>
          <a class="ep-item" data-number="3" data-id="22678" href="https://hianime.at/watch/other-show-9?ep=22678"></a>
        </div>
      ''',
    });

    test('unwraps the JSON payload and sorts episodes by number', () {
      final episodes = AnimeStreamService.parseEpisodeList(
        apiBody,
        'naruto-1335',
      );
      expect(episodes.map((episode) => episode.number), [1, 2]);
      expect(episodes.map((episode) => episode.id), ['22676', '22677']);
    });

    test('keeps the episode titles from the markup', () {
      final episodes = AnimeStreamService.parseEpisodeList(
        apiBody,
        'naruto-1335',
      );
      expect(episodes.first.title, 'Prologue');
      expect(episodes.first.filler, isTrue);
    });

    test('flags missing streams as empty', () {
      expect(
        AnimeStreamService.parseEpisodeList('<div></div>', 'x-1'),
        isEmpty,
      );
    });
  });

  group('parseServerHash', () {
    final body = jsonEncode({
      'html': '''
        <div class="ps_-block">
          <a class="server-item" data-type="sub" data-server-name="HD-1" data-hash="wrong"></a>
          <a class="server-item" data-type="dub" data-server-name="ZokoAnime" data-hash="dubhash"></a>
          <a class="server-item" data-type="sub" data-server-name="ZokoAnime" data-hash="subhash"></a>
        </div>
      ''',
    });

    test('picks the sub hash of the preferred server', () {
      expect(AnimeStreamService.parseServerHash(body, 'sub'), 'subhash');
    });

    test('picks the dub hash of the preferred server', () {
      expect(AnimeStreamService.parseServerHash(body, 'dub'), 'dubhash');
    });

    test('returns null when the server is absent', () {
      expect(AnimeStreamService.parseServerHash(body, 'raw'), isNull);
    });
  });

  group('deobfuscateEmbed', () {
    test('reverses the XOR obfuscation', () {
      const plain = '{"sources":[{"src":"https://cdn.example/master.m3u8"}]}';
      expect(AnimeStreamService.deobfuscateEmbed(_xorEmbed(plain)), plain);
    });
  });

  group('parseEmbedConfig', () {
    test('prefers the JSON playlist and default subtitle', () {
      final resolved = AnimeStreamService.parseEmbedConfig(
        '{"sources":[{"src":"https://cdn.example/master.m3u8?x=1"}],'
        '"tracks":[{"src":"https://cdn.example/other.vtt"},'
        '{"default":true,"src":"https://cdn.example/ep1.vtt"}]}',
      );
      expect(resolved.playlistUrl, 'https://cdn.example/master.m3u8?x=1');
      expect(resolved.subtitleUrl, 'https://cdn.example/ep1.vtt');
    });

    test('falls back to regex matching for non-JSON embeds', () {
      final resolved = AnimeStreamService.parseEmbedConfig(
        r'var config = {"src":"https:\/\/cdn.example\/master.m3u8"};'
        r' track {"src":"https:\/\/cdn.example\/ep2.vtt"}',
      );
      expect(resolved.playlistUrl, 'https://cdn.example/master.m3u8');
      expect(resolved.subtitleUrl, 'https://cdn.example/ep2.vtt');
    });

    test('reports no playlist when the embed is unplayable', () {
      final resolved = AnimeStreamService.parseEmbedConfig('{"sources":[]}');
      expect(resolved.playlistUrl, isNull);
    });
  });

  group('parseAniListSeasons', () {
    final payload = {
      'data': {
        'Media': {
          'relations': {
            'edges': [
              {
                'relationType': 'SEQUEL',
                'node': {
                  'type': 'ANIME',
                  'format': 'TV',
                  'episodes': 220,
                  'seasonYear': 2007,
                  'title': {'romaji': 'Naruto Shippuden', 'english': null},
                  'coverImage': {'medium': 'https://img.example/shippuden.jpg'},
                },
              },
              {
                'relationType': 'PREQUEL',
                'node': {
                  'type': 'ANIME',
                  'format': 'TV',
                  'episodes': 26,
                  'seasonYear': 2002,
                  'title': {'romaji': 'Naruto', 'english': 'Naruto'},
                  'coverImage': {'medium': 'https://img.example/naruto.jpg'},
                },
              },
              {
                'relationType': 'CHARACTER',
                'node': {
                  'type': 'ANIME',
                  'format': 'TV',
                  'title': {'romaji': 'Ignored'},
                },
              },
              {
                'relationType': 'SIDE_STORY',
                'node': {
                  'type': 'MANGA',
                  'format': 'TV',
                  'title': {'romaji': 'Also ignored'},
                },
              },
            ],
          },
        },
      },
    };

    test('keeps anime relations and sorts them by year', () {
      final seasons = AnimeStreamService.parseAniListSeasons(payload);
      expect(seasons.map((season) => season.title), [
        'Naruto',
        'Naruto Shippuden',
      ]);
      expect(seasons.first.year, 2002);
      expect(seasons.last.episodeCount, 220);
    });

    test('builds a readable chip label', () {
      final seasons = AnimeStreamService.parseAniListSeasons(payload);
      expect(seasons.first.label, 'Naruto (2002)');
    });

    test('survives an empty payload', () {
      expect(
        AnimeStreamService.parseAniListSeasons(const {'data': null}),
        isEmpty,
      );
    });
  });

  group('serverHashes', () {
    final body =
        '{"status":true,"html":"<div class=\\"item server-item\\" data-type=\\"sub\\" data-server-name=\\"HD-1\\" data-hash=\\"aGQx\\"></div><div class=\\"item server-item\\" data-type=\\"sub\\" data-server-name=\\"ZokoAnime\\" data-hash=\\"em9rbw==\\"></div><div class=\\"item server-item\\" data-type=\\"dub\\" data-server-name=\\"ZokoAnime\\" data-hash=\\"ZHVi\\"></div>"}';

    test('prefers the ZokoAnime server for the requested mode', () {
      expect(AnimeStreamService.serverHashes(body, 'sub'), [
        'em9rbw==',
        'aGQx',
      ]);
    });

    test('only returns servers in the requested mode', () {
      expect(AnimeStreamService.serverHashes(body, 'dub'), ['ZHVi']);
    });

    test('returns nothing when no server matches', () {
      expect(AnimeStreamService.serverHashes(body, 'raw'), isEmpty);
    });
  });
}
