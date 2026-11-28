import 'package:flutter_test/flutter_test.dart';
import 'package:musico/services/hls_playlist.dart';

void main() {
  group('HlsPlaylist.parse', () {
    const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Italian",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ita",URI="a.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",DEFAULT=NO,LANGUAGE="eng",URI="b.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="eng",URI="c.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360,AUDIO="audio"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720,AUDIO="audio"
720/index.m3u8
''';

    test('reads video renditions sorted by height', () {
      final playlist = HlsPlaylist.parse(master);
      expect(playlist.variants.length, 2);
      expect(playlist.variants.first.label, '720p');
      expect(playlist.variants.first.bandwidth, 1800000);
      expect(playlist.variants.last.uri, '360/index.m3u8');
    });

    test('reads audio renditions but not subtitles', () {
      final playlist = HlsPlaylist.parse(master);
      expect(playlist.audioTracks.map((t) => t.name), ['Italian', 'English']);
      expect(playlist.audioTracks.first.language, 'ita');
      expect(playlist.audioTracks.first.isDefault, isTrue);
    });

    test('returns an empty playlist for a media playlist', () {
      final playlist = HlsPlaylist.parse(
        '#EXTM3U\n#EXT-X-TARGETDURATION:6\nsegment1.ts',
      );
      expect(playlist.isEmpty, isTrue);
    });

    test('ignores a body that is not a playlist', () {
      expect(HlsPlaylist.parse('<html>nope</html>').isEmpty, isTrue);
    });

    test('keeps a bandwidth-only rendition readable', () {
      const body =
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=5000000\nhigh/index.m3u8';
      final playlist = HlsPlaylist.parse(body);
      expect(playlist.variants.single.label, '5.0 Mbps');
    });
  });
}
